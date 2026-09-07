---
title: "流式与实时响应"
weight: 2
description: "bouine 如何流式传输响应体、服务 Server-Sent Events，以及在源站缓慢时卸载过量负载。"
---

bouine 从不进行不必要的响应体缓冲。本页描述三种流式行为，以及与
之交互的两项过载保护。

## Server-Sent Events（SSE）

bouine 将 Server-Sent Events 作为**端到端的实时流**服务。携带
`Accept: text/event-stream` 的请求（WHATWG 客户端契约——浏览器、
`EventSource` 和 AI SDK 的行为）以无缓冲流的方式服务：永不缓存、
永不被 singleflight 合并到其他客户端的流上。

```yaml
routes:
  - match: { path_prefix: /chat/ }
    pool: llm
    cache:
      ttl_default: 60s
```

无需任何路由级配置：`Accept` 头即契约。基于 POST 的 SSE（AI API 的
主流形态——请求体后跟流式响应）同样适用，其[写方法失效](../cache-policy/#write-method-invalidation-postputdelete)
语义保持不变：2xx/3xx 响应在**收到响应头时**即清除受影响的缓存
条目，而非等待（无限的）响应体。

### SSE 服务契约

| 行为 | 说明 |
|---|---|
| `X-Cache` | `BYPASS` — 完全跳过缓存读取 |
| 存储 | 永不存储 |
| Singleflight | 永不合并；每个客户端获得自己的源站 fetch |
| Fetch 槽位 | 收到响应头时即释放——活跃流不占用 `max_fetch_concurrency` 槽位 |
| 刷新 | 每个事件到达即刷新给客户端 |
| 源站读取预算 | 10 分钟**空闲**预算，每个事件重置——活跃流永远不会被时钟切断 |
| 客户端写入预算 | 基于空闲（H1 fast path 上每次写入重置 5 分钟；未启用时为 1 小时绝对值） |

后两行是关键属性：源站持续发送事件的流无限期保持打开，而死掉的
对端或停止读取的客户端仍会被切断。

### 未声明的 SSE

源站可能对未携带 `Accept` 头的请求返回
`Content-Type: text/event-stream`。此类响应仍以无缓冲方式流式传输，
但**受该路由 `fetch_timeout` 的限制**（源站连接的读取截止时间在
得知响应是流之前就已设置）。应修正客户端使其发送该头，而不是
提高 `fetch_timeout`。同一 URL 的并发未声明请求不会合并到一个流上
——没有任何缓冲，因此不存在可共享的结果。

### SSE 路由调优

- **稀疏事件流**（间隔超过 10 分钟且无心跳）：无需调整。源站必须
  发送 SSE 注释行心跳，否则流在 10 分钟空闲预算后被切断，客户端
  会重连。
- **大量并发流**：每个流在其生命周期内占用一条客户端连接和一条
  源站连接。面向 SSE 密集路由的 pool 应提高
  `upstream_pools[].connect.max_connections`（默认 64），并为数据
  面提高 `listen.max_connections`。`max_fetch_concurrency` **无需**
  提高——流在收到响应头时即释放 fetch 槽位。
- **挂起的源站**：已声明的 fetch 若源站接受连接但从不发送响应头，
  会在 10 分钟空闲预算内占用一个 fetch 槽位（而非
  `response_header_timeout`）。只有显式声明流式意图的请求走此路径。

### 故障模式

| 症状 | 原因 |
|---|---|
| 流在约 10 分钟静默后结束 | 空闲预算触发——源站停止发送且无心跳 |
| 流恰好在 `fetch_timeout` 时结束 | 客户端未发送 `Accept: text/event-stream`（未声明路径） |
| 未启用 fast path 时流在 1 小时结束 | 普通 fasthttp 服务路径上的预期行为；启用 `experimental.h1_fast_path` 或依赖客户端重连 |
| 流开始时收到 `503 + Retry-After` | `fetch_wait_timeout` 内 fetch 队列已满——提高 `max_fetch_concurrency` 或排查源站延迟 |

## 流式 miss

可缓存的 miss 在后台将响应体 tee 到存储的同时流式传输给客户端，
客户端无需等待完整响应体即可收到首字节。Tee 缓冲受以下限制：

- 单流：`max_response_bytes`（超出即以 502 中止 fetch）。
- 单路由：`max_streaming_buffer_bytes`——该路由所有并发 miss fetch
  持有的活跃 tee 缓冲总字节数。超限时，新的可缓存 miss 回退为同步
  缓冲（客户端等待完整响应体，缓冲不再活跃）。默认值从 GOMEMLIMIT
  推导（7%），内置下限 64 MiB。可通过
  `bouine_streaming_buffer_bytes` 和 `bouine_streaming_fallback_total`
  观察压力。

## 源站 fetch 卸载

源站缓慢是反向代理的经典故障模式：请求 goroutine 等待 fetch 槽位
而无限堆积，pod 进入无法自恢复的活锁。bouine 选择卸载。

当前台 miss 无法在 `fetch_wait_timeout`（默认 100ms，校验上限 1s）
内获取源站 fetch 槽位（由每路由 `max_fetch_concurrency` 限定）时：

1. **作用域内存在过期对象则直接用过期对象服务**（RFC 5861 风格），或
2. 客户端收到 **503 + `Retry-After: 1`**——与源站故障的 502 映射不同。

Singleflight 跟随者与进行中流的跟随者以 leader 的卸载结果一并解除
阻塞。`bouine_fetch_shed_total` 计数器暴露卸载率用于告警。

```yaml
routes:
  - match: { path_prefix: / }
    pool: app
    cache:
      max_fetch_concurrency: 32
      fetch_wait_timeout: 100ms
```

等待上限存在的意义是吸收亚秒级的 fetch 队列突发，而非在持续过载
中排队：当到达速率超过排空速率时，任何有限等待都无法排空队列，
更长的上限只会让 goroutine（及其连接）在卸载前被更久地挂住。
应提高 `max_fetch_concurrency` 或横向扩容，而非提高
`fetch_wait_timeout`。
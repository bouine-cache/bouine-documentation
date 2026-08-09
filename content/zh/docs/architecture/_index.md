---
title: "架构"
weight: 4
description: "bouine 内部结构：监听器、管道、存储、缓存引擎、上游池、集群和可观测性。"
---


## 分层设计

bouine 由 8 层组成，每层可独立测试。

{{< arch-diagram >}}

## HTTP 协议栈

单一 HTTP 实现：

- **`net/http`** — HTTP/1.1 + HTTP/2（数据面 + 管理面）

管理 API 使用 `net/http.ServeMux`。

## 缓存引擎

RFC 9111 状态机是确定性的：输入为 `*http.Request`、存储的 `*Object` 和 `now`。输出为 `HIT`、`MISS`、`REVALIDATE`、`STALE_HIT` 或 `BYPASS`。

### 缓存键

主键：`xxhash64(scheme | host | path | sorted_query | method)`

次键（Vary）：从响应 `Vary` 头中列出的请求头派生，或从 `cache.key.include_headers` 派生。

### 淘汰

- **SIEVE** — 简单，命中率接近 LRU-K，每次操作 O(1)

### CDN-Cache-Control (RFC 9211)

当源站发送 `CDN-Cache-Control` 时，它覆盖 `Cache-Control` 用于所有共享缓存决策：

```http
Cache-Control: no-store
CDN-Cache-Control: max-age=3600
```

### 替代键

源站可以用替代键标记响应以进行分组失效：

```http
Surrogate-Key: product-456 category-shoes
Cache-Tag: product-456, category-shoes
```

bouine 在存储时读取 `Surrogate-Key`、`Cache-Tag` 和 `X-Cache-Tags`，并可通过 `POST /v1/ban{surrogate_key:"..."}` 进行失效。

### 负缓存

404、405、410、501 响应可以以可配置的持续时间缓存（`negative_ttl`）。

### TTL 抖动

每个 TTL 应用 ±N% 随机抖动，防止缓存条目之间同步过期导致的请求洪峰。

## 集群

bouine 支持两种一致性模式（参见[集群](/docs/configuration/cluster-modes/)）：

### Strong 模式（默认）

**分片**：一致性哈希，每个真实节点 256 个虚拟节点。未命中时，请求节点在访问源站前先检查拥有者节点。

### Eventual 模式

每个节点独立 — 无分片，无 peer fetch。失效仅通过 gossip 传播。

### 成员管理（所有模式）

使用 `hashicorp/memberlist` 进行 gossip。节点通过 StatefulSet DNS 引导。

### Peer-fetch 流程（仅 Strong 模式）

{{< peer-fetch-diagram >}}

Peer hit 增加延迟：~0.3ms（集群内单跳 HTTP/2）。

### Stale-while-revalidate (SWR)

当对象进入 `stale-while-revalidate` 窗口时，bouine：

1. 立即提供过期对象（客户端无等待）。
2. 触发后台 goroutine（`bgRevalSem` 限制并发为 256）与源站进行条件重新验证。
3. 源站响应（200 或 304）更新 hot store；下次请求获得新鲜 `HIT`。

### 失效传播

| 操作 | `strong` | `eventual` | `full` |
|---|---|---|---|
| **Purge** | HTTP 扇出到所有 peer + gossip | 仅 gossip（1–5s 收敛） | HTTP 扇出到所有 peer + gossip |
| **Ban** | HTTP 扇出到所有 peer + gossip | 仅 gossip | HTTP 扇出到所有 peer + gossip |
| **Refresh** | 转发给键拥有者节点 | 仅 gossip | HTTP 扇出到所有 peer |

### 加入协议

Pod 每 2 秒重试加入，持续最多 60 秒。成功需要 `Members() > 1`。headless Service **必须**设置 `publishNotReadyAddresses: true`。

## 性能

| Benchmark | 结果 |
|---|---|
| `Evaluate_Hit` | 40 ns/op, 0 alloc |
| `HotStore_Get_Hit` | 5.4 ns/op, 0 alloc |
| `Handler_CacheHit` | 537 ns/op, 8 allocs |
| `BuildKey` (query params) | 46 ns/op, 0 alloc |
| `SIEVE_Access` | 5.4 ns/op, 0 alloc |

负载测试结果（Docker，3k RPS，单节点 vs Varnish + nginx）：

| 场景 | bouine | nginx | varnish |
|---|---|---|---|
| 纯命中（热缓存） | 166 µs 平均 | 166 µs 平均 | 177 µs 平均 |
| 未命中风暴（no-store） | 157 µs 平均 | 降级 | 166 µs 平均 |
| 混合 60/15/10/5/5 | 230 µs 平均 | 22 ms 平均† | 199 µs 平均 |

†nginx 混合平均值高是由于阻塞式重新验证；bouine 和 Varnish 都使用后台 SWR 刷新。

---
title: "响应头"
weight: 93
description: "bouine 添加的 HTTP 响应头。"
---

## X-Cache

指示响应的返回方式。

| 值 | 描述 |
|-------|-------------|
| `HIT` | 从缓存返回（新鲜） |
| `MISS` | 从源站获取并已缓存 |
| `STALE` | 从缓存返回（过期，在 stale-while-revalidate 或 stale-if-error 窗口内） |
| `BYPASS` | 绕过缓存（no-store、no-cache、路由禁用缓存，或 SSE 请求） |
| `REVALIDATED` | 向源站的条件请求返回 304，从缓存返回并更新新鲜度 |

```bash
curl -sI http://localhost:8080/get | grep x-cache
# X-Cache: HIT
```

## Age

缓存对象的年龄（秒），计算自原始响应的 `Date` 头加上在
上游转发代理中花费的时间。每次缓存命中时更新。

```bash
curl -sI http://localhost:8080/get | grep age
# Age: 42
```

## X-Cache-Source

指示由哪个存储层返回了响应。

| 值 | 描述 |
|-------|-------------|
| `hot` | 从 RAM 热层（L0）返回 |
| `warm` | 从 mmap 温层（L1）返回 |
| `peer` | 通过 peer fetch 从集群节点返回 |
| `origin` | 从上游源站获取 |
| _(空)_ | 非由存储层返回（BYPASS 或 only-if-cached 504） |

## X-Bouine-Route

匹配请求的路由标签。用于仪表板的逐路由归因与访问日志。它不再是
Prometheus 标签：自 v0.5.8 起，数据面 RED 指标改为按 `upstream_pool`
（由配置限定的小集合）归因，而非路由名；参见
[监控](/docs/operations/monitoring/#traffic-red)。

## X-Bouine-Pool

所服务路由的 upstream pool。由路由器以进程本地值的形式设置，被
指标中间件用作 `upstream_pool` Prometheus 标签；入站头形式原样
转发。无 pool 的路由（静态、catch-all）上报为 `_default`。

---
title: "响应头"
weight: 93
description: "bouine 添加的 HTTP 响应头。"
---

## X-Cache

指示响应的提供方式。

| 值 | 描述 |
|-------|-------------|
| `HIT` | 从缓存提供（新鲜） |
| `MISS` | 从源站获取并已缓存 |
| `STALE` | 从缓存提供（过期，在 stale-while-revalidate 或 stale-if-error 窗口内） |
| `BYPASS` | 绕过缓存（no-store、no-cache 或路由禁用缓存） |
| `REVALIDATED` | 向源站的条件请求返回 304，从缓存提供并更新新鲜度 |

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

指示由哪个存储层提供了响应。

| 值 | 描述 |
|-------|-------------|
| `hot` | 从 RAM 热层（L0）提供 |
| `warm` | 从 mmap 温层（L1）提供 |
| `peer` | 通过 peer fetch 从集群节点提供 |
| `origin` | 从上游源站获取 |
| _(空)_ | 非存储层提供（BYPASS 或 only-if-cached 504） |

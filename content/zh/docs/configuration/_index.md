---
title: "配置"
weight: 2
description: "bouine YAML 配置参考：监听器、存储、upstream pool、路由、缓存、集群、TLS 和可观测性。"
---

bouine 通过 `--config` 传递的 YAML 文件配置。环境变量在解码前展开（`${VAR}`、`${VAR:-default}`）。

```yaml
listen:
  http: ":8080"
  https: ":443"
  admin: ":9000"

storage:
  hot_max_bytes: 1GiB

upstream_pools:
  - name: app
    targets: ["app.default.svc:8080"]
    health:
      active:
        path: /healthz
        interval: 10s

routes:
  - match: { path_prefix: /api/ }
    pool: app
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

## 本节页面

- [缓存策略](cache-policy/) — TTL 选择、覆盖、stale-while-revalidate、负缓存、抖动、缓存键。
- [流式与实时响应](streaming/) — SSE、流式 miss、fetch 槽位卸载与内存上限。
- [集群模式](cluster-modes/) — strong、eventual；headless Service；gossip。
- [Helm Chart](helm/) — Helm chart 可配置值。
- [静态文件服务](static-files/) — 无需源站从磁盘服务文件。
- [存储](storage/) — hot（RAM）和 warm（mmap）层、SIEVE 淘汰。
- [TLS](tls/) — TLS 终止、peer 间 mTLS、证书。
- [实验性功能](experimental/) — 可能变更的 opt-in 功能。

## v0.5.27–v0.5.29 新增配置

- **`routes[].match.path`** — 锚定 RE2 正则路径匹配，与 `path_prefix` 互斥；`match.host` 支持 `*.` 开头的通配符后缀匹配（v0.5.27）。
- **`routes[].request.forwarded`** — 在发往源站的请求上注入 `X-Forwarded-For`、`X-Forwarded-Proto`、`X-Forwarded-Host` 和 `Via`（v0.5.27）；可通过顶层 `route_defaults.request.forwarded` 一次性声明。
- **`routes[].cache.bypass_on_user_agent`** — 按 User-Agent glob 模式完全绕过缓存（v0.5.27）；`route_defaults.cache.bypass_on_user_agent` 一次性声明。
- **`routes[].cache.bypass_on_cookie_names`** — 请求携带名单中的 cookie 名即完全绕过缓存（v0.5.27）。
- **`routes[].cache.key.cookie_presence`** — 按 cookie 是否存在（而非其值）为 Vary 变体键贡献比特位（v0.5.27）。
- **`upstream_pools[].connect.preserve_host`** — 向源站转发时保留请求自身的 Host 头，拨号目标不变（v0.5.28）。
- **TCP Fast Open 三层面**：`listen.tcp_fast_open`（监听）、`upstream_pools[].connect.tcp_fast_open`（源站拨号）、`cluster.peer_tcp_fast_open`（peer 拨号）——**v0.5.29 起默认全部关闭**，需显式开启（仅 Linux）。
- **`cluster.peer_fetch_concurrency`** — 每节点并发 peer-fetch/put RPC 上限的默认值从 4 提升到 16（v0.5.29）。
- **`metrics.traffic_classes`** — 按主机模式声明最多 8 个命名流量群体，为数据面指标添加 `traffic_class` 标签（v0.5.27）。
- **`ttl_override`** — 自 v0.5.29 仅作用于成功与重定向响应（status < 400）；可缓存的错误响应按负缓存 TTL 阶梯过期。

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
- [集群模式](cluster-modes/) — strong、eventual；headless Service；gossip。
- [Helm Chart](helm/) — Helm chart 可配置值。
- [静态文件服务](static-files/) — 无需源站从磁盘服务文件。
- [存储](storage/) — hot（RAM）和 warm（mmap）层、SIEVE 淘汰。
- [TLS](tls/) — TLS 终止、peer 间 mTLS、证书。
- [实验性功能](experimental/) — 可能变更的 opt-in 功能。

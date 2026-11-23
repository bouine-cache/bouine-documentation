---
title: "Configuration"
weight: 2
description: "Reference for bouine YAML configuration: listeners, storage, routes, cache policy, TLS, clustering, Helm chart values, and health checks."
---


bouine is configured via a YAML file passed with `--config`. Environment variable interpolation is supported: `${VAR}` is replaced with the value of `VAR`, and `${VAR:-default}` provides a fallback. `$$` escapes to a literal `$`.

## Pages in this section

- [Cache policy](cache-policy/) — TTL selection, stale serving, negative caching, jitter, refresh-before-expiry, and cache keys.
- [Streaming and live responses](streaming/) — SSE, streaming misses, fetch-slot shedding, and memory caps.
- [Static file serving](static-files/) — serve files from a local directory instead of an upstream pool.
- [Storage tiers](storage/) — hot and warm tiers, eviction, sizing guidelines.
- [TLS](tls/) — certificates, SNI, and automatic reload.
- [Clustering](cluster-modes/) — consistency modes, gossip, peer fetch, mTLS, invalidation, verification and troubleshooting.
- [Experimental features](experimental/) — opt-in features like the H1 fast path.
- [Helm chart reference](helm/) — all `values.yaml` keys with defaults.
- [YAML configuration reference](/docs/reference/config/) — exhaustive field-by-field reference for every top-level key.

## Minimal working config

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 256MiB

upstream_pools:
  - name: app
    targets: ["app.default.svc:8080"]

routes:
  - match: { path_prefix: / }
    pool: app
    cache:
      ttl_default: 60s
```

## Full example

```yaml
listen:
  http: ":80"
  https: ":443"
  admin: ":9000"
  cluster: ":8443"

tls:
  certs:
    - cert_file: /etc/bouine/tls/cert.pem
      key_file: /etc/bouine/tls/key.pem
      sni: ["example.com", "*.example.com"]
  min_version: "1.2"

storage:
  hot_max_bytes: 2GiB
  warm_dir: /var/lib/bouine
  warm_max_bytes: 50GiB

cluster:
  join:
    - "bouine-0.bouine-headless.ns.svc.cluster.local:8443"
    - "bouine-1.bouine-headless.ns.svc.cluster.local:8443"
    - "bouine-2.bouine-headless.ns.svc.cluster.local:8443"
  hop_limit: 2

upstream_pools:
  - name: api
    targets: [api.default.svc:8080]
    tls:
      enabled: false
    health:
      active:
        path: /healthz
        interval: 5s
        timeout: 1s
        unhealthy_threshold: 3
      passive:
        consecutive_5xx: 5
    connect:
      timeout: 10s
      keep_alive: 15s

routes:
  - match: { host: "api.example.com", path_prefix: /v1/ }
    pool: api
    cache:
      ttl_default: 60s
      stale_while_revalidate: 30s
      stale_if_error: 300s
      negative_ttl: 5s
      jitter_percent: 10
      refresh_before_expiry: true
      refresh_margin_percent: 20
      refresh_timeout: 5s
      refresh_concurrency: 16
      refresh_min_hits: 3
      refresh_persist_cycles: 2
      refresh_min_score: 1048576
      refresh_max_rps: 100
      refresh_reactive_first: true
      key:
        include_headers:
          - Accept-Language
        exclude_headers:
          - x-request-id
          - x-trace-id
          - x-forwarded-for
```

The exhaustive field-by-field reference for every key above (listen, storage, cluster, routes, upstream pools, metrics, admin, tracing, cloudflare, experimental) lives in [YAML configuration reference](/docs/reference/config/).

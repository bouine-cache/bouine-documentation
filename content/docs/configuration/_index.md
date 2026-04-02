---
title: "Configuration"
weight: 2
description: "Reference for bouine YAML configuration: listeners, storage, routes, cache policy, clustering, and health checks."
---


bouine is configured via a YAML file passed with `--config`. Environment variable interpolation is not supported — use Kubernetes ConfigMaps or Helm values for templating.

## Full example

```yaml
listen:
  http: ":80"
  https: ":443"
  http3: ":443/udp"
  admin: ":9000"
  cluster: ":8443"

tls:
  certs:
    - cert_file: /etc/bouine/tls/cert.pem
      key_file: /etc/bouine/tls/key.pem
      sni: ["example.com", "*.example.com"]
  alpn: [h2, http/1.1]
  min_version: "1.2"
  reload:
    fsnotify: true
    sighup: true

storage:
  hot_max_bytes: 2GiB
  warm_dir: /var/lib/bouine
  warm_max_bytes: 50GiB
  eviction: sieve

cluster:
  enabled: true
  join:
    - "bouine-0.bouine-headless.ns.svc.cluster.local:8443"
    - "bouine-1.bouine-headless.ns.svc.cluster.local:8443"
    - "bouine-2.bouine-headless.ns.svc.cluster.local:8443"
  replicas: 2
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
      key:
        include_headers:
          - Accept-Language
```

## Sections

### `listen`

| Field | Default | Description |
|---|---|---|
| `http` | `":80"` | HTTP/1.1 + h2c plaintext listener |
| `https` | `""` | HTTPS (TLS) listener |
| `http3` | `""` | HTTP/3 (QUIC, UDP) listener |
| `admin` | `":9000"` | Admin API (health, metrics, purge) |
| `cluster` | `""` | Gossip cluster port |

### `storage`

| Field | Default | Description |
|---|---|---|
| `hot_max_bytes` | - | RAM cache size. Accepts `MiB`, `GiB`, `KiB`, `TiB` (IEC binary) or `MB`, `GB`, `KB`, `TB` (decimal SI). Example: `2GiB`. |
| `warm_dir` | `""` | Path for mmap warm-tier segments. Empty disables. |
| `warm_max_bytes` | `""` | Max warm-tier disk usage |
| `eviction` | `sieve` | Eviction algorithm. `sieve` (default, recommended). `w-tinylfu` is planned for Phase 5.5. |

### `cluster`

| Field | Default | Description |
|---|---|---|
| `enabled` | `false` | Enable gossip clustering |
| `join` | `[]` | Seed addresses (StatefulSet pod DNS) |
| `replicas` | `1` | Write replication factor |
| `hop_limit` | `2` | Max peer-fetch hops before origin fallback |
| `tls.ca_bundle` | `""` | CA certificate path for peer-to-peer mTLS. Empty = plain HTTP. |
| `tls.cert_file` | `""` | Client certificate for mTLS |
| `tls.key_file` | `""` | Client private key for mTLS |

### `routes[]`

| Field | Default | Description |
|---|---|---|
| `name` | `""` | Human-readable label used in Prometheus `route` label and the dashboard. Defaults to `host:path_prefix` when empty. |
| `match.host` | `""` | Match on `Host` header (empty = any) |
| `match.path_prefix` | `""` | Match on URL path prefix (empty = any) |
| `pool` | — | Upstream pool name |

### `routes[].cache`

| Field | Default | Description |
|---|---|---|
| `ttl_default` | `0` | Default TTL when origin has no `Cache-Control` |
| `stale_while_revalidate` | `0` | Serve stale while refreshing in background |
| `stale_if_error` | `0` | Serve stale on origin 5xx |
| `negative_ttl` | `0` | Cache 404/405/410/501 responses for this duration |
| `jitter_percent` | `0` | Random ±N% on TTLs to prevent stampedes (0–50) |
| `stayin_alive` | `false` | Serve stale indefinitely when upstream is down (see [Stayin Alive](/docs/configuration/cache-policy/#stayin-alive)) |

### `routes[].cache.key`

| Field | Default | Description |
|---|---|---|
| `include_headers` | `[]` | Headers to include in cache key (replaces Vary) |

### `upstream_pools[].connect`

| Field | Default | Description |
|---|---|---|
| `timeout` | `10s` | TCP dial timeout |
| `keep_alive` | `15s` | TCP keep-alive interval |
| `hedge_timeout` | `""` | Fire a duplicate request after this duration; first response wins (hedged fetch). Empty disables. |

### Health checks

Active health probes the upstream periodically. Passive ejects after consecutive failures.

```yaml
health:
  active:
    path: /healthz
    method: GET          # default
    interval: 5s
    timeout: 1s
    healthy_threshold: 1
    unhealthy_threshold: 3
    expected_status_codes: [200]
  passive:
    consecutive_5xx: 5
    eject_for: 30s
```


### `tracing`

Configure OpenTelemetry span export. Leave `endpoint` empty (default) to disable tracing.

| Field | Default | Description |
|---|---|---|
| `endpoint` | `""` | OTLP/HTTP collector URL, e.g. `http://otel-collector:4318`. Empty disables. |
| `service_name` | `"bouine"` | `service.name` OTel resource attribute |
| `sampling_rate` | `1.0` | Fraction of requests to sample (0.0–1.0) |

### `prefetch`

Background cache warming via `Link: rel=preload` response headers and optional sitemap crawling.

| Field | Default | Description |
|---|---|---|
| `sitemap_urls` | `[]` | Sitemap XML URLs to crawl periodically |
| `sitemap_interval` | `0` | Crawl interval. Zero disables sitemap crawling. |

## Hot reload

Reloadable without restart: routes, upstream pools, cache TTLs, TLS certificates.

**Not** reloadable: listen addresses, storage settings, cluster settings.

Trigger reload via:
- `kill -HUP <pid>`
- `curl -X POST http://localhost:9000/v1/config/reload`
- File change (fsnotify watches the config file)

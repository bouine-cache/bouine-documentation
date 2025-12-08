---
title: "Configuration"
weight: 2
bookCollapseSection: false
---

# Configuration reference

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
  hot_max_bytes: 2Go
  warm_dir: /var/lib/bouine
  warm_max_bytes: 50Go
  eviction: sieve       # or "w-tinylfu"

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
| `hot_max_bytes` | - | RAM cache size. Accepts `Mo`, `Go`, `Ko`, `To` (decimal) or `MiB`, `GiB` (binary). |
| `warm_dir` | `""` | Path for mmap warm-tier segments. Empty disables. |
| `warm_max_bytes` | `""` | Max warm-tier disk usage |
| `eviction` | `sieve` | Eviction algorithm: `sieve` or `w-tinylfu` |

### `cluster`

| Field | Default | Description |
|---|---|---|
| `enabled` | `false` | Enable gossip clustering |
| `join` | `[]` | Seed addresses (StatefulSet pod DNS) |
| `replicas` | `1` | Write replication factor |
| `hop_limit` | `2` | Max peer-fetch hops before origin fallback |

### `routes[].cache`

| Field | Default | Description |
|---|---|---|
| `ttl_default` | `0` | Default TTL when origin has no `Cache-Control` |
| `stale_while_revalidate` | `0` | Serve stale while refreshing in background |
| `stale_if_error` | `0` | Serve stale on origin 5xx |
| `negative_ttl` | `0` | Cache 404/405/410/501 responses for this duration |
| `jitter_percent` | `0` | Random ±N% on TTLs to prevent stampedes (0–50) |

### `routes[].cache.key`

| Field | Default | Description |
|---|---|---|
| `include_headers` | `[]` | Headers to include in cache key (replaces Vary) |

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

## Hot reload

Reloadable without restart: routes, upstream pools, cache TTLs, TLS certificates.

**Not** reloadable: listen addresses, storage settings, cluster settings.

Trigger reload via:
- `kill -HUP <pid>`
- `curl -X POST http://localhost:9000/v1/config/reload`
- File change (fsnotify watches the config file)

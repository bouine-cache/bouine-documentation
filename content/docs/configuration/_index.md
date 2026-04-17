---
title: "Configuration"
weight: 2
description: "Reference for bouine YAML configuration: listeners, storage, routes, cache policy, TLS, clustering, Helm chart values, and health checks."
---


bouine is configured via a YAML file passed with `--config`. Environment variable interpolation is not supported — use Kubernetes ConfigMaps or Helm values for templating.

## Pages in this section

- [Cache policy](cache-policy/) — TTL selection, stale serving, negative caching, jitter, and cache keys.
- [Storage tiers](storage/) — hot and warm tiers, eviction, sizing guidelines.
- [TLS](tls/) — certificates, SNI, ALPN, OCSP stapling, HTTP/3, and automatic reload.
- [Clustering](cluster-modes/) — consistency modes, gossip, peer fetch, mTLS, invalidation.
- [Helm chart reference](helm/) — all `values.yaml` keys with defaults.

## Minimal working config

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 256MiB
  eviction: sieve

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
  http3: ":443/udp"
  admin: ":9000"
  cluster: ":8443"
  proxy_protocol: false

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

## Field reference

### `listen`

| Field | Default | Description |
|---|---|---|
| `http` | `":80"` | HTTP/1.1 + h2c plaintext listener |
| `https` | `""` | HTTPS (TLS) listener. See [TLS](tls/). |
| `http3` | `""` | HTTP/3 (QUIC, UDP) listener |
| `admin` | `":9000"` | Admin API (health, metrics, purge) |
| `cluster` | `""` | Gossip cluster port |
| `proxy_protocol` | `false` | Parse PROXY Protocol v1/v2 headers on the HTTP/HTTPS listener |

### `storage`

| Field | Default | Description |
|---|---|---|
| `hot_max_bytes` | — | RAM cache size. See [size units](#size-units). Example: `2GiB`. |
| `warm_dir` | `""` | Path for mmap warm-tier segments. Empty disables. See [Storage tiers](storage/). |
| `warm_max_bytes` | `""` | Max warm-tier disk usage |
| `eviction` | `sieve` | Eviction algorithm. `sieve` (default, recommended). |

### `cluster`

| Field | Default | Description |
|---|---|---|
| `enabled` | `false` | Enable gossip clustering |
| `mode` | `strong` | Consistency mode: `strong`, `eventual`, or `full`. See [Clustering](cluster-modes/). |
| `join` | `[]` | Seed addresses (StatefulSet pod DNS) |
| `replicas` | `1` | Write replication factor (strong mode only) |
| `hop_limit` | `2` | Max peer-fetch hops before origin fallback (strong mode only) |
| `tls.ca_bundle` | `""` | CA certificate path for peer-to-peer mTLS. Empty = plain HTTP. |
| `tls.cert_file` | `""` | Client certificate for mTLS |
| `tls.key_file` | `""` | Client private key for mTLS |

### `routes[]`

Route matching uses `host` and `path_prefix` only. Regex-based path matching is not supported in routes — use `path_regex` in [ban predicates](/docs/operations/cache-invalidation/) for invalidation.

| Field | Default | Description |
|---|---|---|
| `name` | `""` | Human-readable label used in Prometheus `route` label and the dashboard. Defaults to `host:path_prefix` when empty. |
| `match.host` | `""` | Match on `Host` header (empty = any) |
| `match.path_prefix` | `""` | Match on URL path prefix (empty = any) |
| `pool` | — | Upstream pool name |

### `routes[].cache`

| Field | Default | Description |
|---|---|---|
| `enabled` | `true` | Set to `false` to bypass caching for this route |
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
| `hedge_timeout` | `""` | Fire a duplicate request after this duration; first response wins ([hedged fetch](#hedged-fetch)). Empty disables. |

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

### `admin`

| Field | Default | Description |
|---|---|---|
| `token` | `""` (auto-generated) | Admin bearer token. See [Authentication](/docs/operations/authentication/). |

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

When `sitemap_urls` is configured with a non-zero `sitemap_interval`, bouine periodically fetches each sitemap, extracts URLs, and warms the cache by issuing internal requests. This reduces cold-start miss rates after restarts.

bouine also parses `Link: </path>; rel=preload` response headers and prefetches the linked URLs in the background.

### `cloudflare`

Optional Cloudflare Cache API propagation. See [Cloudflare CDN propagation](/docs/operations/cloudflare/) for full details and Kubernetes secret wiring.

| Field | Default | Description |
|---|---|---|
| `zone_id` | `""` | Cloudflare zone identifier (non-secret) |
| `api_token` | `""` | Cache Purge API token. Prefer `CF_API_TOKEN` env var. |
| `async` | `true` | Return immediately; CF call runs in background goroutine |
| `timeout` | `10s` | Per-call timeout for CF API requests |
| `propagate.purge` | `true` | Forward `POST /v1/purge` to CF `PurgeSingleFile` |
| `propagate.ban` | `true` | Forward `POST /v1/ban` to CF (tags / prefixes / hostnames) |
| `propagate.refresh` | `true` | Forward `POST /v1/refresh` to CF `PurgeSingleFile` |

---

## Hedged fetch

When `hedge_timeout` is set on an upstream pool, bouine fires a duplicate request to the origin after the specified duration if the first request hasn't responded. The first response to arrive wins; the other is discarded.

```yaml
upstream_pools:
  - name: api
    targets: [api.default.svc:8080]
    connect:
      hedge_timeout: 50ms
```

Use hedging when your origin has occasional high-latency outliers (p99 >> p50). It trades a small amount of extra origin load for significantly better tail latency. Do **not** use hedging for non-idempotent requests or when origin load is already near capacity.

---

## Size units

All byte-size fields (`hot_max_bytes`, `warm_max_bytes`) accept any of these suffixes (case-insensitive):

| Suffix | Multiplier | Family |
|--------|-----------|--------|
| `B` | 1 | exact |
| `K`, `KB` | 10³ | SI decimal |
| `KiB`, `KI` | 1 024 | IEC binary |
| `Ko` | 10³ | French SI |
| `M`, `MB` | 10⁶ | SI decimal |
| `MiB`, `MI` | 1 048 576 | IEC binary |
| `Mo` | 10⁶ | French SI |
| `G`, `GB` | 10⁹ | SI decimal |
| `GiB`, `GI` | 1 073 741 824 | IEC binary |
| `Go` | 10⁹ | French SI |
| `T`, `TB` | 10¹² | SI decimal |
| `TiB`, `TI` | 2⁴⁰ | IEC binary |
| `To` | 10¹² | French SI |

> **Recommendation**: Use IEC binary units (`MiB`, `GiB`) for clarity. The Helm chart defaults use `GiB`.

---

## Hot reload

Reloadable without restart: routes, upstream pools, cache TTLs, TLS certificates.

**Not** reloadable: listen addresses, storage settings, cluster settings.

Trigger reload via:
- `kill -HUP <pid>`
- `curl -X POST http://localhost:9000/v1/config/reload -H "Authorization: Bearer <token>"`
- File change (fsnotify watches the config file automatically)

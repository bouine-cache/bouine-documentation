---
title: "Configuration"
weight: 2
description: "Reference for bouine YAML configuration: listeners, storage, routes, cache policy, TLS, clustering, Helm chart values, and health checks."
---


bouine is configured via a YAML file passed with `--config`. Environment variable interpolation is supported: `${VAR}` is replaced with the value of `VAR`, and `${VAR:-default}` provides a fallback. `$$` escapes to a literal `$`.

## Pages in this section

- [Cache policy](cache-policy/) — TTL selection, stale serving, negative caching, jitter, refresh-before-expiry, and cache keys.
- [Static file serving](static-files/) — serve files from a local directory instead of an upstream pool.
- [Storage tiers](storage/) — hot and warm tiers, eviction, sizing guidelines.
- [TLS](tls/) — certificates, SNI, and automatic reload.
- [Clustering](cluster-modes/) — consistency modes, gossip, peer fetch, mTLS, invalidation.
- [Experimental features](experimental/) — opt-in features like the H1 fast path.
- [Helm chart reference](helm/) — all `values.yaml` keys with defaults.

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

## Field reference

### `listen`

| Field | Default | Description |
|---|---|---|
| `http` | `":80"` | HTTP/1.1 + h2c plaintext listener |
| `https` | `""` | HTTPS (TLS) listener. See [TLS](tls/). |
| `admin` | `":9000"` | Admin API (health, metrics, purge) |
| `cluster` | `""` | Gossip cluster port |
| `max_connections` | `0` | Max concurrent data-plane connections (0 = unlimited). Protects against FD exhaustion. |
| `tcp_fast_open` | `true` (Linux) | Enable TCP_FASTOPEN on data-plane listeners. Defaults to true on Linux, no-op elsewhere. |
| `tcp_defer_accept` | `true` (Linux) | Enable TCP_DEFER_ACCEPT on data-plane listeners. Defaults to true on Linux, no-op elsewhere. |
| `reuse_port` | `true` (Linux) | Enable SO_REUSEPORT on data-plane listeners (N parallel accept loops). Defaults to true on Linux, false on other platforms. |

### `storage`

| Field | Default | Description |
|---|---|---|
| `hot_max_bytes` | — | RAM cache size. See [size units](#size-units). Example: `2GiB`. |
| `hot_mmap_slab` | `false` | Use mmap slab allocator for hot body bytes (reduces GC pressure, Linux only) |
| `warm_dir` | `""` | Path for mmap warm-tier segments. Empty disables. See [Storage tiers](storage/). |
| `warm_max_bytes` | `""` | Max warm-tier disk usage |
| `warm_max_entries` | — (auto) | Max warm-tier entry count. Auto-derived from GOMEMLIMIT when unset. |
| `warm_max_disk_bytes` | `""` | Max total warm-tier disk usage (all segments) |
| `min_free_disk` | `""` | Minimum free disk space before warm writes are paused |
| `warm_preallocate` | `0` | Preallocate warm-tier segment files totaling this size at startup. Eliminates disk amplification from append-only segments. Zero = create on demand. |
| `compact_interval` | `30m` | Interval between warm-tier compaction sweeps. Set to `-1` to disable periodic compaction (not recommended). |
| `body_threshold` | `64KiB` | Body size threshold for warm-tier admission. Objects larger than this are written to warm on every Put; smaller objects only by the background sync loop. |
| `warm_sync_interval` | `60s` | Interval between hot-to-warm sync batches |
| `warm_sync_batch_size` | `5000` | Max objects per warm sync batch |
| `wal_sync_interval` | `100ms` | WAL fsync interval (async batching) |
| `compact_startup_delay` | `5m` | Delay before first compaction on startup. Prevents I/O contention with WAL replay and cluster join. Set to `-1` to start immediately. |
| `checkpoint_interval` | `5m` | Warm-tier checkpoint interval |
| `checkpoint_wal_threshold` | `100000` | WAL entry count that triggers a checkpoint, regardless of interval. Bounds WAL replay time on unclean restart. |
| `segment_cache_size` | `0` (auto) | Number of warm-tier segment files to keep mmap-ed. 0 = auto (min(segCount, 256)). `-1` = unlimited (no eviction). |
| `tombstone_queue_size` | `65536` | Tombstone queue depth for warm-tier deletions. Increasing this reduces drops under bursty eviction pressure. |
| `tombstone_drain_interval` | `1s` | Interval between tombstone drain sweeps. Set to `-1` to disable the dedicated drain goroutine. |

### `cluster`

| Field | Default | Description |
|---|---|---|
| `mode` | `strong` | Consistency mode: `strong` or `eventual`. The cluster is enabled when `listen.cluster` is set. See [Clustering](cluster-modes/). |
| `join` | `[]` | Seed addresses (StatefulSet pod DNS) |
| `hop_limit` | `2` | Max peer-fetch hops before origin fallback (strong mode only) |
| `join_timeout` | `120s` | Max time to wait for cluster join. In strong mode, the pod stays not-ready if join fails. In eventual mode, the pod becomes ready and retries in the background. |
| `handoff_queue_depth` | `4096` | Memberlist per-peer message buffer. Absorbs bursts of cache invalidations. Negative values are rejected. |
| `tls.ca_bundle` | `""` | CA certificate path for peer-to-peer mTLS. Empty = plain HTTP. |
| `tls.cert_file` | `""` | Client certificate for mTLS |
| `tls.key_file` | `""` | Client private key for mTLS |

### `routes[]`

Route matching uses `host`, `path_prefix`, and optionally `methods`. Routes are matched in declaration order; the first match wins. Regex-based path matching is not supported in routes — use `path_regex` in [ban predicates](/docs/operations/cache-invalidation/) for invalidation.

A route must specify exactly one of `pool` or `static.root`. The former proxies to an upstream pool; the latter serves files from a local directory. See [Static file serving](static-files/).

| Field | Default | Description |
|---|---|---|
| `name` | `""` | Human-readable label used in Prometheus `route` label and the dashboard. Defaults to `host:path_prefix` when empty. |
| `match.host` | `""` | Match on `Host` header (empty = any) |
| `match.path_prefix` | `""` | Match on URL path prefix (empty = any) |
| `match.methods` | `[]` | Restrict to listed HTTP methods, e.g. `[GET, HEAD]`. Empty = all methods. Normalised to upper-case. Lets you give GET and POST on the same path independent cache policies. |
| `pool` | — | Upstream pool name. Required unless `static.root` is set. |
| `static.root` | `""` | Absolute path to a directory to serve files from. Required unless `pool` is set. See [Static file serving](static-files/). |
| `static.index` | `[]` | Index files to try (in order) when the request path maps to a directory, e.g. `[index.html]`. |
| `static.max_file_size` | `10MiB` | Per-file size cap. Files larger than this are rejected with 413. |

### `routes[].request`

| Field | Default | Description |
|---|---|---|
| `header_set` | `{}` | Headers to set on the upstream request |
| `header_remove` | `[]` | Headers to remove from the upstream request |
| `strip_prefix` | `""` | Strip this path prefix before forwarding to the upstream (e.g. `/api/v1/users` → `/users`). Must start with `/`. The cache key still uses the original path. |

### `routes[].cache`

| Field | Default | Description |
|---|---|---|
| `enabled` | `true` | Set to `false` to bypass caching for this route |
| `ttl_default` | `0` | Default TTL when origin has no `Cache-Control` |
| `ttl_override` | `0` | Force bouine's internal TTL regardless of upstream `Cache-Control`/`Expires`; upstream headers are forwarded unaltered. See [TTL override](/docs/configuration/cache-policy/#ttl-override). |
| `stale_while_revalidate` | `0` | Serve stale while refreshing in background |
| `stale_if_error` | `0` | Serve stale on origin 5xx |
| `negative_ttl` | `0` | Cache 404/405/410/501 responses for this duration |
| `jitter_percent` | `0` | Random ±N% on TTLs to prevent stampedes (0–50) |
| `stayin_alive` | `false` | Serve stale indefinitely when upstream is down (see [Stayin Alive](/docs/configuration/cache-policy/#stayin-alive)) |
| `allow_set_cookie` | `false` | Allow caching responses that carry `Set-Cookie`. Default blocks caching such responses (nginx-style). When `true`, the response is cached but `Set-Cookie` is stripped from the stored copy. See [Set-Cookie caching](/docs/configuration/cache-policy/#set-cookie-caching). |
| `max_object_size` | `0` | Skip caching responses whose body exceeds this size (e.g. `1MiB`). The response is still proxied. `0` = no limit. |
| `max_response_bytes` | `64MiB` | Hard cap on origin response body size. Aborts the fetch if exceeded. Different from `max_object_size` which controls caching eligibility. |
| `max_fetch_concurrency` | `64` | Max concurrent origin fetches per route (collapsed via singleflight). |
| `fetch_timeout` | `60s` | Max duration for a single origin fetch. |
| `refresh_before_expiry` | `false` | Enable proactive background conditional revalidation before TTL expiry. See [Refresh before expiry](/docs/configuration/cache-policy/#refresh-before-expiry). |
| `refresh_margin_percent` | `10` | Percentage of TTL before expiry at which the background refresh fires (1–50). E.g. `20` fires at 80% of TTL. |
| `refresh_timeout` | `10s` | Maximum duration for a single background refresh fetch (5s–120s) |
| `refresh_concurrency` | `8` | Maximum concurrent background refresh fetches per route (1–64) |
| `refresh_min_hits` | `0` | Minimum cache hits during a TTL window for an object to qualify for re-scheduling after a refresh. `0` disables the gate. See [Popularity gates](/docs/configuration/cache-policy/#popularity-gates). |
| `refresh_persist_cycles` | `0` | Additional TTL cycles to keep refreshing after the popularity gate would block. Requires `refresh_min_hits > 0`. See [Persist cycles](/docs/configuration/cache-policy/#persist-cycles). |
| `refresh_min_score` | `0` | Minimum refresh priority score (`staleHits × bodySize`) for re-scheduling. Requires `refresh_min_hits > 0`. See [Popularity gates](/docs/configuration/cache-policy/#popularity-gates). |
| `refresh_max_rps` | `0` | Caps background refresh fetches per second per route (0 or 1–10000). `0` = no limit. See [Rate limiting](/docs/configuration/cache-policy/#rate-limiting). |
| `refresh_reactive_first` | `false` | SWR-first mode: new objects rely on stale-while-revalidate instead of proactive refresh. Requires `stale_while_revalidate > 0` and `refresh_min_hits > 0`. See [Reactive-first mode](/docs/configuration/cache-policy/#reactive-first-mode). |

### `routes[].cache.key`

| Field | Default | Description |
|---|---|---|
| `include_headers` | `[]` | Headers to include in cache key (replaces Vary) |
| `exclude_headers` | `[]` | Request header names to strip from the Vary-based variant key, preventing cache fragmentation from per-request headers like `X-Request-Id`. Matched case-insensitively. See [Excluding headers](/docs/configuration/cache-policy/#excluding-headers-from-the-cache-key). |
| `strip_query_params` | `[]` | Query parameter names to exclude from the cache key, e.g. `[utm_source, fbclid]`. The params are still forwarded to the upstream. See [Stripping query parameters](/docs/configuration/cache-policy/#stripping-query-parameters-from-the-key). |
| `keep_query_params` | `[]` | When non-empty, restricts the cache key to only these query parameters; all others are excluded. Mutually exclusive with `strip_query_params` and `strip_query_prefix`. Equivalent to Varnish `qs.keep()`. |
| `strip_query_prefix` | `[]` | Strip query params whose names start with any of these prefixes (e.g. `[utm_, fb_, _ga]`). Covers wildcard stripping without enumerating every variant. Capped at 16 entries. |
| `strip_empty_params` | `false` | Remove query params with empty values (`?foo=&bar=1` → `?bar=1`). Does not apply to params in `keep_query_params`. |
| `dedup_query_params` | `false` | Keep only the first value for duplicate query params (`?a=2&a=1` → `?a=2`). Values are not sorted. |
| `canonicalize_path` | `false` | Normalize the path component: percent-decode unreserved chars, uppercase remaining hex, resolve dot-segments. Applies at the listener level if any route on that listener enables it. |

### `upstream_pools[].connect`

| Field | Default | Description |
|---|---|---|
| `timeout` | `10s` | TCP dial timeout |
| `keep_alive` | `15s` | TCP keep-alive interval |
| `max_connections` | `0` | Max concurrent connections per pool (0 = unlimited) |
| `response_header_timeout` | `30s` | Max time to wait for response headers from upstream. Zero applies a 30s built-in default. Primary defence against slow-origin resource exhaustion. |
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
| `max_batch_size` | `1000` | Max URLs per `/v1/purge/batch` request |
| `rate_limit_per_second` | `0` | Rate limit on admin write endpoints (0 = no limit) |
| `pprof_enabled` | `false` | Enable `/debug/pprof/*` profiling endpoints |
| `drain_duration` | `10s` | Duration the `/drain` endpoint blocks during shutdown (K8s preStop hook) |

### `tracing`

Configure OpenTelemetry span export. Leave `endpoint` empty (default) to disable tracing.

| Field | Default | Description |
|---|---|---|
| `endpoint` | `""` | OTLP/HTTP collector URL, e.g. `http://otel-collector:4318`. Empty disables. |
| `service_name` | `"bouine"` | `service.name` OTel resource attribute |
| `sampling_rate` | `1.0` | Fraction of requests to sample (0.0–1.0) |

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

### `experimental`

Opt-in features that are not yet stable. All fields default to off. See [Experimental features](experimental/).

| Field | Default | Description |
|---|---|---|
| `h1_fast_path` | `false` | Enable custom HTTP/1.1 parser for zero-allocation cache hits. Eliminates `*http.Request` and `http.ResponseWriter` construction on the hit path (~40% CPU reduction, 0 allocations). Misses and non-GET/HEAD requests fall through to `net/http`. |

### Top-level fields

| Field | Default | Description |
|---|---|---|
| `gogc` | `100` | Go GC percentage. Set to `-1` to disable percentage-based GC, relying solely on `GOMEMLIMIT`. |
| `url_ring_sample_rate` | `0` | 1-in-N sampling for the dashboard URL ring buffer. `0` = record every non-HIT request. `100` = 1 in 100 (reduces sync.Map overhead under high miss rates). `1` = record every call (debug mode). |

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

## Config updates

bouine does not support live config reload. All config changes require a
process restart. On Kubernetes, use a rolling restart:

```bash
kubectl rollout restart statefulset/bouine
```

For TLS certificate rotation, restart the process or use Kubernetes rolling
restarts with cert-manager.

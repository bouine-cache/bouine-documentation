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
| `http` | `":80"` | HTTP/1.1 plaintext listener |
| `https` | `""` | HTTPS (TLS) listener. See [TLS](tls/). |
| `admin` | `":9000"` | Admin API (health, metrics, purge) |
| `cluster` | `""` | Gossip cluster port |
| `max_connections` | `0` | Max concurrent data-plane connections (0 = built-in default **65536 since v0.6.0**, previously 4096; Helm chart sets 65536 default / 8192 production / 16384 HA — explicit values are untouched, and 0 disables the cap). Protects against FD exhaustion. Idle keep-alive connections hold a slot, so size for the whole client population a single CDN front produces, not just peak concurrency; each accepted connection pins ~32 KiB, so 65536 conns pin at most ~2 GiB — size down on small pods. Over-limit connections get an instant `503 + Connection: close` at accept, counted exactly by `bouine_conn_rejections_total` (the warn log is rate-limited to one line per 10 s per listener). |
| `idle_timeout` | `120s` | Keep-alive idle timeout for data-plane connections: how long a connection with no in-flight request stays open. Also used by the H1 fast-path parser, so the two stay in sync. With an upstream proxy or LB in front, keep its keep-alive idle timeout **below** this value so it closes idle connections first — otherwise bouine can close a connection mid-reuse and the upstream logs `upstream prematurely closed connection`. |
| `tcp_fast_open` | `false` | Enable server-side TCP_FASTOPEN on data-plane listeners (Linux only, no-op elsewhere). **Default changed from enabled to disabled in v0.5.29** — deployments that relied on the old default must set `true` explicitly. With a kernel-cached TFO cookie the request bytes ride in the client's SYN, saving one RTT on fresh connections. Advisory: accepts never fail because of it. See [TCP Fast Open](#tcp-fast-open). |
| `tcp_defer_accept` | `true` (Linux) | Enable TCP_DEFER_ACCEPT on data-plane listeners. Defaults to true on Linux, no-op elsewhere. |
| `reuse_port` | `true` (Linux) | Enable SO_REUSEPORT on data-plane listeners (N parallel accept loops). Defaults to true on Linux, false on other platforms. |
| `tcp_quickack` | `true` (Linux) | Enable TCP_QUICKACK on accepted data-plane connections to reduce latency by avoiding delayed ACKs. Defaults to true on Linux, no-op elsewhere. |
| `read_timeout` | `30s` | Bounds how long reading a single request's header and body may take, per request (since v0.5.9). This is the slowloris defense for clients that drip-feed bytes — it is **not** an end-to-end request deadline (origin fetches are bounded by `fetch_timeout`). Raise it for slow mobile clients or large uploads. Must stay below the 5-minute data-plane safety-net write timeout. |

### `storage`

| Field | Default | Description |
|---|---|---|
| `hot_max_bytes` | — | RAM cache size. See [size units](#size-units). Example: `2GiB`. |
| `eviction_algorithm` | `sieve` | Eviction policy for both tiers: `sieve` (visited-bit sweep) or `cachaner` (SIEVE + 3-bit frequency counter — up to 7 second chances for hot objects). Per-tier overrides: `hot_eviction_algorithm`, `warm_eviction_algorithm`. |
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
| `peer_max_conns_per_host` | `8` | Pipelined peer connections per peer. Default 8, with 16 pending requests each, gives 128 concurrent peer fetches per peer. Set to 1 to disable pipelining. |
| `peer_max_idle_conn_duration` | `120s` | How long idle peer RPC connections are kept before closing. Must stay **below** `admin.idle_timeout` (default 300s) — config validation rejects any explicit value that violates the ordering, because a peer request sent on a connection the admin server already reaped fails with EOF and falls back to origin. |
| `peer_fetch_concurrency` | `64` | Bounds concurrent peer-fetch and peer-put RPCs per node (since v0.5.11, range 1–128; **default raised from 4 to 16 in v0.5.29, then from 16 to 64 in v0.6.0** — too small a pool queues peer hits behind in-flight fetches and adds tail latency on strong-mode clusters; explicit values are unaffected). In strong mode most cache hits are peer hits, so this semaphore sits on the hot path; raise it together with `peer_max_conns_per_host` under load to cut peer-hit tail latency. |
| `peer_tcp_fast_open` | `false` | Enable outbound TCP Fast Open (`TCP_FASTOPEN_CONNECT`) on peer-bound dials — peer fetch/put and the invalidation-broadcast client (since v0.5.29). With a kernel-cached TFO cookie the first RPC bytes ride in the SYN, saving one RTT on every fresh peer connection. Opt-in, Linux 4.11+ only, no-op elsewhere; bouine↔bouine peer dials use TFO end-to-end when the dialing side sets this flag, the answering side sets `listen.tcp_fast_open`, and each peer's kernel has `net.ipv4.tcp_fastopen` including the server bit. Advisory: dials never fail because of it. |
| `ban_ttl` | `24h` | How long a lazy invalidation ban stays in the active ban list before the reaper prunes it (since v0.5.20, must be ≥ 1s when set). RFC 9111 §4.4 exempts objects stored after the ban, so cache-lifecycle surrogate invalidations are safe at minutes scale — lower it to bound the hit-ratio damage of an over-broad ban. |
| `join_timeout` | `120s` | Max time to wait for cluster join. In strong mode, the pod stays not-ready if join fails. In eventual mode, the pod becomes ready and retries in the background. |
| `handoff_queue_depth` | `4096` | Memberlist per-peer message buffer. Absorbs bursts of cache invalidations. Negative values are rejected. |
| `tls.ca_bundle` | `""` | CA certificate path for peer-to-peer mTLS. Empty = plain HTTP. |
| `tls.cert_file` | `""` | Client certificate for mTLS |
| `tls.key_file` | `""` | Client private key for mTLS |

### `routes[]`

Route matching uses `host` (exact or a leading-`*.` wildcard since v0.5.27), `path_prefix` **or** `path` (an anchored RE2 regex, since v0.5.27), and optionally `methods`. Routes are matched in declaration order; the first match wins. A later route fully covered by an earlier one (host, path, and methods all covered) is dead config and is reported at Error level at boot while boot proceeds. Ban predicates still use their own `path_regex` — see [ban predicates](/docs/operations/cache-invalidation/).

A route must specify exactly one of `pool` or `static.root`. The former proxies to an upstream pool; the latter serves files from a local directory. See [Static file serving](static-files/).

| Field | Default | Description |
|---|---|---|
| `name` | `""` | Human-readable label used in Prometheus `route` label and the dashboard. Defaults to the host + path predicate when empty (a `match.path` regex is shown verbatim). |
| `match.host` | `""` | Match on `Host` header (empty = any). Since v0.5.27 a leading `*.` performs a suffix match anchored on the label boundary: `*.staging.example.com` covers `abc.staging.example.com` and the whole per-PR subdomain tree, never the bare `staging.example.com` or `evilstaging.example.com`. Any wildcard that is not the single leading `*.` form is rejected at config validation. |
| `match.path_prefix` | `""` | Match on URL path prefix (empty = any) |
| `match.path` | `""` | Anchored RE2 pattern matched against the request path, query excluded, e.g. `^/[a-z]{2}-[a-z]{2}/l/campaign-.*$` (since v0.5.27). Mutually exclusive with `path_prefix`. Validation rejects invalid regexes, unanchored patterns, patterns over 512 B, and control bytes. Regexes compile once at startup, so route resolution never pays compile cost; prefix-only route tables keep their zero-alloc hit path. Reduces `route`-label and config cardinality versus the per-host/per-page route explosion they replace. |
| `match.methods` | `[]` | Restrict to listed HTTP methods, e.g. `[GET, HEAD]`. Empty = all methods. Normalised to upper-case. Lets you give GET and POST on the same path independent cache policies. |
| `pool` | — | Upstream pool name. Required unless `static.root` is set. |
| `static.root` | `""` | Absolute path to a directory to serve files from. Required unless `pool` is set. See [Static file serving](static-files/). |
| `static.index` | `[]` | Index files to try (in order) when the request path maps to a directory, e.g. `[index.html]`. |
| `static.max_file_size` | `10MiB` | Per-file size cap. Files larger than this are rejected with 413. |

### `routes[].request`

| Field | Default | Description |
|---|---|---|
| `header_set` | `{}` | Headers to set on the upstream request. Rewrites apply on every origin fetch (miss, revalidation, invalidating methods, background refresh) — enforced on all emit paths since v0.5.19. |
| `header_remove` | `[]` | Headers to remove from the upstream request |
| `strip_prefix` | `""` | Strip this path prefix before forwarding to the upstream (e.g. `/api/v1/users` → `/users`). Must start with `/`. The cache key still uses the original path. |
| `path_rewrite` | — | Per-route regex path rewrite applied to the origin-bound request path (since v0.5.21) — the nginx `rewrite ... break` / Varnish `regsub` equivalent. `match` (Go RE2, linear time) and `replace` (`$1` capture references, `${1}x` braced disambiguation) are compiled once at config load and applied exactly once on every origin-bound fetch: miss, bypass, invalidating methods, revalidation, background refresh, streams. The query string is never matched or modified; only the first match is replaced (nginx semantics); pattern and template are capped at 512 B; every `$reference` must resolve against the pattern's groups at config load. Mutually exclusive with `strip_prefix` (validation rejects both). The cache key, ban matching, purges, and all client-facing surfaces keep the original public path. |
| `forwarded` | off | Client-identity header injection on origin-bound fetches (since v0.5.27): `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host`, and `Via`. Accepts four YAML shapes — the `standard` preset, a token list (`[client_ip, proto]`), the opt-out (`false`/`none`), or a full mapping with `max_append` (default 5, range 1–64). Never applied on the hit path, never part of the cache key or stored request headers. Requires a pool; mutually exclusive with `header_set` entries targeting the same header. Declare once for every route with `route_defaults.request.forwarded`. See [Forwarded headers](#forwarded-headers). |

### `routes[].cache`

| Field | Default | Description |
|---|---|---|
| `enabled` | `true` | Set to `false` to bypass caching for this route |
| `ttl_default` | `0` | Default TTL when origin has no `Cache-Control` |
| `ttl_override` | `0` | Force bouine's internal TTL regardless of upstream `Cache-Control`/`Expires`; upstream headers are forwarded unaltered. Since v0.5.29 the override applies to success and redirect responses only (status < 400) — storable error responses follow the negative-caching TTL ladder (origin explicit freshness > `negative_ttl` > heuristic > `ttl_default`) instead of being pinned fresh for the override duration. See [TTL override](/docs/configuration/cache-policy/#ttl-override). |
| `stale_while_revalidate` | `0` | Serve stale while refreshing in background |
| `stale_if_error` | `0` | Serve stale on origin 5xx |
| `negative_ttl` | `0` | Cache 404/405/410/501 responses for this duration. Since v0.5.22 also accepts a per-status map — `negative_ttl: {404: 1m, 5xx: 10s, 410: 0}` (exact codes 400–599, classes `4xx`/`5xx`, exact shadows class, `0` disables that status) — which outranks `ttl_default`/heuristic freshness for the statuses it covers. See [Negative caching](/docs/configuration/cache-policy/#negative-caching). |
| `jitter_percent` | `0` | Random ±N% on TTLs to prevent stampedes (0–50) |
| `stayin_alive` | `false` | Serve stale indefinitely when upstream is down (see [Stayin Alive](/docs/configuration/cache-policy/#stayin-alive)) |
| `allow_set_cookie` | `false` | Allow caching responses that carry `Set-Cookie`. Default blocks caching such responses (nginx-style). When `true`, the response is cached but `Set-Cookie` is stripped from the stored copy. See [Set-Cookie caching](/docs/configuration/cache-policy/#set-cookie-caching). |
| `bypass_on_cookie` | `false` | When `true`, a request carrying any non-empty `Cookie` header never touches the cache on this route: no lookup, no storage, no in-flight sharing — it proxies to origin (`X-Cache: BYPASS`). The Varnish `return (pass)` equivalent for `req.http.Cookie`; designed for personalized SSR routes whose origin renders per-user content from the request cookie (since v0.5.26). The trigger is Cookie-header presence, not a name list. See [Cookie bypass](/docs/configuration/cache-policy/#cookie-bypass-since-v0526). |
| `bypass_on_cookie_names` | `[]` | Cookie names that route a request carrying any of them entirely around the cache — the same no-lookup/no-storage/no-in-flight contract as `bypass_on_cookie`, scoped to the listed names (since v0.5.27). Requests carrying only unlisted cookies participate in the cache per RFC 9111. Matching is case-insensitive on the cookie-name token only, in every `; `-separated position and on every repeated `Cookie` field line. Capped at 16 names; mutually exclusive with `bypass_on_cookie`. See [Cookie-name bypass](/docs/configuration/cache-policy/#cookie-name-bypass-since-v0527). |
| `bypass_on_user_agent` | `[]` | User-Agent `*`-glob patterns that route matching requests entirely around the cache — no lookup, no storage, no in-flight sharing; the request proxies to origin with `X-Cache: BYPASS` (since v0.5.27). Patterns match the full UA string case-insensitively; `*` matches any run of bytes including `/`; an exact pattern matches the whole string (`*Bot*` for substring semantics). Capped at 16 entries / 256 B each. Declare once via `route_defaults.cache.bypass_on_user_agent`. See [User-Agent bypass](/docs/configuration/cache-policy/#user-agent-bypass-since-v0527). |
| `max_object_size` | `0` | Skip caching responses whose body exceeds this size (e.g. `1MiB`). The response is still proxied. `0` = no limit. |
| `max_response_bytes` | `64MiB` | Hard cap on bytes buffered per origin fetch. Aborts the fetch (502) when exceeded. Different from `max_object_size` which controls caching eligibility. Default derives from GOMEMLIMIT (7%) or a built-in 64 MiB floor. |
| `max_fetch_concurrency` | `256` (since v0.6.0, previously 32) | Max concurrent foreground origin fetches per route (collapsed via singleflight). Excess requests wait up to `fetch_wait_timeout` for a slot, then shed. A miss holds its slot for roughly the origin latency, so a route sustains at most `slots / origin-latency` misses per second — 32 slots capped at ~640 misses/s against a 50 ms origin and shed 75% of misses above that; the 256 default sustains ~5 100 misses/s at the same latency. Size `slots × 2 × max_response_bytes` within about two thirds of `GOMEMLIMIT` on small pods. |
| `max_variants` | `1024` (built-in) | Cap on distinct Vary variants stored per primary cache key on this route (since v0.5.25). Unset/`0` applies the built-in default; negative values are rejected; the cap cannot be disabled. When hit, further variant storage is skipped and `vary_cap_hits_total` increments — requests keep being proxied. See [Variant caps](/docs/configuration/cache-policy/#variant-caps-and-content-negotiation-bucketing). |
| `fetch_timeout` | inherits `connect.response_header_timeout` (30s) | The authoritative per-route origin timeout (header + body), starting once a fetch slot is acquired (semantics since v0.5.11). When unset, the route inherits the pool's `connect.response_header_timeout`; when set, the value is enforced verbatim in either direction — a route may exceed the pool-wide knob to give a slow endpoint more time without raising the wait for every other route. Must stay below the 5-minute data-plane safety-net write timeout. |
| `fetch_wait_timeout` | `100ms` | How long a foreground miss waits for an origin-fetch slot (bounded by `max_fetch_concurrency`) before shedding: stale object served if one is in scope, otherwise 503 + `Retry-After: 1`. Validated range: 0–1s. Independent of `fetch_timeout`. See [Streaming and live responses](streaming/). |
| `max_streaming_buffer_bytes` | auto (GOMEMLIMIT × 7%, floor 64MiB) | Total bytes held in live streaming tee buffers across concurrent miss-fetches on this route. When exceeded, new cacheable misses fall back to synchronous buffering instead of streaming. |
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
| `include_headers` | `[]` | Request header names added to the Vary-based variant key exactly as if the origin had listed them in `Vary` (unioned at object-build time, never a replacement — since v0.5.21). A listed header absent from the request hashes as an empty value. Validation rejects `*`, non-token, duplicate, and `exclude_headers`-overlapping entries; max 16. Must be identical on every cluster node serving the route. See [Cache key headers](/docs/configuration/cache-policy/#cache-key-headers). |
| `include_host` | `true` | Explicitly `false` drops the host segment from the primary cache key (since v0.5.22): the same URL+query resolves to one entry regardless of request Host. Requests still forward the client's Host; only key computation changes. Absent/`true` keeps the key byte-for-byte. Rejected on routes that set `match.host`. Must be identical across cluster nodes serving the route. See [Dropping the host from the key](/docs/configuration/cache-policy/#dropping-the-host-from-the-key-include_host-false-since-v0522). |
| `verbatim_encoding` | `false` | `true` restores the pre-bucketing `Accept-Encoding` keying: the raw value is lowercased+sorted and forwarded to the upstream unchanged. Use only when the origin varies response bodies by the full AE string — it re-fragments the variant space (since v0.5.22). Must be identical across cluster nodes. See [Accept-Encoding bucketing](/docs/configuration/cache-policy/#accept-encoding-bucketing-since-v0522). |
| `exclude_headers` | `[]` | Request header names to strip from the Vary-based variant key, preventing cache fragmentation from per-request headers like `X-Request-Id`. Matched case-insensitively. See [Excluding headers](/docs/configuration/cache-policy/#excluding-headers-from-the-cache-key). |
| `cookie_presence` | `[]` | Cookie names whose **presence** (never the value) contributes one bit each to the Vary variant key (since v0.5.27) — for origins that render different content depending on whether a consent/analytics cookie exists. Presence rides a synthetic Vary field, so store/lookup pairing, peer gates, 304 revalidation, and background-refresh replay hash the same bits everywhere; repeated `Cookie` lines are canonicalized to the RFC 6265 §4.2 form before the bits are computed. Capped at 16 names (N names = up to 2^N presence combinations); mutually exclusive with both bypass knobs. Must be identical on every cluster node serving the route. See [Cookie presence keying](/docs/configuration/cache-policy/#cookie-presence-keying-since-v0527). |
| `strip_query_params` | `[]` | Query parameter names to exclude from the cache key, e.g. `[utm_source, fbclid]`. The params are still forwarded to the upstream. See [Stripping query parameters](/docs/configuration/cache-policy/#stripping-query-parameters-from-the-key). |
| `keep_query_params` | `[]` | When non-empty, restricts the cache key to only these query parameters; all others are excluded. Mutually exclusive with `strip_query_params` and `strip_query_prefix`. Equivalent to Varnish `qs.keep()`. |
| `strip_query_prefix` | `[]` | Strip query params whose names start with any of these prefixes (e.g. `[utm_, fb_, _ga]`). Covers wildcard stripping without enumerating every variant. Capped at 16 entries. |
| `strip_empty_params` | `false` | Remove query params with empty values (`?foo=&bar=1` → `?bar=1`). Does not apply to params in `keep_query_params`. |
| `dedup_query_params` | `false` | Keep only the first value for duplicate query params (`?a=2&a=1` → `?a=2`). Values are not sorted. |

> **`canonicalize_path` was removed in v0.5.19.** The knob was parsed and documented but its listener-level wiring never landed, so it had no effect; configs setting it now fail at load time with the strict loader. Remove the key from your config when upgrading.

### `route_defaults`

Declare per-route blocks once instead of repeating them on every route (since v0.5.27). Values are merged into every route before validation; only the two blocks with defined merge semantics are accepted — any other route field under `route_defaults` is rejected at decode time.

```yaml
route_defaults:
  request:
    forwarded: standard        # inherited by every route that does not opt out
  cache:
    bypass_on_user_agent: ["*ShoppingFeedBot*"]
```

| Field | Merge semantics |
|---|---|
| `request.forwarded` | A route without its own `forwarded` block inherits the default wholesale; a preset or token list **replaces** the default's flags (only `max_append` falls back); the mapping form **ORs** field-by-field with the default — use the token-list form to drop a single header; `forwarded: false`/`none` opts the route out. Static routes ignore the inherited default (no origin-bound request exists); validation (pool requirement, `header_set` conflict, `max_append` bounds) runs on the resolved value. |
| `cache.bypass_on_user_agent` | Every pool route without its own list inherits the default wholesale; a route's own list **replaces** it (never a union); an explicit empty list (`bypass_on_user_agent: []`) opts the route out; static routes inherit nothing. An invalid default is reported once at `route_defaults`' own path. |

### `upstream_pools[].connect`

All fields are optional; a zero/empty value applies the built-in default, so existing configs keep their current behaviour.

| Field | Default | Description |
|---|---|---|
| `timeout` | `10s` | TCP dial timeout |
| `keep_alive` | `30s` | TCP keep-alive probe interval on origin connections |
| `max_connections` | `64` | Max concurrent connections per origin host (fasthttp `MaxConnsPerHost`). Per host, not per pool: a pool with N targets gets N × `max_connections`. Bounds FD consumption under slow origins. |
| `max_idle_conn_duration` | `90s` | How long an idle pooled origin connection is kept before closing. Keep this **below** any LB idle timeout between bouine and the origin (e.g. AWS NLB 350s) so bouine closes idle connections first. |
| `response_header_timeout` | `30s` | Max time to wait for response headers from upstream. Zero applies a 30s built-in default. Primary defence against slow-origin resource exhaustion — and, since v0.5.11, the default origin timeout (header + body) for every route on the pool that does not set its own `cache.fetch_timeout`. Since v0.5.29 a fetch that times out (dial, response-header, or per-route deadline) surfaces to clients as `504 Gateway Timeout`, not `502` — every other upstream failure keeps `502`. |
| `hedge_timeout` | `0` (disabled) | Hedged fetch (since v0.5.19): fire a duplicate request to the same pool when the primary does not respond within this duration; the first response wins. Only applies to idempotent methods (GET, HEAD, OPTIONS). Zero disables hedging. See [Hedged fetch](#hedged-fetch). |
| `tcp_fast_open` | `false` | Enable outbound TCP Fast Open (`TCP_FASTOPEN_CONNECT`) on origin dials for this pool (since v0.5.29) — the pool's shared and SSE clients set the option before connect, so with a kernel-cached TFO cookie the first request bytes ride in the SYN, saving one RTT on every fresh origin connection. Opt-in, Linux 4.11+ only, no-op elsewhere; origins without TFO never issue a cookie and the dial silently falls back to the regular handshake, so there is no penalty for enabling it. See [TCP Fast Open](#tcp-fast-open). |
| `preserve_host` | `false` | Keep the request's own `Host` header on origin-bound fetches instead of replacing it with the pool target (since v0.5.28). Only the wire-level Host header changes — the dial target stays the configured pool target, and the cache key, Vary variant key, `X-Bouine-Host` attribution, ban/purge matching, and `request.forwarded` are untouched. Enable for origins that derive behaviour from the request Host (market/country selection, virtual-host routing); host-blind origins keep the historical behaviour, and the `host` token of `request.forwarded` remains the mechanism for origins that read `X-Forwarded-Host`. |

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

`passive.eject_for` restores passively ejected targets once the window
elapses and re-ejects them automatically if they are still broken
(enforced since v0.5.19; restores are counted in the
`origin_restores_total` metric with a `source` label). **Since v0.6.1 an
unset `eject_for` resolves to a built-in 30s window on pools that configure
passive health** — previously the zero value ejected a single-target pool for
the process lifetime (every miss returned an instant 502 until restart).
There is no eject-forever configuration anymore; set a very long window to
opt out of restore. **Since v0.6.0 a 5xx response counts toward ejection
only once the target has stopped completing successful fetches for a 5s
success window** — a healthy origin answering successes is never ejected by
a 5xx burst. Connection errors are never excused by recent successes. Both
`consecutive_5xx` and `eject_for` are hot-configurable per pool at runtime
(`bouine config set pool:<name>.health.passive.consecutive_5xx ...` and
`pool:<name>.health.passive.eject_for ...`; `eject_for` only when the reaper
started at boot) — see [Hot configuration](#hot-configuration).

### `metrics`

| Field | Default | Description |
|---|---|---|
| `traffic_classes` | `[]` | Up to 8 named traffic populations matched by request-host patterns (since v0.5.27). Adds an always-present `traffic_class` label to `bouine_requests_total`, `bouine_request_duration_seconds`, and `bouine_response_bytes_total`, plus a matching `traffic_class` access-log attribute — enabling per-population hit-ratio, latency, and saved-bandwidth queries inside one instance. Each class carries a unique lowercase name (the reserved `unclassified` is rejected; it is the fallback for requests matching no class) and up to 64 host patterns: an exact host, a leading `*.` (suffix match), or a trailing `.*`/`*` (prefix match). Declaration order is precedence — first match wins — and a later class fully shadowed by an earlier one is reported at Error level at boot while boot proceeds. |

```yaml
metrics:
  traffic_classes:
    - name: checkout
      hosts: ["checkout.example.com"]
    - name: marketing
      hosts: ["*.example.com"]   # suffix match on the label boundary
```

Every invalid field is reported at once, each anchored to its own `metrics.traffic_classes[i].name` / `.hosts[j]` path. See [Monitoring → traffic classes](/docs/operations/monitoring/#traffic-classes) for the label semantics and the series-cardinality note.

### `admin`

| Field | Default | Description |
|---|---|---|
| `token` | `""` (auto-generated) | Admin bearer token. See [Authentication](/docs/operations/authentication/). |
| `max_batch_size` | `1000` | Max URLs per `/v1/purge/batch` request |
| `idle_timeout` | `300s` | Keep-alive idle timeout for admin-server connections, including cluster peer RPCs (`/v1/peer/*`). Peer clients default to a 120s idle duration, so they close idle connections before the admin server reaps them; keep `cluster.peer_max_idle_conn_duration` below this value. |
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
| `api_tokens` | `[]` | Additional API tokens for rate-limit spreading (also injectable via `CF_API_TOKENS`, comma-separated). The client rotates across all tokens to multiply the effective rate-limit budget. |
| `async` | `true` | Return immediately; CF call runs in background goroutine |
| `timeout` | `10s` | Per-call timeout for CF API requests |
| `batch.max_batch_size` | `0` (passthrough) | Max items coalesced per CF API call when > 0. Purges are deduplicated and batched. |
| `batch.max_wait` | `500ms` | Max time a batched item waits before a flush |
| `circuit.enabled` | `false` | Circuit breaker: fail fast during CF API outages |
| `circuit.failure_threshold` | `5` | Consecutive failures before the circuit opens |
| `circuit.open_timeout` | `30s` | Time before probing again |
| `circuit.half_open_max_calls` | `1` | Probe calls allowed in half-open state |
| `retry.enabled` | `false` | Dead-letter queue for failed CF purges: retried with exponential backoff so transient CF outages don't lose invalidations |
| `retry.max_queue_size` | `1000` | Max items in the retry queue; new failed items are dropped when full |
| `retry.max_retries` | `3` | Retry attempts per item |
| `retry.base_delay` | `1s` | Initial retry delay (grows exponentially) |
| `retry.max_delay` | `30s` | Retry backoff cap |
| `propagate.purge` | `true` | Forward `POST /v1/purge` to CF `PurgeSingleFile` |
| `propagate.ban` | `true` | Forward `POST /v1/ban` to CF (tags / prefixes / hostnames) |
| `propagate.refresh` | `true` | Forward `POST /v1/refresh` to CF `PurgeSingleFile` |

### `experimental`

Opt-in features that are not yet stable. All fields default to off. See [Experimental features](experimental/).

| Field | Default | Description |
|---|---|---|
| `h1_fast_path` | n/a (retired v0.6.0) | **Always on since v0.6.0** (ADR-0069): the zero-allocation HTTP/1.1 hit path is built whenever a store exists, with no config gate. The key still parses (strict loader keeps pre-promotion configs loading) but is ignored, and a retirement notice is logged at startup when set — there is no opt-out. Misses and non-GET/HEAD requests fall through to the standard `fasthttp` handler. See [Experimental features](experimental/). |
| `h1_fast_peer_path` | n/a (retired v0.6.0) | **Always on since v0.6.0** in strong-mode clusters: the fast-path miss now always asks the ring owner first, the same owner-first path the slow path has always taken. The key still parses but is ignored; retirement logged at startup. |
| `h1_reactor` | — (removed v0.6.0) | **Removed in v0.6.0** (ADR-0041 superseded by ADR-0068): configs setting `experimental.h1_reactor` now fail strict parsing with an unknown-field error — remove the key. All fast-path traffic uses the blocking h1parser path. |
| `config_reload` | `false` | Experimental (since v0.6.0, issue #817): enable `bouine config reload` / `POST /v1/config/reload` to apply a config file to a running daemon without a restart. See [Hot configuration](#hot-configuration). |

### Top-level fields

| Field | Default | Description |
|---|---|---|
| `gogc` | `100` | Go GC percentage. Set to `-1` to disable percentage-based GC, relying solely on `GOMEMLIMIT`. |
| `url_ring_sample_rate` | `0` | 1-in-N sampling for the dashboard URL ring buffer. `0` = record every non-HIT request. `100` = 1 in 100 (reduces sync.Map overhead under high miss rates). `1` = record every call (debug mode). |
| `route_defaults` | — | Declare `request.forwarded` and `cache.bypass_on_user_agent` once for every route instead of repeating them per route. See [`route_defaults`](#route_defaults). |
| `metrics.traffic_classes` | `[]` | Named host-matched traffic populations for the `traffic_class` metric label. See [`metrics`](#metrics). |

---

## Hedged fetch

Set `upstream_pools[].connect.hedge_timeout` to hedge slow origins (wired
into the fetch path since v0.5.19). When the primary request does not get a
response within `hedge_timeout`, bouine fires a duplicate request to the
same pool and returns whichever response arrives first. Only idempotent
methods (`GET`, `HEAD`, `OPTIONS`) are hedged — SSE and non-idempotent
requests never duplicate. Zero (the default) disables hedging.

```yaml
upstream_pools:
  - name: api
    targets: [api.default.svc:8080]
    connect:
      hedge_timeout: 250ms
```

---

## Forwarded headers

`routes[].request.forwarded` (since v0.5.27) injects client-identity
headers onto **origin-bound** requests only — miss, invalidating proxy
(POST/PUT/DELETE), bypass, revalidate, streaming/SSE, and the background
fetchers. The cache-hit path is untouched, and the headers never join the
cache key or the stored request headers.

| Header | Token | Behaviour |
|---|---|---|
| `X-Forwarded-For` | `client_ip` | Appends the address of bouine's immediate peer (the edge) to the carried chain — existing entries are never rewritten. Client-supplied chains are append-only untrusted input; a spoofed chain merely costs an origin fetch. |
| `X-Forwarded-Proto` | `proto` | **Set** to the scheme bouine received the request on (`https` on a TLS listener, `http` otherwise) — not the scheme used towards the origin. |
| `X-Forwarded-Host` | `host` | **Set** to the Host header bouine received, replacing any client-supplied value. Tells multi-host origins which hostname was requested, and matters wherever the outbound Host is rewritten to a pool target — pair with `connect.preserve_host`. |
| `Via` | `via` | Appends `1.1 bouine` per RFC 9110 §7.6.3, complementing the internal cluster hop limit. |

Four YAML shapes:

```yaml
request:
  forwarded: standard           # all four headers, one line
  forwarded: [client_ip, proto]  # exactly these headers, no implicit extras
  forwarded: false              # explicit opt-out (kills a route_default)
  forwarded:                    # full mapping, field-by-field
    client_ip: true
    proto: true
    max_append: 10              # chain cap, default 5 (range 1–64)
```

The XFF and `Via` chains are capped at `max_append` entries (the
rightmost — nearest — entries are kept) and the 8 KiB per-header budget.
Background fetches (SWR revalidation, refresh-before-expiry, shed refill)
inject proto/host/`Via` from the captured request but deliberately never
append `X-Forwarded-For` — there is no live peer, and replaying the
original requester's address would attribute one user's identity to an
anonymous refresh. `forwarded` requires a pool (rejected on static
routes) and is mutually exclusive with `header_set` entries targeting the
same header.

---

## TCP Fast Open

bouine supports TCP Fast Open on three surfaces, all **disabled by
default since v0.5.29** (previously an unset `listen.tcp_fast_open`
meant "enabled on Linux"):

| Surface | Key | Direction |
|---|---|---|
| Data-plane listeners | `listen.tcp_fast_open` | Server-side TFO on accepts |
| Origin dials | `upstream_pools[].connect.tcp_fast_open` | Client-side `TCP_FASTOPEN_CONNECT` per pool |
| Peer dials | `cluster.peer_tcp_fast_open` | Client-side `TCP_FASTOPEN_CONNECT` on peer fetch/put and invalidation broadcast |

With a kernel-cached TFO cookie, the first request bytes ride in the SYN
packet — one full RTT saved on every fresh connection. The option is
advisory: peers or origins without server-side TFO never issue a cookie
and the dial silently falls back to the regular handshake, so there is no
penalty for enabling it. Linux only (4.11+ for the client side; no-op
elsewhere); the kernel is probed once at startup and an unsupported
option is left unwired with a single warn line. bouine↔bouine peer dials
use TFO end-to-end when both sides opt in — `cluster.peer_tcp_fast_open`
on the dialing side, `listen.tcp_fast_open` on the answering side — and
peers' kernels need `net.ipv4.tcp_fastopen` to include the server bit.
Per-socket failures are best-effort and never fail a dial.

> **Upgrade note (v0.5.29):** deployments relying on the old
> listener-side default must set `listen.tcp_fast_open: true` explicitly
> after upgrading.

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

Most config changes require a process restart. On Kubernetes, use a rolling restart:

```bash
kubectl rollout restart statefulset/bouine
```

For TLS certificate rotation, restart the process or use Kubernetes rolling
restarts with cert-manager.

Since v0.6.0, two runtime surfaces exist on top of the restart path:

- **Hot configuration knobs** (`bouine config get/set/diff`, `GET|POST /v1/config/hot`)
  change genuinely hot-appliable fields on a running daemon without a restart.
  Current knobs: `cluster.ban_ttl`, `url_ring_sample_rate`, and per-pool
  `pool:<name>.health.passive.consecutive_5xx` and `pool:<name>.health.passive.eject_for`.
  Runtime overrides are ephemeral — lost at restart, with drift visible via
  `bouine config diff` — and `bouine config set` fans out to every live peer
  in strong mode (`POST /v1/peer/config/hot`), reporting honest coverage and
  counting failures in `bouine_cluster_broadcast_failures_total{type="hot_set"}`.
  Every attempt is audited and counted in `bouine_config_hot_sets_total`.
- **`bouine config reload` / `POST /v1/config/reload`** (experimental, behind
  `experimental.config_reload`) re-parses and validates a config file on a
  running daemon, applies the hot-appliable subset, and reports applied /
  unchanged / `NEEDS RESTART` sections with reasons. A parse or validation
  failure leaves the running config untouched. Reload is per-node; a disabled
  daemon answers 503 with the opt-in instructions. Audited via
  `bouine_config_reloads_total{result}`.

## Hot configuration

The hot-config knob surface (since v0.6.0, issues #815/#817) lets you change
a registry of genuinely hot-appliable fields on a running daemon:

```bash
bouine config get                          # every knob with live value and source (file / default / runtime)
bouine config set cluster.ban_ttl 45m      # validated point mutation; always prints a not-persisted warning
bouine config set cluster.ban_ttl 45m --dry-run   # validate and report server-side without touching live state
bouine config diff                         # knobs a restart would lose (runtime drift)
bouine config diff a.yaml b.yaml           # preview a deploy: diff two effective configs
bouine config reload --file /etc/bouine/config.yaml   # experimental: apply a file, reports NEEDS RESTART
```

Runtime overrides are deliberately ephemeral (pods are cattle, no sidecar
state) and lost at restart — drift is visible, never silent. Unknown and
cold-only keys are rejected with precise errors; per-route keys stay
cold-only. In strong mode, applied sets propagate to every live peer over
`POST /v1/peer/config/hot` (never re-broadcast, so the fan-out cannot loop);
eventual-mode clusters do not fan out, and dry runs never fan out.

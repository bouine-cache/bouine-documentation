---
title: "Varnish to bouine"
weight: 2
description: "Complete migration guide from Varnish Cache to bouine: conceptual mapping, VCL vs YAML side-by-side, parity tables, behavioral differences, and FAQ."
---

> **Status:** Stable for production use. Assumes familiarity with VCL and bouine's YAML configuration model.

## Quick reference

| Varnish concept | bouine equivalent | Notes |
|---|---|---|
| VCL subroutines | declarative YAML config | bouine uses config, not code |
| `vcl_recv` | `routes[].match` | routing and request matching |
| `vcl_hash` | `routes[].match.headers` | implicit via match rules |
| `vcl_backend_fetch` | `upstream_pools[]` | backend pool config |
| `vcl_backend_response` | origin `Cache-Control` | bouine honors RFC 9111 strictly |
| `beresp.ttl` | `cache.ttl_default` | overridden by origin headers |
| `beresp.grace` | `cache.stale_while_revalidate` | SWR semantics |
| `ban()` | admin API `/admin/bans` | HTTP-based purge API |
| `purge` | admin API `/admin/purge` | exact-match invalidation |
| Varnish log (`-g request`) | `access_logs` | OpenTelemetry-compatible output |
| `varnishstat` | `/admin/stats` | Prometheus-compatible metrics |
| VSM/shared memory | in-process memory | no mmap, no VSM files |

## 1. Conceptual mapping

### The big picture

Varnish is a **programmable cache** — you write VCL to define cache behavior.
bouine is a **declarative cache** — you write YAML to describe routes, backends,
and cache policies, and bouine implements RFC 9111 rigorously.

This means:

- **No VCL**: bouine does not parse or execute VCL. Instead, it uses a YAML
  configuration tree that covers the common use cases handled by VCL.
- **No inline C**: Custom logic must live outside bouine (e.g., in an
  upstream service or a pre-processing edge).
- **No varnishd CLI**: bouine exposes an HTTP admin API and a CLI binary
  (`bouine`).

### Configuration comparison

| Aspect | Varnish | bouine |
|---|---|---|
| Language | VCL (domain-specific, C-like) | YAML |
| Reload | `varnishadm vcl.load` + `vcl.use` (compile and link) | Hot-reload via `SIGHUP` or `/v1/config/reload` |
| Backend definition | `backend` block in VCL | `upstream_pools[]` in YAML |
| Routing | `vcl_recv` with `if/return(pass)` | `routes[].match` declarative table |
| Cache policy | Explicit TTL, grace, keep assignments | RFC 9111 + `routes[].cache` overrides |
| Cluster | Via `varnish-plus` or external HA | Built-in gossip (strong, eventual, full) |
| TLS termination | `varnish-plus` or separate proxy | Built-in (H1+H2+H3) |

## 2. Side-by-side: e-commerce workload

### VCL

```vcl
vcl 4.1;

backend default {
    .host = "origin.internal";
    .port = "8080";
}

sub vcl_recv {
    if (req.method == "POST" || req.method == "PUT" || req.method == "DELETE") {
        return(pass);
    }
    if (req.url ~ "^/api/") {
        return(pass);
    }
    if (req.url ~ "\\.(jpg|png|css|js)$") {
        set req.http.X-Cache-Tier = "static";
    }
    if (req.http.Cookie ~ "sessionID") {
        return(pass);
    }
    if (req.http.Authorization) {
        return(pass);
    }
}

sub vcl_backend_response {
    if (beresp.status >= 500) {
        return(retry);
    }
    if (beresp.ttl <= 0s) {
        set beresp.grace = 5m;
        set beresp.ttl = 1m;
    }
    if (bereq.url ~ "\\.(jpg|png|css|js)$") {
        set beresp.ttl = 1d;
        set beresp.grace = 1h;
    }
    if (beresp.http.Set-Cookie) {
        return(pass);
    }
}

sub vcl_deliver {
    set resp.http.X-Cache-Hits = obj.hits;
}
```

### bouine YAML

```yaml
listen:
  http: ":80"
  https: ":443"
  admin: ":9000"

tls:
  cert_file: /etc/bouine/cert.pem
  key_file: /etc/bouine/key.pem

upstream_pools:
  - name: origin
    targets:
      - origin.internal:8080
    health:
      active:
        enabled: true
        interval: 10s
      passive:
        consecutive_5xx: 3

routes:
  - name: static-assets
    match:
      path_regex: "\\.(jpg|png|css|js)$"
    pool: origin
    cache:
      ttl_default: 1d
      stale_while_revalidate: 1h
      stale_if_error: 5m

  - name: api
    match:
      path_prefix: /api/
    pool: origin
    cache:
      enabled: false

  - name: default
    match:
      path_prefix: /
      methods: [GET, HEAD]
    pool: origin
    cache:
      ttl_default: 5m
      stale_while_revalidate: 30s
      stale_if_error: 5m
      cookies:
        allow_set_cookie: false
      # Authorization header automatically prevents caching per RFC 9111

access_logs:
  format: json
  sample_rate: 0.01
```

### Key differences in the example

| Behavior | VCL | bouine |
|---|---|---|
| POST/PUT/DELETE | `return(pass)` (bypass cache) | `methods: [GET, HEAD]` (only GET/HEAD cached) |
| `/api/` bypass | `return(pass)` in `vcl_recv` | `cache.enabled: false` on matched route |
| Static asset TTL | `set beresp.ttl = 1d` | `ttl_default: 1d` on route match |
| Session cookie | `return(pass)` if Cookie matches | `allow_set_cookie: false` (default) |
| Authorization | `return(pass)` | Not cached by default (RFC 9111) |
| 5xx retry | `return(retry)` | Passive health ejection (configurable) |
| Cache hits header | `obj.hits` | `X-Cache` header added automatically |

## 3. Purge, ban, and refresh parity

| Operation | Varnish | bouine CLI | bouine Admin API |
|---|---|---|---|
| Exact-key purge | `ban("req.url == /products/123")` | `bouine purge https://example.com/products/123` | `POST /v1/purge {"url":"..."}` |
| Predicate ban | `ban("req.http.host ~ example.com && req.url ~ ^/api/")` | `bouine ban host_regex=example.com path_regex=^/api/` | `POST /v1/ban {"host_regex":"...","path_regex":"..."}` |
| Soft-purge (refresh) | `set req.http.n-gage = "1"` or `return(hit_for_pass)` | `bouine refresh https://example.com/products/123` | `POST /v1/refresh {"url":"..."}` |
| Surrogate key ban | `ban("obj.http.Surrogate-Key ~ product-456")` | `bouine ban surrogate_key=product-456` | `POST /v1/ban {"surrogate_key":"..."}` |
| TTL override | `set beresp.ttl = 0s; set beresp.grace = 5m;` | Config reload or per-route `ttl_default` | Not exposed via API (by design) |

### Ban predicate syntax comparison

Varnish bans use a boolean expression language evaluated per-request:

```vcl
ban("req.http.host ~ example.com && req.url ~ ^/products/ && obj.status == 200")
```

bouine uses a JSON predicate object with AND semantics:

```bash
curl -X POST http://127.0.0.1:9000/v1/ban \
  -H "Authorization: Bearer ${BOUINE_ADMIN_TOKEN}" \
  -d '{"host_regex":"example.com","path_regex":"^/products/"}'
```

Note: bouine does not support `obj.status` in ban predicates (this is planned
for Phase 5). Current predicates match against request headers / URL only.

## 4. Observability mapping

### Metrics

| Varnish | bouine |
|---|---|
| `MAIN.cache_hit` | `bouine_cache_result_total{result="HIT"}` |
| `MAIN.cache_miss` | `bouine_cache_result_total{result="MISS"}` |
| `MAIN.n_object` | `bouine_hot_store_objects` (hot tier only) |
| `MAIN.n_expired` | Not directly exposed; use TTL from origin |
| `MAIN.n_lru_nuked` | `bouine_sieve_evictions_total` |
| `MAIN.sess_conn` | `bouine_listener_connections_total` |
| `MAIN.client_req` | `bouine_requests_total` |
| `MAIN.backend_fail` | `bouine_origin_failures_total` |
| `VBE.default.*` | `bouine_upstream_*` metrics |

### Logs

| Varnish | bouine |
|---|---|
| `varnishlog -g request` | Access logs (JSON) |
| `varnishncsa` | Tail access log with custom format |
| VSL tags | Structured JSON fields: `cache_result`, `upstream_pool`, `dur_ms` |

### Dashboard

| Varnish | bouine |
|---|---|
| `varnishstat` | `/metrics` (Prometheus) |
| Varnish Agent / VAC | Built-in dashboard at `/dashboard/` |
| Custom (Grafana) | Standard Prometheus + Grafana |

## 5. Behavioral differences

These are **intentional divergences** where bouine behaves differently from
Varnish by design:

1. **No built-in ESI** — bouine does not parse `<esi:include>` tags. Use
   application-level composition or a CDN with ESI support in front of bouine.

2. **No VMODs** — bouine does not support VMODs. Extend behavior via:
   - Upstream services (e.g., an auth service returning headers)
   - Pre-processing edge (e.g., Envoy with Lua/WASM before bouine)
   - Post-processing (e.g., a sidecar modifying responses)

3. **Strict RFC 9111** — Varnish allows flexible TTL logic. bouine follows
   [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html) and does not allow
   overriding cacheability heuristics via config for compliant responses.
   Non-compliant responses (e.g., missing `Date`) fall back to heuristics.

4. **No hit-for-pass** — Varnish's `return(hit_for_pass)` caches the
   decision-to-not-cache. bouine simply does not store non-cacheable responses;
   the next request re-evaluates cacheability. This is equivalent behavior with
   less state.

5. **Grace is SWR** — Varnish's `grace` covers both stale-while-revalidate
   and stale-if-error. bouine separates these:
   - `stale_while_revalidate`: serve stale while fetching in background
   - `stale_if_error`: serve stale when origin returns 5xx or is unreachable

6. **Surrogate key** — Varnish stores surrogate keys as response header fields.
   bouine reads `Surrogate-Key`, `Cache-Tag`, or `X-Cache-Tags` headers and
   indexes by key for grouped invalidation. No additional configuration needed.

7. **Cluster invalidation** — Varnish requires external tools (e.g., Varnish
   Plus's MSE) for cluster invalidation. bouine propagates purge/ban across
   the cluster natively via HTTP fan-out or gossip, depending on mode.

## 6. Unsupported VCL constructs

These VCL features have no bouine equivalent and require a different
architecture:

| VCL construct | Typical use | bouine alternative |
|---|---|---|
| `vcl_hash` custom key | Cache by API key, session, etc. | `routes[].match.headers` or upstream key extraction |
| `vcl_backend_error` | Synthetic error page | Origin returns error body; bouine caches per RFC 9111 |
| `vcl_deliver` injection | Add headers to all responses | Origin or downstream proxy adds headers |
| ESI | Edge-side includes | Application-level composition or CDN ESI |
| `vcl_synth` | Synthetic responses | Static file server or upstream service |
| `return(pipe)` | TCP pass-through | Layer 4 proxy (e.g., Envoy, HAProxy) |
| `varnishadm` | Runtime CLI commands | Admin API (`/v1/*`) + CLI (`bouine <command>`) |
| VMODs | Custom logic | External service or pre-processing edge |

## 7. Validation checklist

After migrating, verify these behaviors:

- [ ] `Cache-Control: no-store` responses are not cached
- [ ] `Cache-Control: private` responses are not cached
- [ ] `Authorization` requests are not cached (unless `public` is set)
- [ ] `POST` requests are not cached
- [ ] Surrogate-key purge invalidates all matching objects
- [ ] Cluster invalidation reaches all nodes (test with 2+ nodes)
- [ ] Rolling restart produces zero 5xx (test with k6 + StatefulSet)
- [ ] Stale-if-error serves cached responses when origin is down
- [ ] TTL from origin `Cache-Control` is respected over `ttl_default`
- [ ] Vary-based variants are stored separately and purged together

## 8. FAQ

**Q: Can I run bouine and Varnish side by side?**
A: Yes. Deploy bouine behind Varnish (or vice versa) during a gradual
migration. Point a percentage of traffic at bouine to validate behavior
before cutting over.

**Q: How do I migrate my VCL-built surrogate keys?**
A: Add `Surrogate-Key` headers to origin responses (or have Varnish add them
before the response reaches bouine). bouine will index them automatically.
No config change needed.

**Q: What about custom VCL logic (e.g., rate limiting, A/B testing)?**
A: Move logic to an upstream service or a pre-processing proxy. bouine is
intentionally not programmable — it is a cache that strictly implements
RFC 9111. Separation of concerns (cache vs. business logic) is a feature.

**Q: Does bouine support Varnish Plus features (e.g., MSE, TLS, HA)?**
A: bouine replaces Varnish Plus's clustering with native gossip, TLS is
built-in (H3 via quic-go), and HA is handled by Kubernetes or a load
balancer. No separate Plus license needed.

**Q: How do I warm the cache after startup?**
A: Use the `bouine warm` CLI (reads from a URL list or sitemap) or configure
[SWR background refresh](/docs/configuration/cache-policy/) to keep popular
objects warm automatically.

**Q: Can I use the same backend health checks?**
A: bouine supports active HTTP probes and passive outlier detection. See
[upstream pool configuration](/docs/configuration/cluster/) for details. The
`consecutive_5xx` threshold replaces Varnish's `probe` block.

**Q: Will my Varnish stats dashboards work?**
A: Not directly — metric names differ. Plan a migration of Grafana
 dashboards from `varnish_*` to `bouine_*`. The built-in dashboard at
`/dashboard/` provides a zero-config alternative during transition.

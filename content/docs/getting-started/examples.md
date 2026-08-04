---
title: "Example configurations"
weight: 5
description: "Ready-to-adapt bouine YAML examples for static sites, self-served static files, API gateways, bouine-in-front-of-Cloudflare, and e-commerce routes."
---


## Static site / blog

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 64Mo

upstream_pools:
  - name: site
    targets: ["site.default.svc.cluster.local:80"]

routes:
  - match: { path_prefix: /assets/ }
    pool: site
    cache:
      ttl_default: 86400s
      stale_if_error: 604800s
      jitter_percent: 10

  - match: { path_prefix: / }
    pool: site
    cache:
      ttl_default: 300s
      stale_while_revalidate: 60s
      stale_if_error: 86400s
      jitter_percent: 15
```

## Self-served static site (no origin server)

bouine can serve files directly from disk — no separate nginx or Caddy
needed. See [Static file serving](/docs/configuration/static-files/) for
the full reference.

```yaml
listen:
  http: ":8080"
  admin: ":9000"

routes:
  - name: assets
    match: { path_prefix: /assets/ }
    static:
      root: /var/www/assets
      max_file_size: 50MiB
    request:
      strip_prefix: /assets/
    response:
      header_set:
        X-Content-Type-Options: nosniff
        Cache-Control: public, max-age=86400

  - name: root
    match: {}
    static:
      root: /var/www/html
      index: [index.html]
    response:
      header_set:
        X-Content-Type-Options: nosniff
```

No `upstream_pools` section is needed. The OS page cache handles hot
caching. Enable `cache.enabled: true` on static routes when you need
cluster replication or TTL-based eviction.

## API gateway

```yaml
upstream_pools:
  - name: api
    targets: ["api.default.svc.cluster.local:8080"]
    health:
      active:
        path: /healthz
        interval: 5s
        timeout: 1s
        unhealthy_threshold: 3

routes:
  - match: { path_prefix: /v1/ }
    pool: api
    cache:
      ttl_default: 30s
      stale_while_revalidate: 10s
      stale_if_error: 300s
      negative_ttl: 5s
      key:
        include_headers: [Accept-Language]
```

## E-commerce

```yaml
routes:
  - match: { path_prefix: /static/ }
    pool: storefront
    cache:
      ttl_default: 604800s
      stale_if_error: 3600s

  - match: { path_prefix: /products/ }
    pool: storefront
    cache:
      ttl_default: 60s
      stale_while_revalidate: 30s
      stale_if_error: 300s

  - match: { path_prefix: /cart/ }
    pool: cart-api
    cache:
      enabled: false

  - match: { path_prefix: /checkout/ }
    pool: cart-api
    cache:
      enabled: false
```

Private routes should bypass cache entirely. Do not cache cart, checkout, account, or authenticated responses unless the origin explicitly marks them public.

---

## bouine in front of Cloudflare

The origin emits `Cache-Control: max-age=60` intended for the browser and
the Cloudflare edge. bouine's `ttl_override` lets you hold responses for
much longer internally while forwarding the original headers unchanged, so
Cloudflare and the browser still see `max-age=60`.

```yaml
listen:
  http:  ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 512Mo
  warm_dir: /var/cache/bouine
  warm_max_bytes: 10Go

upstream_pools:
  - name: api
    targets: ["api.default.svc.cluster.local:8080"]
    health:
      active:
        path: /healthz
        interval: 5s
        unhealthy_threshold: 3

routes:
  # Public API responses: origin emits max-age=60, but bouine holds for 1 h.
  # Cloudflare (and browsers) still see Cache-Control: max-age=60.
  - name: public-api
    match: { path_prefix: /api/v1/ }
    pool: api
    cache:
      ttl_override: 1h              # bouine's internal TTL
      ttl_default:  30s             # fallback if origin omits Cache-Control
      stale_while_revalidate: 5m   # serve stale during background refresh
      stale_if_error: 24h           # keep serving if origin is down
      jitter_percent: 5             # spread expiry across ±5 %

  # Static assets: long TTL on all layers.
  - name: assets
    match: { path_prefix: /static/ }
    pool: api
    cache:
      ttl_override: 24h
      stale_if_error: 168h   # 1 week
      jitter_percent: 10

  # Authenticated or user-specific routes: must not be cached.
  - name: auth
    match: { path_prefix: /account/ }
    pool: api
    cache:
      enabled: false

cloudflare:
  zone_id: "your-zone-id"
  async: true
  propagate:
    purge: true
    ban: true
    refresh: true
```

**What each layer caches:**

| Layer | `/api/v1/*` | `/static/*` |
|---|---|---|
| bouine (internal) | 1 h (`ttl_override`) | 24 h (`ttl_override`) |
| Cloudflare edge | Origin's `max-age` (e.g. 60 s) | Origin's `Cache-Control` |
| Browser | Origin's `max-age` (e.g. 60 s) | Origin's `Cache-Control` |

See [Cache policy → TTL override](/docs/configuration/cache-policy/#ttl-override)
and [Cloudflare CDN propagation](/docs/operations/cloudflare/) for the full
reference.

## Method-split routes and path rewriting

Cache `GET`/`HEAD` on an API path while passing writes straight through, and
strip the routing prefix so the upstream sees the path it expects.

```yaml
upstream_pools:
  - name: api
    targets: ["api.default.svc.cluster.local:8080"]

routes:
  # Cached reads. strip_prefix rewrites /api/v1/users → /users for the upstream.
  - name: api-reads
    match:
      path_prefix: /api/v1
      methods: [GET, HEAD]
    pool: api
    request:
      strip_prefix: /api/v1
    cache:
      ttl_default: 30s
      stale_while_revalidate: 10s
      max_object_size: 512KiB
      key:
        strip_query_params: [utm_source, fbclid]

  # Writes: same path + prefix rewrite, but never cached.
  - name: api-writes
    match:
      path_prefix: /api/v1
      methods: [POST, PUT, PATCH, DELETE]
    pool: api
    request:
      strip_prefix: /api/v1
    cache:
      enabled: false
```

- `match.methods` lets the **same** `path_prefix` carry two route entries with
  independent cache policies (first match wins, so order reads before writes).
- `request.strip_prefix` rewrites the upstream path but leaves the **cache key**
  on the original path, so `/api/v1/users` and `/api/v2/users` never collide.
- Empty/omitted `methods` matches all methods (the default).

See the [routes field reference](/docs/configuration/#routes) for all options.

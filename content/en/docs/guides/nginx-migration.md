---
title: "Migration from NGINX"
weight: 1
description: "Migrate from NGINX proxy_cache to bouine by mapping directives, cache keys, stale serving, and observability concepts."
---


## Directive mapping

| NGINX directive | bouine config | Notes |
|---|---|---|
| `proxy_cache_path ... max_size=1g` | `storage.hot_max_bytes: 1GiB` | bouine uses in-RAM storage, no filesystem levels |
| `proxy_cache_path ... keys_zone=api:10m` | Not needed | bouine manages shard count automatically (`N=NumCPU`) |
| `proxy_cache_valid 200 60s` | `routes[].cache.ttl_default: 60s` | Per-route, respects `Cache-Control` by default |
| `proxy_cache_valid 404 10s` | `routes[].cache.negative_ttl: 10s` | Negative caching for error responses |
| `proxy_cache_use_stale error http_500 http_502 http_503 http_504` | `routes[].cache.stale_if_error: 30s` | Serves stale on origin 5xx or timeout |
| `proxy_cache_background_update on` | `routes[].cache.stale_while_revalidate: 10s` | Background revalidation while serving stale |
| `proxy_cache_revalidate on` | Built-in | Conditional requests (`If-None-Match`, `If-Modified-Since`) |
| `proxy_cache_key $scheme$host$request_uri` | Automatic | xxhash128 of scheme+host+path+sorted query |
| `proxy_cache_key $scheme$host$request_uri$http_accept` | `cache.key.include_headers: [Accept]` | Explicit header keying |
| `proxy_ignore_headers Vary` | `cache.key.include_headers: [...]` | Explicit header keying instead of Vary |
| `proxy_no_cache $variable` | `routes[].cache.enabled: false` | Per-route disable |
| `proxy_cache_bypass $variable` | Not needed | Use route matching to separate cached/uncached |
| `proxy_cache_lock on` | Built-in (request collapsing) | Single-flight per cache key |
| `proxy_cache_lock_timeout 5s` | Built-in | Subscribers wait for leader fetch |
| `proxy_cache_min_uses 3` | Not needed | bouine caches on first response (RFC 9111) |
| `add_header X-Cache-Status $upstream_cache_status` | Built-in | `X-Cache` header (HIT, MISS, STALE, BYPASS, REVALIDATED) |
| `proxy_next_upstream error timeout` | `upstream_pools[].health.passive` | Passive health checks with outlier ejection |
| `upstream backend { keepalive 32; }` | `upstream_pools[].connect.max_idle_conn_duration: 60s` | Idle pooled-connection lifetime to the origin. Keep bouine's value **below** any LB idle timeout between bouine and the origin (e.g. AWS NLB 350s) so bouine closes idle connections first. |
| `keepalive_timeout 65s` | `listen.idle_timeout: 65s` | Keep-alive idle timeout for client-facing connections. Keep the front-end's value **below** bouine's so the front-end closes idle connections first; otherwise bouine may close a connection mid-reuse and nginx logs `upstream prematurely closed connection`. |

## Key differences

- **No zone configuration** — bouine manages memory automatically with SIEVE eviction
- **No filesystem cache** — bouine uses in-RAM hot tier + mmap warm tier (no `proxy_cache_path` on disk)
- **Clustering built-in** — NGINX requires third-party modules for cache sharing; bouine has gossip + peer fetch
- **RFC 9111 native** — bouine implements the spec directly, not via directives
- **Observability built-in** — Prometheus `/metrics`, structured JSON access logs with `cache_status`
- **No `proxy_pass` needed** — upstream pools are declared separately and referenced by name in routes
- **Declarative config** — no `if` blocks, no `map` directives, no embedded Lua

## Example: API gateway

**NGINX:**
```nginx
proxy_cache_path /var/cache levels=1:2 keys_zone=api:10m max_size=1g;

server {
    location /api/ {
        proxy_cache api;
        proxy_cache_valid 200 60s;
        proxy_cache_use_stale error http_500 http_502;
        proxy_pass http://backend;
    }
}
```

**bouine:**
```yaml
listen:
  http: ":80"
  admin: ":9000"
storage:
  hot_max_bytes: 1GiB
upstream_pools:
  - name: backend
    targets: [backend:8080]
routes:
  - match: { path_prefix: /api/ }
    pool: backend
    cache:
      ttl_default: 60s
      stale_if_error: 30s
```

## Example: Static site with long TTLs

**NGINX:**
```nginx
proxy_cache_path /var/cache levels=1:2 keys_zone=static:10m max_size=2g;

server {
    location /assets/ {
        proxy_cache static;
        proxy_cache_valid 200 1y;
        proxy_cache_lock on;
        add_header X-Cache-Status $upstream_cache_status;
        proxy_pass http://origin;
    }

    location / {
        proxy_cache static;
        proxy_cache_valid 200 10m;
        proxy_pass http://origin;
    }
}
```

**bouine:**
```yaml
listen:
  http: ":80"
  admin: ":9000"
storage:
  hot_max_bytes: 2GiB
upstream_pools:
  - name: origin
    targets: [origin:8080]
routes:
  - match: { path_prefix: /assets/ }
    pool: origin
    cache:
      ttl_default: 8760h  # 1 year
  - match: {}
    pool: origin
    cache:
      ttl_default: 10m
```

## Example: Multiple backends with health checks

**NGINX:**
```nginx
upstream backend {
    server backend1:8080 max_fails=3 fail_timeout=30s;
    server backend2:8080 max_fails=3 fail_timeout=30s;
}

server {
    location / {
        proxy_pass http://backend;
        proxy_next_upstream error timeout http_502 http_503;
    }
}
```

**bouine:**
```yaml
upstream_pools:
  - name: backend
    targets: [backend1:8080, backend2:8080]
    health:
      active:
        path: /healthz
        interval: 10s
        timeout: 2s
        unhealthy_threshold: 3
      passive:
        consecutive_5xx: 3
        eject_for: 30s
routes:
  - match: {}
    pool: backend
    cache:
      ttl_default: 60s
```

## Behavioral differences

| Behavior | NGINX | bouine |
|----------|-------|--------|
| Caching by default | Opt-in (`proxy_cache` directive) | Opt-in (`cache.enabled: true` per route) |
| Cache key | Manual (`proxy_cache_key`) | Automatic (scheme+host+path+sorted query) |
| Vary header | Ignored by default (`proxy_ignore_headers Vary` is common) | Honored by default (RFC 9111) |
| Set-Cookie responses | Cached by default | Not cached by default (opt-in per route) |
| Authorization requests | Cached if response allows | Not cached unless response has `public` or `s-maxage` (RFC 9111 §3.5) |
| Stale serving | Requires `proxy_cache_use_stale` directive | `stale_if_error` and `stale_while_revalidate` per route |
| Negative caching | Via `proxy_cache_valid 404 10s` | `negative_ttl` per route |
| Response header | `$upstream_cache_status` (MISS, HIT, EXPIRED, STALE, UPDATING, REVALIDATED, BYPASS) | `X-Cache` (HIT, MISS, STALE, BYPASS, REVALIDATED) |

## Migration gotchas

1. **Vary is honored by default in bouine** — if your NGINX config ignores Vary (common for
   performance), check that your `Vary` responses won't create excessive variants. Use
   `cache.key.include_headers` for explicit header keying instead of Vary.

2. **Set-Cookie responses are not cached by default** — NGINX caches them. If you need
   Set-Cookie caching, set `cache.allow_set_cookie: true` per route.

3. **No `proxy_cache_path` on disk** — bouine's warm tier uses mmap-backed segments, not
   filesystem cache files. The warm tier is optional and configured via `storage.warm_dir`.

4. **No `if` blocks** — NGINX configs often use `if` for conditional cache behavior. In bouine,
   use separate routes with different match conditions and cache policies.

5. **Clustering changes the cache model** — in NGINX, each instance has an independent cache.
   In bouine strong mode, the consistent hash ring routes each URL to one owner node. This
   improves hit rates but requires peer fetch for non-owner nodes.
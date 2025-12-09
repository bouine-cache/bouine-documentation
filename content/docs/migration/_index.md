---
title: "Migration from NGINX"
weight: 5
description: "Migrate from NGINX proxy_cache to bouine by mapping directives, cache keys, stale serving, and observability concepts."
---

# Migrating from NGINX

## Directive mapping

| NGINX directive | bouine config | Notes |
|---|---|---|
| `proxy_cache_path ... max_size=1g` | `storage.hot_max_bytes: 1Go` | bouine uses in-RAM storage, no filesystem levels |
| `proxy_cache_valid 200 60s` | `routes[].cache.ttl_default: 60s` | Per-route, respects `Cache-Control` by default |
| `proxy_cache_use_stale error http_500 http_502 http_503 http_504` | `routes[].cache.stale_if_error: 30s` | Serves stale on origin 5xx or timeout |
| `proxy_cache_background_update on` | `routes[].cache.stale_while_revalidate: 10s` | Background revalidation while serving stale |
| `proxy_cache_revalidate on` | Built-in | Conditional requests (`If-None-Match`, `If-Modified-Since`) |
| `proxy_cache_key $scheme$host$request_uri` | Automatic | xxhash64 of scheme+host+path+sorted query |
| `proxy_ignore_headers Vary` | `cache.key.include_headers: [...]` | Explicit header keying instead of Vary |
| `proxy_no_cache $variable` | `routes[].cache.enabled: false` | Per-route disable |
| `proxy_cache_bypass $variable` | Not needed | Use route matching to separate cached/uncached |

## Key differences

- **No zone configuration** — bouine manages memory automatically with SIEVE eviction
- **Clustering built-in** — NGINX requires third-party modules for cache sharing
- **RFC 9111 native** — bouine implements the spec directly, not via directives
- **Observability built-in** — Prometheus `/metrics`, structured JSON access logs with `cache_status`

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
  hot_max_bytes: 1Go
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

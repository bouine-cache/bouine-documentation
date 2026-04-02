---
title: "Cache policy"
weight: 2
description: "Understand how bouine chooses TTLs, serves stale content, applies negative caching, jitters expirations, and builds cache keys."
---


## TTL selection

bouine picks freshness in this order:

1. `CDN-Cache-Control` (RFC 9211 targeted header — overrides `Cache-Control` for shared caches)
2. `s-maxage`
3. `max-age`
4. `Expires` (valid dates only; syntactically invalid Expires values are ignored)
5. Route `ttl_default` (operator fallback when origin sends no freshness)
6. Heuristic freshness from `Last-Modified` (10% of `Date − Last-Modified`, where allowed by status code)

## Stale serving

```yaml
cache:
  ttl_default: 60s
  stale_while_revalidate: 10s
  stale_if_error: 300s
```

- `stale_while_revalidate`: serve stale immediately and trigger a background revalidation. The next request gets a fresh `HIT` without any blocking. Concurrency is bounded to 256 simultaneous background revalidations.
- `stale_if_error`: serve stale when the origin returns 5xx or is unreachable, up to the configured window. Unlike SWR, bouine always attempts the origin first and only falls back to stale on error.

## Stayin Alive

When `stale_if_error` expires and the upstream is still down, bouine normally starts returning errors to clients. **Stayin Alive** prevents this — the cached object is served indefinitely until the upstream recovers, regardless of how long ago it expired.

```yaml
routes:
  - match: { path_prefix: /products/ }
    pool: backend
    cache:
      ttl_default: 60s
      stale_if_error: 5m
      stayin_alive: true   # serve stale forever if upstream is down
```

When `stayin_alive: true`:

- If the upstream returns 5xx, bouine serves the last known good response.
- If the upstream is unreachable (connection error, timeout), bouine serves the last known good response.
- If the upstream returns 2xx, the fresh response replaces the stale one as normal.
- If there is **no cached entry at all**, bouine cannot help — it returns 502.

A `WARN` log is emitted on every stale-served request while the upstream is unhealthy:

```json
{"level":"WARN","msg":"stayin-alive: upstream 5xx, serving stale indefinitely","status":503,"key":12345}
```

**When to use it**

Use Stayin Alive for routes where showing slightly stale content is far better than showing an error — product pages, homepages, navigation menus, search results. Do **not** use it for checkout, cart, account, or any route that must reflect real-time state.

## Negative caching

```yaml
cache:
  negative_ttl: 5s
```

Caches 404, 405, 410, and 501 responses briefly. Use this to protect origins from repeated misses.

## Jittered TTLs

```yaml
cache:
  jitter_percent: 10
```

Applies random ±10% TTL jitter to prevent all objects expiring at the same time.

## Cache key headers

```yaml
cache:
  key:
    include_headers:
      - Accept-Language
      - BM-Market
```

Use this when the origin varies by request header. Keep the list short — every extra header increases variant cardinality.

> **Avoid unbounded variants**
>
> Never key on raw `User-Agent`, unbounded cookies, or high-cardinality request IDs. This creates cache fragmentation and can be a cache-poisoning vector.

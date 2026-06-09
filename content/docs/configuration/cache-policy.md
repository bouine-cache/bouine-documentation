---
title: "Cache policy"
weight: 2
description: "Understand how bouine chooses TTLs, overrides them per-route, serves stale content, applies negative caching, jitters expirations, and builds cache keys."
---


## TTL selection

bouine picks freshness in this order:

1. `CDN-Cache-Control` (RFC 9211 targeted header — overrides `Cache-Control` for shared caches)
2. `s-maxage`
3. `max-age`
4. `Expires` (valid dates only; syntactically invalid Expires values are ignored)
5. Route `ttl_default` (operator fallback when origin sends no freshness)
6. Heuristic freshness from `Last-Modified` (10% of `Date − Last-Modified`, where allowed by status code)

If the route has `ttl_override` set, its value **replaces** the result of
this waterfall entirely. See [TTL override](#ttl-override) below.

---

## TTL override

`ttl_override` forces bouine's internal cache lifetime to a specific value,
regardless of what `max-age`, `s-maxage`, `CDN-Cache-Control`, or `Expires`
the origin sends. The upstream's response headers are forwarded to downstream
clients **unaltered** — only bouine's internal freshness counter changes.

```yaml
routes:
  - name: api
    match: { path_prefix: /api/ }
    pool: backend
    cache:
      ttl_override: 1h    # bouine caches for 1 h
      ttl_default:  30s   # fallback if origin sends no freshness headers
      stale_while_revalidate: 5m
```

### Why it exists: bouine in front of a downstream CDN

The canonical use case is a **bouine → Cloudflare** (or bouine → any CDN)
stack where you want to control the two caches independently:

```
Service → bouine → Cloudflare → Client
```

The service emits `Cache-Control: max-age=60`. Without `ttl_override`:

- bouine caches for 60 s, revalidates after each minute.
- Cloudflare sees `Cache-Control: max-age=60` and also caches for 60 s.

With `ttl_override: 1h`:

- bouine caches for **1 h**. The service is hit once per hour per bouine
  node instead of once per minute.
- Cloudflare still receives `Cache-Control: max-age=60` unaltered and
  caches for **60 s** at the edge.
- Clients get low edge latency (Cloudflare's 60 s cache) while the
  origin is shielded by bouine's much longer storage window.

> **TTL override does not mutate the forwarded headers.** `Cache-Control: max-age=60`
> is what Cloudflare (and browsers) see. Only bouine's internal
> storage lifetime changes.

### What the override does NOT affect

| Upstream directive | Behaviour with `ttl_override` set |
|---|---|
| `no-store` | Response is **not cached at all**. Override has no effect. |
| `private` | Response is **not cached at all**. Override has no effect. |
| `no-cache` | Response is stored but **revalidated on every request**. Override is bypassed. |
| `must-revalidate` | Honoured after the override TTL expires. |
| `proxy-revalidate` | Honoured after the override TTL expires. |
| `jitter_percent` | Applied to the override value (not the origin's max-age). |

`no-store` and `private` are evaluated before the object is stored;
the override never runs for these responses.

### Revalidation behaviour

When bouine's override TTL expires it performs a conditional revalidation
(`If-None-Match` / `If-Modified-Since`). If the origin returns `304 Not Modified`,
the override TTL is **re-applied** to the refreshed object — the object does
not revert to the origin's `max-age`. A full `200` is stored fresh with the
override TTL.

### Combining with other cache fields

`ttl_override` composes cleanly with the rest of the cache policy:

```yaml
cache:
  ttl_override: 2h                # bouine keeps for 2 h
  stale_while_revalidate: 10m     # serve stale during background refresh
  stale_if_error: 24h             # serve if origin is down for up to 24 h
  jitter_percent: 5               # ±5 % jitter on the 2 h override
  negative_ttl: 10s               # cache 404s for 10 s (unaffected)
```

`ttl_default` is not superseded when `ttl_override` is set — it remains the
fallback for responses the origin sends **without any freshness headers**.
Set both if your origin is inconsistent about emitting `Cache-Control`.

---

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

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

## Set-Cookie caching

By default, a response carrying a `Set-Cookie` header is **never cached** — even
if it has explicit freshness (`max-age`). This matches nginx's `proxy_cache`
behaviour and prevents one user's session cookie from being replayed to other
users (a session-fixation vector).

```yaml
cache:
  allow_set_cookie: false   # default — Set-Cookie blocks caching
```

To cache such responses anyway, opt in explicitly. When enabled, bouine still
delivers the cookie to the **first** client (the MISS), but **strips
`Set-Cookie` from the stored copy** so subsequent HITs never replay it:

```yaml
cache:
  allow_set_cookie: true    # cache, but strip Set-Cookie from stored object
```

| Upstream sends | `allow_set_cookie: false` (default) | `allow_set_cookie: true` |
|---|---|---|
| `Set-Cookie` + `max-age=60` | Not cached (proxied through) | Cached without `Set-Cookie` |
| `Set-Cookie` + `no-store` | Not cached | Not cached |
| No `Set-Cookie` | Cached normally | Cached normally |

> **Only enable `allow_set_cookie` on routes where the `Set-Cookie` is not
> user-specific** (e.g. a non-personalised A/B cookie). Never enable it on
> authentication or session routes.

## Object size limit

Skip caching responses whose body exceeds a size limit. The response is still
proxied to the client — only storage is skipped, so large downloads don't evict
useful entries:

```yaml
cache:
  max_object_size: 1MiB     # don't cache bodies larger than 1 MiB
```

`0` (default) means no limit.

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

## Stripping query parameters from the key

Tracking and analytics parameters (`utm_source`, `fbclid`, `gclid`, `_ga`, …)
make otherwise-identical URLs into distinct cache entries, fragmenting the
cache. Strip them from the **key** while still forwarding them to the origin:

```yaml
cache:
  key:
    strip_query_params: [utm_source, utm_medium, utm_campaign, fbclid, gclid, _ga]
```

With this config, `/page?id=1&utm_source=email` and `/page?id=1&utm_source=twitter`
resolve to the **same** cache entry. The origin still receives the full query
string (including the tracking params) on a MISS.

> **Purge note**: `POST /v1/purge` computes the key from the URL you send, without
> route context. When using `strip_query_params`, send purge URLs **without** the
> stripped parameters so they match the stored key (same behaviour as Varnish).

## Excluding headers from the cache key

Origins sometimes include per-request headers in `Vary` that should not
fragment the cache — tracing IDs (`X-Request-Id`, `X-Trace-Id`),
forwarding headers (`X-Forwarded-For`), or A/B testing cookies. Each
unique value creates a separate cache entry, wasting storage and reducing
hit rate.

`exclude_headers` strips the listed request header names from the
Vary-based variant key. The origin's `Vary` response header is left
intact and forwarded to the client — only the key computation skips
the excluded headers:

```yaml
cache:
  key:
    exclude_headers:
      - x-request-id
      - x-trace-id
      - x-forwarded-for
```

With this config, two requests that differ only in `X-Request-Id` share
the same cache entry and produce a `HIT`:

```
Request A  X-Request-Id: abc   →  MISS (stored)
Request B  X-Request-Id: xyz   →  HIT  (same entry)
```

### Collapse to primary key

When exclusion removes **all** fields from the Vary list, the variant key
collapses to the primary key. This means every request with the same
scheme, host, path, query, and method shares a single cache entry —
regardless of the excluded header's value.

For example, if the origin sends `Vary: X-Request-Id` and `x-request-id`
is in `exclude_headers`, the variant key equals the primary key. All
requests to the same URL get a HIT after the first fetch.

### Case insensitivity

Header names in `exclude_headers` are matched case-insensitively. Both
`x-request-id` and `X-Request-ID` in the config will match `X-Request-Id`
in the origin's `Vary` header.

### When NOT to use `exclude_headers`

Do not exclude headers that genuinely affect the response body — such as
`Accept-Encoding`, `Accept-Language`, or `Accept`. Excluding a
content-negotiation header causes bouine to serve the wrong variant to
clients (cache poisoning). Only exclude headers you are certain do not
change the response content.

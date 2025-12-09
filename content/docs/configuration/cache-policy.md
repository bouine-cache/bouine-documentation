---
title: "Cache policy"
weight: 2
description: "Understand how bouine chooses TTLs, serves stale content, applies negative caching, jitters expirations, and builds cache keys."
---

# Cache policy

## TTL selection

bouine picks freshness in this order:

1. `s-maxage`
2. `max-age`
3. `Expires`
4. Route `ttl_default`
5. Heuristic freshness from `Last-Modified` (where allowed)

## Stale serving

```yaml
cache:
  ttl_default: 60s
  stale_while_revalidate: 10s
  stale_if_error: 300s
```

- `stale_while_revalidate`: serve stale while refreshing in the background.
- `stale_if_error`: serve stale when the origin fails.

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

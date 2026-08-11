---
title: "缓存失效"
weight: 3
description: "Purge by URL, predicate ban, surrogate-key invalidation, and soft-purge refresh — and how they propagate across cluster peers."
---

## Purge (exact URL)

```bash
# CLI
bouine purge https://example.com/products/123 --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/purge \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/products/123"}'
```

In a cluster, the purge is forwarded to all live peers via HTTP fan-out (in `strong` mode) or gossiped via the memberlist broadcast queue (in `eventual` mode).

## Cluster propagation

The delivery mechanism depends on `cluster.mode`:

| Mode | Purge delivery | Ban delivery | Refresh delivery |
|---|---|---|---|
| `strong` | HTTP fan-out + gossip dual path | HTTP fan-out + gossip dual path | HTTP POST to owner node |
| `eventual` | Gossip only (1–5 s convergence) | Gossip only (1–5 s convergence) | Gossip only |

See [Clustering](/docs/configuration/cluster-modes/) for details on choosing a mode.

## Ban (predicate-based)

```bash
# CLI
bouine ban host_regex=example.com path_regex=^/api/ --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/ban \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"host_regex":"example.com","path_regex":"^/api/"}'
```

Bans use a two-pronged invalidation strategy:

1. **Eager eviction** — all entries currently in the hot store that match the predicate are deleted immediately.
2. **Lazy check** — newly-stored objects are checked against the active ban list on every lookup. This ensures objects filled during the scan window (e.g. from a miss storm) are also invalidated.

Active bans are retained for 24 hours and then pruned automatically.

### Surrogate key ban

```bash
curl -X POST http://127.0.0.1:9000/v1/ban \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"surrogate_key":"product-456"}'
```

Invalidates all objects tagged with the given surrogate key. Origins emit surrogate keys via response headers:

| Header | Used by |
|---|---|
| `Surrogate-Key: <tag> <tag>` | Fastly, RFC 8607 draft |
| `Cache-Tag: <tag>, <tag>` | Cloudflare |
| `X-Cache-Tags: <tag> <tag>` | Varnish / Drupal |

bouine reads whichever header is present (first non-empty header wins) and stores the tags on the cached object.

## Refresh (soft-purge)

```bash
# CLI
bouine refresh https://example.com/products/123 --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/refresh \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/products/123"}'
```

Marks the entry stale — the next request triggers revalidation. If the origin returns `304`, the cached body is reused; the TTL is refreshed from the updated headers.

| Scenario | Use |
|---|---|
| Content is wrong / security issue | **Purge** |
| Content updated, old is OK temporarily | **Refresh** |
| Bulk invalidation by pattern | **Ban** |
| Invalidate all pages for a product | **Ban (surrogate key)** |

## Dashboard invalidation

The **Invalidation** view in the [operator dashboard](/docs/operations/dashboard/) provides the same four operations through a browser UI — no curl required. The forms validate inputs before submitting:

- URLs must begin with `http://` or `https://` and include a host
- Regex fields must be valid RE2 expressions
- At least one ban field (host, path, or surrogate key) must be non-empty

The **Recent invalidations** list updates immediately after each successful operation, showing the operation type, argument, and relative timestamp.

## Cloudflare CDN propagation

When bouine sits behind Cloudflare, invalidation operations can be forwarded to
the Cloudflare Cache API so both caches are cleared together.

See [Cloudflare CDN propagation](/docs/operations/cloudflare/) for full setup
instructions, mapping strategy (URL→PurgeSingleFile, surrogate-key→PurgeByTags,
literal regex→PurgeByPrefixes/Hostnames), async mode, Kubernetes secret wiring,
and monitoring metrics.

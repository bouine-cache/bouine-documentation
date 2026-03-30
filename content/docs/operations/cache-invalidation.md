---
title: "Cache invalidation"
weight: 3
description: "Purge by URL, predicate ban, and soft-purge refresh — and how they propagate across cluster peers."
---

## Purge (exact URL)

```bash
# CLI
bouine purge https://example.com/products/123 --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/purge   -H "Authorization: Bearer <token>"   -H "Content-Type: application/json"   -d '{"url":"https://example.com/products/123"}'
```

In a cluster, the purge is forwarded to the key's owner node.

## Ban (predicate-based)

```bash
# CLI
bouine ban host_regex=example.com path_regex=^/api/ --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/ban   -H "Authorization: Bearer <token>"   -H "Content-Type: application/json"   -d '{"host_regex":"example.com","path_regex":"^/api/"}'
```

Bans are lazy — entries are checked against active bans on each lookup. Broadcast to all peers.

## Refresh (soft-purge)

```bash
# CLI
bouine refresh https://example.com/products/123 --token <token>

# API
curl -X POST http://127.0.0.1:9000/v1/refresh   -H "Authorization: Bearer <token>"   -H "Content-Type: application/json"   -d '{"url":"https://example.com/products/123"}'
```

Marks the entry stale — the next request triggers revalidation. If the origin returns 304, the cached body is reused.

| Scenario | Use |
|---|---|
| Content is wrong / security issue | **Purge** |
| Content updated, old is OK temporarily | **Refresh** |
| Bulk invalidation by pattern | **Ban** |

## Dashboard invalidation

The **Invalidation** view in the [operator dashboard](/docs/operations/dashboard/) provides the same three operations through a browser UI — no curl required. The forms validate inputs before submitting:

- URLs must begin with `http://` or `https://` and include a host
- Regex fields must be valid RE2 expressions
- At least one ban field (host or path) must be non-empty

The **Recent invalidations** list updates immediately after each successful operation, showing the operation type, argument, and relative timestamp.

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

In a cluster, the purge is forwarded to all live peers via HTTP fan-out (in `strong` mode) or gossiped via the memberlist broadcast queue (in `eventual` mode). Since v0.5.14, fan-out is **batched**: purge and refresh events coalesce into batch frames flushed on 256 events, a 10 ms interval, or shutdown — a 1000-key purge burst in a 3-peer cluster produces a handful of batched POSTs instead of 3000 — and receivers deduplicate by per-issuer sequence number. Events arriving on an idle queue still flush synchronously, preserving the purge API's fan-out-before-return guarantee. Ban events stay unbatched (rare; immediacy dominates).

Since v0.5.26, gossip-delivered batch frames are **split to the gossip window** (issue #754): a 256-event batch encodes to ~10 KiB — far above memberlist's ~1.4 KiB UDP gossip window — so before the fix such a frame never fit any gossip round and was re-queued forever, silently dropping the whole batch in `eventual` mode and growing the gossip queue without bound in every mode. Frames are now split at flush time into sub-frames sized to the window, and the gossip drain drops (with `bouine_cluster_gossip_oversized_drops_total`) any frame that could never fit a gossip round, so a regression can no longer wedge the queue. HTTP fan-out is unaffected.

## Cluster propagation

The delivery mechanism depends on `cluster.mode`:

| Mode | Purge delivery | Ban delivery | Refresh delivery |
|---|---|---|---|
| `strong` | HTTP fan-out + gossip dual path | HTTP fan-out + gossip dual path | HTTP POST to owner node |
| `eventual` | Gossip only (1–5 s convergence) | Gossip only (1–5 s convergence) | Gossip only |

See [Clustering](/docs/configuration/cluster-modes/) for details on choosing a mode.

### Data-plane invalidation also propagates (since v0.5.26)

A `POST`/`PUT`/`DELETE` request (RFC 9111 §4.4 invalidation, including `Location`/`Content-Location`-derived keys) previously purged only the receiving node's local store — in `strong` mode an invalidating request landing on a non-owner left the owner serving stale content until TTL, and in `eventual` mode every other node stayed stale. Invalidations from the data plane now broadcast one purge per invalidated key through the same batching pipeline as the admin purge API, in every cluster mode — the broadcast fires even when the local purge reports the key absent (the owner may still hold it). Delivery is enqueue-only (within the same 10 ms coalescing bound every batched event accepts), so the proxied response is never blocked on peer fan-out. Since v0.5.26 a `HEAD` exchange can also no longer poison the cache with an empty body (a `HEAD` revalidation answered `200` used to store the empty response under the shared GET key; background refreshes now remap `HEAD` to `GET` per RFC 9110 §9.3.2).

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

1. **Eager eviction** — all entries currently in the hot store that match the predicate are deleted immediately. Since v0.5.16, **surrogate-only bans skip the eager scan entirely**: the O(1) lazy check below enforces them identically (a banned entry is never served), and memory reclaim moves to the TTL reaper — a ~1800× faster registration path for the dominant production invalidation workload. `POST /v1/ban` therefore reports `count: 0` for surrogate-only bans. Host/path and multi-condition bans keep the coalesced scan (which also deduplicates identical bans registered concurrently, v0.5.14).
2. **Lazy check** — newly-stored objects are checked against the active ban list on every lookup. Since v0.5.15 the ban list is compiled into an immutable snapshot (literal hosts, paths, and surrogate keys become set lookups; anchored prefixes become `HasPrefix` checks), so a full 1024-ban list costs ~22 ns per hit instead of ~10 µs. Since v0.5.26 the snapshot read itself is lock-free on the hit path: the compiled snapshot is published through an atomic pointer with an atomic dirty flag, so the clean steady state pays one uncontended load and a concurrent ban registration rebuilds the snapshot without parking every reader (issue #757 — contended hit + registrations went 594–776 → 178 ns/op, 0 allocs/op).

Active bans are retained for 24 hours by default and then pruned automatically by the reaper. Since v0.5.20 the retention window is configurable via `cluster.ban_ttl` (must be ≥ 1s when set): RFC 9111 §4.4 exempts objects stored *after* the ban from matching, so cache-lifecycle surrogate invalidations are safe at minutes scale — lower it to bound the hit-ratio damage of an over-broad ban (a typo'd ban previously poisoned the hit ratio for the full 24 h).

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

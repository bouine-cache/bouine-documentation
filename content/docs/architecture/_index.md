---
title: "Architecture"
weight: 4
description: "How bouine is structured internally: listeners, pipeline, storage, cache engine, origin pools, clustering, and observability."
---


## Layered design

bouine is structured in 9 layers, each testable in isolation.

{{< arch-diagram >}}

## HTTP stacks

Two HTTP implementations only:


- **`net/http`** — HTTP/1.1 + HTTP/2 (data plane + admin)
- **`quic-go/http3`** — HTTP/3 (data plane only)


Both share `http.Handler`. The admin API uses `net/http.ServeMux`.

## Cache engine

The RFC 9111 state machine is deterministic: inputs are `*http.Request`, stored `*Object`, and `now`. Outputs are `HIT`, `MISS`, `REVALIDATE`, `STALE_HIT`, or `BYPASS`.

### Cache key

Primary key: `xxhash64(scheme | host | path | sorted_query | method)`

Secondary key (Vary): derived from the request headers listed in the response's `Vary` header, or from `cache.key.include_headers`.

### Eviction


- **SIEVE** (default) — simple, near-LRU-K performance, O(1) per operation
- **W-TinyLFU** (planned) — better hit ratio under skewed access patterns; not yet implemented (tracked as Phase 5.5)


### CDN-Cache-Control (RFC 9211)

When the origin sends a `CDN-Cache-Control` header, it takes precedence over `Cache-Control` for all shared-cache decisions. This allows origins to set different TTLs for CDN caches vs browser caches:

```http
Cache-Control: no-store              # browsers don't cache
CDN-Cache-Control: max-age=3600      # bouine caches for 1h
```

### Surrogate keys

Origins can tag responses with opaque surrogate keys for grouped invalidation:

```http
Surrogate-Key: product-456 category-shoes
Cache-Tag: product-456, category-shoes
```

bouine reads `Surrogate-Key`, `Cache-Tag`, and `X-Cache-Tags` at store time and makes them available for `POST /v1/ban{surrogate_key:"..."}` invalidation.

### Negative caching

404, 405, 410, 501 responses can be cached for a configurable duration (`negative_ttl`).

### Jittered TTLs

Random ±N% applied to every TTL to prevent synchronized expiry stampedes across cached entries.

## Clustering

bouine supports three consistency modes (see [Cluster Consistency Modes](/docs/configuration/cluster-modes/)):

### Strong mode (default)

**Sharding**: Consistent hash with 256 virtual nodes per real node. On a miss, the requesting node checks the owner node before going to origin.

### Eventual mode

Every node is independent — no sharding, no peer-fetch. Invalidations propagate via gossip only. Each node caches whatever it receives from origin.

### Full mode

Every node holds a full replica of the cached object set. Objects are actively replicated via gossip on every cacheable fill. Invalidations use HTTP fan-out (sub-second, same as strong).

### Membership (all modes)

`hashicorp/memberlist` for gossip. Nodes bootstrap via StatefulSet DNS.

### Peer fetch flow (strong mode only)

{{< peer-fetch-diagram >}}

Added latency for a peer hit: ~0.3ms (one in-cluster HTTP/2 hop).

### Stale-while-revalidate (SWR)

When an object enters its `stale-while-revalidate` window, bouine:

1. Serves the stale object immediately (no client wait).
2. Fires a background goroutine (`bgRevalSem` bounds concurrency to 256) that conditionally revalidates with the origin.
3. The origin reply (200 or 304) updates the hot store; the next request gets a fresh `HIT`.

This is what eliminates the 93% effective hit rate gap vs Varnish in mixed workloads — both caches serve stale immediately and refresh asynchronously.

### Invalidation propagation

| Operation | `strong` | `eventual` | `full` |
|---|---|---|---|
| **Purge** | HTTP fan-out to all peers + gossip | Gossip only (1–5 s convergence) | HTTP fan-out to all peers + gossip |
| **Ban** | HTTP fan-out to all peers + gossip | Gossip only | HTTP fan-out to all peers + gossip |
| **Refresh** | Forwarded to key's owner node | Gossip only | HTTP fan-out to all peers |

In `strong` and `full` modes, the HTTP fan-out ensures sub-second invalidation propagation. The gossip broadcast queue provides a redundant delivery path.


### Join protocol

Pods retry joining every 2 seconds for up to 60 seconds. Success requires `Members() > 1` (at least one real peer, not self-join). The headless Service **must** have `publishNotReadyAddresses: true`.

## Performance

| Benchmark | Result |
|---|---|
| `Evaluate_Hit` | 40 ns/op, 0 allocs |
| `HotStore_Get_Hit` | 5.4 ns/op, 0 allocs |
| `Handler_CacheHit` | 537 ns/op, 8 allocs |
| `BuildKey` (query params) | 46 ns/op, 0 allocs |
| `SIEVE_Access` | 5.4 ns/op, 0 allocs |

Load-test results (Docker, 3k RPS, single node vs Varnish + nginx):

| Scenario | bouine | nginx | varnish |
|---|---|---|---|
| Hit-only (warm cache) | 166 µs avg | 166 µs avg | 177 µs avg |
| Miss storm (no-store) | 157 µs avg | degraded | 166 µs avg |
| Mixed 60/15/10/5/5 | 230 µs avg | 22 ms avg† | 199 µs avg |

†nginx's high mixed average is due to blocking revalidation; bouine and Varnish both use background SWR refresh.

All gates enforced in CI — regressions block merge.

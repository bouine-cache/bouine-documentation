---
title: "架构"
weight: 4
description: "How bouine is structured internally: listeners, pipeline, storage, cache engine, origin pools, clustering, and observability."
---


## Layered design

bouine is structured in 8 layers, each testable in isolation.

{{< arch-diagram >}}

## HTTP stacks

One HTTP implementation only:

- **`fasthttp`** — HTTP/1.1 only (data plane + admin)

The admin API uses a manual method+path router on `fasthttp.Server`.

> **HTTP/2 is not currently available.** bouine previously supported HTTP/2
> (h2 over TLS, h2c over plaintext) via Go's `net/http`. In v0.5.0 the
> entire data plane was migrated from `net/http` to `fasthttp` (ADR-0034),
> achieving a zero-allocation hit path and exceeding pre-migration
> benchmark performance. HTTP/2 was dropped because `fasthttp` is
> HTTP/1.1 only. HTTP/2 reintroduction is in progress, planned as a
> `fasthttp`-native implementation rather than re-adopting `net/http`.

## Cache engine

The RFC 9111 state machine is deterministic: inputs are `*http.Request`, stored `*Object`, and `now`. Outputs are `HIT`, `MISS`, `REVALIDATE`, `STALE_HIT`, or `BYPASS`.

### Cache key

Primary key: 128-bit `XXH128(scheme | host | path | sorted_query | method)`. The full 16-byte hash is used as a map key, providing 128-bit collision resistance without a separate lookup step. Zero allocations via one-shot `Sum128`.

Secondary key (Vary): derived from the request headers listed in the response's `Vary` header, or from `cache.key.include_headers`.

### Eviction


- **SIEVE** — simple, near-LRU-K performance, O(1) per operation
- **mmap slab** (optional, Linux) — hot body bytes are allocated via mmap to avoid Go heap GC pressure (`storage.hot_mmap_slab: true`)


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

bouine supports two consistency modes (see [Clustering](/docs/configuration/cluster-modes/)):

### Strong mode (default)

**Sharding**: Consistent hash with 256 virtual nodes per real node. On a miss, the requesting node checks the owner node before going to origin.

### Eventual mode

Every node is independent — no sharding, no peer-fetch. Invalidations propagate via gossip only. Each node caches whatever it receives from origin.


### Membership (all modes)

`hashicorp/memberlist` for gossip. Nodes bootstrap via StatefulSet DNS.

### Peer fetch flow (strong mode only)

{{< peer-fetch-diagram >}}

Added latency for a peer hit: ~0.3ms (one in-cluster HTTP/1.1 hop).

As of v0.5.0, origin responses are streamed with pipelined peer fetch:
when a node forwards a request to the owner node and the owner has a
cache miss, the owner streams the origin response back to the requesting
node in a single pipelined pass. This eliminates the store-then-forward
round trip that existed before the `fasthttp` migration.

### TCP_QUICKACK

bouine enables `TCP_QUICKACK` on accepted data-plane connections (Linux
only) to reduce latency by acknowledging data immediately rather than
delaying the ACK. This complements `TCP_FASTOPEN` and `TCP_DEFER_ACCEPT`
on the listen path.

### Stale-while-revalidate (SWR)

When an object enters its `stale-while-revalidate` window, bouine:

1. Serves the stale object immediately (no client wait).
2. Fires a background goroutine (`bgRevalSem` bounds concurrency to 256) that conditionally revalidates with the origin.
3. The origin reply (200 or 304) updates the hot store; the next request gets a fresh `HIT`.

This is what eliminates the 93% effective hit rate gap vs Varnish in mixed workloads — both caches serve stale immediately and refresh asynchronously.

### Invalidation propagation

| Operation | `strong` | `eventual` |
|---|---|---|
| **Purge** | HTTP fan-out to all peers + gossip | Gossip only (1–5 s convergence) |
| **Ban** | HTTP fan-out to all peers + gossip | Gossip only |
| **Refresh** | Forwarded to key's owner node | Gossip only |

In `strong` mode, the HTTP fan-out ensures sub-second invalidation propagation. The gossip broadcast queue provides a redundant delivery path.


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

> The v0.5.0 `fasthttp` migration achieved a zero-allocation hit path and
> exceeds pre-migration benchmark performance. All hot-path code uses
> pre-computed cache-control flags, status lines, Date formatting, and
> Vary values to avoid per-request allocations.

Load-test results (Docker, 3k RPS, single node vs Varnish + nginx):

| Scenario | bouine | nginx | varnish |
|---|---|---|---|
| Hit-only (warm cache) | 166 µs avg | 166 µs avg | 177 µs avg |
| Miss storm (no-store) | 157 µs avg | degraded | 166 µs avg |
| Mixed 60/15/10/5/5 | 230 µs avg | 22 ms avg† | 199 µs avg |

†nginx's high mixed average is due to blocking revalidation; bouine and Varnish both use background SWR refresh.

All gates enforced in CI — regressions block merge.

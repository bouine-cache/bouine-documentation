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
- **W-TinyLFU** (optional) — better hit ratio under skew


### Negative caching

404, 405, 410, 501 responses can be cached for a configurable duration (`negative_ttl`).

### Jittered TTLs

Random ±N% applied to every TTL to prevent synchronized expiry stampedes across cached entries.

## Clustering

### Membership

`hashicorp/memberlist` for gossip. Nodes bootstrap via StatefulSet DNS.

### Sharding

Consistent hash with 256 virtual nodes per real node. On a miss, the requesting node checks the owner node before going to origin.

### Peer fetch flow

{{< peer-fetch-diagram >}}

Added latency for a peer hit: ~0.3ms (one in-cluster HTTP/2 hop).

### Invalidation propagation


- **Purge**: forwarded to the key's owner node
- **Ban**: broadcast to all peers
- **Refresh**: forwarded to the key's owner node


### Join protocol

Pods retry joining every 2 seconds for up to 60 seconds. Success requires `Members() > 1` (at least one real peer, not self-join). The headless Service **must** have `publishNotReadyAddresses: true`.

## Performance

| Benchmark | Result |
|---|---|
| `Evaluate_Hit` | 100 ns/op, 0 allocs |
| `HotStore_Get_Hit` | 5.4 ns/op, 0 allocs |
| `Handler_CacheHit` | 626 ns/op, 9 allocs |
| `SIEVE_Access` | 5.4 ns/op, 0 allocs |

All gates enforced in CI — regressions block merge.

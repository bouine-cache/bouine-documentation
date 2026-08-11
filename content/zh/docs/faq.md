---
title: "常见问题"
weight: 99
description: "Frequently asked questions about bouine."
---

## General

### How is bouine different from Varnish?

bouine is designed for Kubernetes from day one: gossip clustering, Helm
chart, Prometheus metrics, and OpenTelemetry tracing are built-in. Varnish
requires commercial Varnish Plus or external orchestration for clustering,
and uses VCL (an imperative DSL) instead of declarative YAML. See the
[migration guide](../guides/varnish-migration/) for a side-by-side comparison.

### How is bouine different from NGINX?

NGINX is a general-purpose reverse proxy with caching bolted on. bouine is
a cache-first reverse proxy: every feature is designed around RFC 9111
compliance, cache hit rates, and invalidation precision. NGINX uses
`proxy_cache` directives; bouine uses declarative per-route cache policies.
See the [migration guide](../guides/nginx-migration/) for directive mapping.

### Can I use bouine without Kubernetes?

Yes. bouine runs as a single binary with a YAML config file. Clustering
works with any DNS-based discovery (not just Kubernetes headless services).
Docker Compose works fine for development. Kubernetes is the primary target
but not a requirement.

### Does bouine need an external database or cache?

No. bouine uses an embedded in-RAM hot tier (sharded map) and an mmap-backed
warm tier (local disk). No Redis, Memcached, or etcd is required.

## Caching

### What is the cache key composed of?

The primary cache key is built from: scheme, host (lowercased), path
(percent-decoded and re-encoded canonically), query (parameters sorted
lexicographically), and method (GET and HEAD share the key space). A
secondary key (Vary) is derived from headers listed in the response's
`Vary` header. See the [architecture reference](../architecture/) for
details.

### How do I debug cache misses?

Check the `X-Cache` response header: `MISS` means the object was not in
cache, `BYPASS` means the cache was bypassed (no-store, no-cache, or cache
disabled for the route). Use the `X-Cache-Source` header to see which tier
served the response (`hot`, `warm`, `peer`, `origin`).

The `GET /v1/debug/cachecheck?url=...` admin endpoint shows the full
decision tree for a given request (key, hit/miss, source).

### Does bouine support WebSocket?

No. bouine passes through WebSocket upgrade requests but never caches them.
Use a separate reverse proxy for WebSocket traffic.

### Does bouine support ESI?

Not in v1.0. ESI-lite (`<esi:include>`) is on the roadmap for v1.1+ if
demand materializes. Most modern architectures prefer client-side composition
or CDN-layer ESI.

### How does bouine handle Vary headers?

bouine canonicalizes `Vary` and builds a secondary cache key from the
listed headers. `Vary: *` disables caching. Vary variants are capped to
prevent cache poisoning via uncontrolled header variation.

## Clustering

### What cluster mode should I use?

- **Strong** (default): consistent-hash ring, peer fetch on miss. Best
  cache hit rates when each URL is served by one owner node.
- **Eventual**: each node caches independently, gossip for invalidation
  only. Best for read-heavy workloads where peer-fetch latency is
  unacceptable.

See the [cluster modes guide](../operations/cluster-modes/) for details.

### What happens when a node joins or leaves?

On join: the new node announces itself via gossip, the ring rebalances,
and new requests are routed to the new owner. The new node starts cold
(no key migration). On leave: the node drains in-flight requests, leaves
the gossip membership, and peers stop routing to it.

### Can I run bouine across multiple regions?

Not in v1.0. Multi-region federation (cross-cluster tiering, regional
cache-of-caches) is a v1.2+ roadmap item.

## Configuration

### Can I reload config without restarting?

No. bouine does not support live config reload. Config changes are
applied by rolling the pod (standard Kubernetes rolling update). This
avoids race conditions between reloadable and non-reloadable components.

### Does bouine support environment variable interpolation in config?

Yes. `${VAR}` and `${VAR:-default}` are expanded in the YAML config before
decoding. `$$` escapes to a literal `$`.

### How do I invalidate cached objects?

Three mechanisms:
- **Purge** (`POST /v1/purge`): exact URL removal
- **Ban** (`POST /v1/ban`): predicate-based (host regex, path regex)
- **Refresh** (`POST /v1/refresh`): soft-purge, marks stale and triggers
  revalidation on next request

See the [cache invalidation guide](../operations/cache-invalidation/).

## Performance

### What is the hit-path budget?

Less than 5 us CPU per request at p50, with zero allocations after warm-up.
The hit path is benchmark-gated in CI: `allocs/op == 0` for `Evaluate_Hit`,
`HotStore_Get_Hit`, and `FastPath_Hit`.

### How does bouine compare to Varnish on throughput?

Benchmark results are published in the [benchmarks guide](../guides/benchmarks/).
bouine matches or exceeds Varnish single-node RPS on the canonical workload.

### Why is my p99 latency spiking?

Check for GC pauses (tune `GOMEMLIMIT` and `GOGC`), working set overflow
(hot tier too small), or revalidation storms (increase `jitter_percent`).
The Grafana dashboard has a "GC max pause vs HIT p99" panel for this.
---
title: "Cluster consistency modes"
weight: 4
description: "bouine's three cluster consistency modes — strong, eventual, and full — how they differ, and how to choose."
---

bouine supports three cluster consistency modes, controlled by `cluster.mode`:

| Mode | YAML value | Default? | Overview |
|------|-----------|----------|----------|
| **Strong** | `strong` | ✅ | Consistent-hash sharding with peer-fetch. One copy per key. |
| **Eventual** | `eventual` | — | Independent caching per node. Invalidations via gossip only. |
| **Full** | `full` | — | Every node holds a full replica. Objects broadcast on fill. |

```yaml
cluster:
  enabled: true
  mode: strong        # "strong" (default) | "eventual" | "full"
  join:
    - "bouine-0.bouine-headless.default.svc.cluster.local:8443"
```

---

## Comparison table

| Concern | `strong` | `eventual` | `full` |
|---------|----------|------------|--------|
| **Hit rate** (warm cluster) | High — keys concentrated on owner | Medium — each node cold-starts independently | Highest — all keys on all nodes |
| **Miss latency** | +1 RTT (peer-fetch to owner, then origin) | Direct to origin | Direct to origin |
| **Memory per node** | Working set ÷ N | 1–N× (overlap varies) | N× (full working set) |
| **Node failure impact** | Keys owned by lost node → cold miss | None for already-cached keys | None |
| **Invalidation propagation** | HTTP fan-out (sub-second) + gossip dual path | Gossip only (1–5 s convergence) | HTTP fan-out (sub-second) + gossip for replication |
| **Cross-node traffic** | Peer-fetch RPCs + HTTP inv fan-out | Gossip invalidations only | Gossip everything (inv + replication) |
| **Object replication** | None — one copy per key | None — each node fills independently | Active — broadcast on every fill |
| **Ideal cluster size** | Any (3–50+) | Any (2–50+) | Small (2–5 nodes) |
| **Best for** | Memory-constrained large clusters; strict consistency | CDN edge PoPs; geo-distributed deployments | Small clusters where hits matter more than memory |

---

## Strong mode

The default. A consistent-hash ring (256 virtual nodes per node) determines which node *owns* each cache key.

**Request flow:**

1. Node receives a request, computes the cache key.
2. Looks up key in local store → HIT returns immediately.
3. MISS: if the key is owned by a peer, forwards a `POST /v1/peer/fetch` RPC to the owner.
4. Peer HIT: object returned and promoted to local hot tier.
5. Peer MISS or error: falls through to origin.

**Invalidation flow:**

- Purge and ban are delivered via **HTTP fan-out** to all live peers (sub-second).
- A secondary gossip broadcast provides redundant delivery if a peer's HTTP port is temporarily unreachable.
- Refresh is forwarded to the key's owner node only.

**Dashboard:** shows the consistent-hash ring with per-node key distribution.

---

## Eventual mode

Every node is independent — no sharding, no peer-fetch. Each node caches whatever it receives from origin.

**Request flow:**

1. Node receives a request, looks up in local store.
2. HIT → returns immediately. MISS → fetches from origin directly (no peer hop).

**Invalidation flow:**

- Purge, ban, and refresh are delivered **exclusively via gossip** (no HTTP fan-out).
- Convergence window: 1–5 seconds. A stale read is possible during convergence.
- This eliminates N-1 HTTP POSTs per invalidation, reducing cross-pod chatter.

**When to use:**

- CDN edge deployments where each PoP operates independently.
- Geo-distributed clusters where cross-region latency makes peer-fetch costly.
- Deployments where slightly stale reads are acceptable in exchange for zero miss latency.

**Dashboard:** shows per-node fill rates and gossip invalidation stats instead of the ring.

---

## Full mode

Every node holds a full replica of the cached object set. Objects are actively replicated on fill.

**Request flow:**

1. Node receives a request, looks up in local store.
2. HIT → returns immediately. MISS → fetches from origin directly.
3. On a cacheable store, the full object is broadcast to all peers via gossip.

**Invalidation flow:**

- Purge and ban use **HTTP fan-out** (sub-second, same as strong mode).
- Object replication uses **gossip**: when a node stores a cacheable response, it broadcasts the full object to all peers. Peers receive and store it in their local hot tier.
- Replication convergence: ~1 second under normal network conditions.

**Memory and bandwidth:**

- Each node needs enough RAM to hold the **entire working set** (`hot_max_bytes` must cover it).
- Replication gossip adds bandwidth proportional to the cache fill rate. On a 5-node cluster with 1k cacheable fills/s and avg 50 KiB responses, replication bandwidth is ~50 MB/s per node.
- Only cacheable responses are replicated (not `no-store`, not errors, not bypass).

**When to use:**

- Small clusters (2–5 nodes) where memory is plentiful.
- Deployments where maximum hit rate and resilience matter more than memory efficiency.
- Read-heavy workloads where cache misses are expensive.

**Dashboard:** shows per-node fill stats, replication throughput, and gossip convergence metrics.

---

## Switching modes

Mode changes require a full cluster restart (rolling restart recommended).

1. Pick a rolling restart strategy: one node at a time (`kubectl delete pod bouine-N --grace-period=60`)
2. Update the `cluster.mode` field in your ConfigMap
3. Trigger a config reload or restart all pods in sequence

See the [cluster mode migration guide](/docs/migration/cluster-modes/) for detailed procedures.

---

## Metrics

Each mode exposes specific Prometheus metrics:

| Metric | Available in |
|--------|-------------|
| `bouine_cluster_mode_info{mode="..."}` | All modes |
| `bouine_peer_fetch_hits_total` | `strong` only |
| `bouine_peer_fetch_misses_total` | `strong` only |
| `bouine_peer_fetch_duration_seconds` | `strong` only |
| `bouine_cluster_invalidations_http_total{type="purge\|ban"}` | `strong`, `full` |
| `bouine_cluster_invalidations_gossip_total{type="purge\|ban"}` | All modes |
| `bouine_cluster_replications_sent_total` | `full` only |
| `bouine_cluster_replications_received_total` | `full` only |
| `bouine_cluster_replication_bytes_total{direction="sent\|received"}` | `full` only |

---

## Startup warnings

bouine logs warnings at startup when the configuration suggests a mismatch:

- `hop_limit` set in `eventual` or `full` mode → warns that it is a no-op.
- `mode: full` with a small `hot_max_bytes` → warns that memory may be insufficient.
- `replicas` set in `full` or `eventual` mode → warns that the field has no effect outside `strong`.
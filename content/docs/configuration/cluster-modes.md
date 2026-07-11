---
title: "Clustering"
weight: 5
description: "Configure bouine clustering: consistency modes, gossip membership, peer fetch, mTLS, invalidation propagation, and metrics."
---

Cluster mode lets multiple bouine pods share cache reads, broadcast invalidations, and reduce origin load.

## Choosing a mode

```yaml
cluster:
  enabled: true
  mode: strong        # "strong" (default) | "eventual"
```

Use this decision guide:

- **Memory-constrained or large cluster (3–50+ nodes)?** → `strong` — one copy per key, peer-fetch on miss.
- **Geo-distributed or CDN edge PoPs?** → `eventual` — independent caching, gossip-only invalidation, zero miss-latency penalty.
- **Small cluster (2–5 nodes) where hits matter more than RAM?** → `full` — every node holds every key.

| Concern | `strong` | `eventual` | `full` |
|---------|----------|------------|--------|
| **Hit rate** (warm) | High — keys concentrated on owner | Medium — each node cold-starts | Highest — all keys on all nodes |
| **Miss latency** | +1 RTT (peer-fetch) | Direct to origin | Direct to origin |
| **Memory per node** | Working set ÷ N | 1–N× (overlap varies) | N× (full working set) |
| **Node failure impact** | Owner keys → cold miss | None | None |
| **Invalidation speed** | Sub-second (HTTP fan-out + gossip) | 1–5 s (gossip only) | Sub-second (HTTP fan-out + gossip) |
| **Cross-node traffic** | Peer-fetch RPCs + fan-out | Gossip only | Gossip replication + fan-out |
| **Ideal cluster size** | 3–50+ | 2–50+ | 2–5 |

---

## Cluster config

```yaml
listen:
  cluster: ":8443"

cluster:
  enabled: true
  mode: strong         # "strong" (default) | "eventual"
  join:
    - "bouine-0.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-1.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-2.bouine-headless.default.svc.cluster.local:8443"
  replicas: 2          # only used in strong mode
  hop_limit: 2         # only used in strong mode
```

On Kubernetes, gossip peer discovery requires a headless Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: bouine-headless
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: bouine
  ports:
    - name: cluster-tcp
      port: 8443
      protocol: TCP
    - name: cluster-udp
      port: 8443
      protocol: UDP
```

> **Required**: `publishNotReadyAddresses: true` — without it, StatefulSet pod DNS may not resolve during startup and gossip will fail to form a cluster.

For inter-node mTLS, see [TLS → Cluster TLS](/docs/configuration/tls/#cluster-tls-mtls).

---

## Strong mode (default)

A consistent-hash ring (256 virtual nodes per node) determines which node *owns* each cache key.

{{< strong-mode-diagram >}}

**Request flow:**

1. Node receives a request, computes the cache key.
2. Looks up key in local store → HIT returns immediately.
3. MISS: if the key is owned by a peer, forwards a `POST /v1/peer/fetch` RPC to the owner.
4. Peer HIT: object returned and promoted to local hot tier.
5. Peer MISS or error: falls through to origin.

Typical peer-fetch latency: ~0.5–2 ms on the same datacenter LAN.

**Invalidation:** Purge and ban are delivered via HTTP fan-out to all live peers (sub-second). A secondary gossip broadcast provides redundant delivery. Refresh is forwarded to the key's owner node only.

> **Anti-entropy**: Nodes exchange ring digests on every gossip push/pull cycle. If a peer was unreachable during a rolling restart, it is automatically re-added to the ring when digests diverge.

---

## Eventual mode

Every node is independent — no sharding, no peer-fetch. Each node caches whatever it receives from origin.

{{< eventual-mode-diagram >}}

**Request flow:**

1. Node receives a request, looks up in local store.
2. HIT → returns immediately. MISS → fetches from origin directly (no peer hop).

**Invalidation:** Purge, ban, and refresh are delivered exclusively via gossip. Convergence window: 1–5 seconds. Stale reads are possible during convergence.

**When to use:**

- CDN edge deployments where each PoP operates independently.
- Geo-distributed clusters where cross-region latency makes peer-fetch costly.
- Deployments where slightly stale reads are acceptable in exchange for zero miss latency.

---


## Invalidation propagation summary

| Operation | `strong` | `eventual` | `full` |
|---|---|---|---|
| Purge | HTTP fan-out + gossip | Gossip only | HTTP fan-out + gossip |
| Ban | HTTP fan-out + gossip | Gossip only | HTTP fan-out + gossip |
| Refresh | HTTP POST to owner | Gossip only | HTTP fan-out to all |

---

## Switching modes

Mode changes require a full cluster restart (rolling restart recommended).

1. Update `cluster.mode` in your ConfigMap.
2. Rolling restart all pods: `kubectl rollout restart statefulset/bouine`.
3. Verify: `curl -s http://127.0.0.1:9000/metrics | grep bouine_cluster_mode_info`.

Cache state is **not preserved** across mode switches — nodes start with empty caches. Expect elevated miss rates for the first few minutes.

See the [cluster mode operations page](/docs/operations/cluster-modes/) for detailed verification and troubleshooting procedures per mode.

---

## Debugging peers

```bash
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
# or via the admin API:
curl http://localhost:9000/v1/cluster/peers
```

Should show every pod in the StatefulSet with `addr` set to the pod IP (not `0.0.0.0`).

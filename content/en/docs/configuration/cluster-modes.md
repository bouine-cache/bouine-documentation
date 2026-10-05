---
title: "Clustering"
weight: 5
description: "Configure bouine clustering: consistency modes, gossip membership, peer fetch, mTLS, invalidation propagation, and metrics."
---

Cluster mode lets multiple bouine pods share cache reads, broadcast invalidations, and reduce origin load.

## Choosing a mode

```yaml
listen:
  cluster: ":8443"

cluster:
  mode: strong        # "strong" (default) | "eventual"
```

Use this decision guide:

- **Memory-constrained or large cluster (3–50+ nodes)?** → `strong` — one copy per key, peer-fetch on miss.
- **Geo-distributed or CDN edge PoPs?** → `eventual` — independent caching, gossip-only invalidation, zero miss-latency penalty.

---

## Cluster config

```yaml
listen:
  cluster: ":8443"

cluster:
  mode: strong         # "strong" (default) | "eventual"
  join:
    - "bouine-0.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-1.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-2.bouine-headless.default.svc.cluster.local:8443"
  hop_limit: 2                      # only used in strong mode
  peer_max_conns_per_host: 8        # pipelined peer connections (8 × 16 pending = 128 fetches/peer)
  peer_max_idle_conn_duration: 120s # MUST stay below admin.idle_timeout (default 300s)
  peer_fetch_concurrency: 4         # concurrent peer-fetch/put RPCs per node (1–128)
  ban_ttl: 24h                      # how long invalidation bans stay active (≥ 1s when set)
```

The `peer_max_idle_conn_duration` ↔ `admin.idle_timeout` ordering matters:
peer RPCs ride keep-alive connections pooled by the client. If the admin
server reaps an idle connection before the client closes it, the next
peer-fetch or peer-put fails with `EOF` and falls back to origin, spiking
latency. Config validation rejects any explicit combination that violates
the ordering.

Two sizing knobs matter under strong-mode load (both added in v0.5.11):

- **`peer_fetch_concurrency`** (default 4, range 1–128) bounds concurrent
  peer-fetch/peer-put RPCs per node. In strong mode most cache hits are
  peer hits, so this semaphore sits on the hot path — raise it together
  with `peer_max_conns_per_host` so the pipeline clients stay the binding
  constraint. Excess callers wait up to 100 ms for a slot, then shed to
  the slow path / origin fallback.
- **`ban_ttl`** (default 24h, ≥ 1s when set; added in v0.5.20) bounds how
  long invalidation bans stay in the active ban list. See
  [Cache invalidation](/docs/operations/cache-invalidation/).

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

**Invalidation:** Purge and ban are delivered via HTTP fan-out to all live peers (sub-second). A secondary gossip broadcast provides redundant delivery. Refresh is forwarded to the key's owner node only. Since v0.5.26, **data-plane invalidations (POST/PUT/DELETE per RFC 9111 §4.4) also fan out** through the same batching pipeline as the admin purge API — a write landing on a non-owner node no longer leaves the owner serving stale content until TTL. The data-plane hook is enqueue-only (10 ms coalescing bound), so the proxied response is never blocked on peer fan-out.

> **Anti-entropy**: Nodes exchange ring digests on every gossip push/pull cycle. If a peer was unreachable during a rolling restart, it is automatically re-added to the ring when digests diverge.

> **Wire format (since v0.5.22):** memberlist node metadata (peer info) and push/pull state (ring digests) are binary frames (magic + version header); receivers reject unversioned or unknown-version frames, and peer-fetch requests only accept the binary v2 format. Mixed-version clusters running a pre-v0.5.22 build will fail to exchange meta/state during a rolling upgrade — upgrade all nodes together. Also since v0.5.22 the admin API and Go SDK parse request bodies with `encoding/json/v2`: duplicate JSON keys and misspelled (case-mismatched) field names are rejected with `400` instead of silently accepted.

### Peer-fetch resilience (v0.5.17–v0.5.20)

The peer-fetch machinery is hardened against rolling restarts, HPA
scale-down, and miss storms:

- **Background reconcile pass** (default every 30s) re-derives the peer
  set from memberlist's live member view, healing missed leave/update
  notifications after a peer restart.
- **Per-address failure breaker** — three consecutive transport failures
  blacklist an address for a 30s cooldown; Fetch/Put return immediately
  and the handler falls back to origin. Tripped addresses surface in the
  `bouine_peer_addr_blacklisted` gauge.
- **Bounded RPC budgets** — all peer-fetch/put RPCs are capped at a 500 ms
  budget and the peer dial timeout is 200 ms, so dead peers fail fast
  instead of pinning fetch slots.
- **Bounded queue wait + shedding** — callers waiting for a
  `peer_fetch_concurrency` slot shed after 100 ms
  (`bouine_peer_fetch_shed_total`); the queue wait itself is observed in
  `bouine_peer_fetch_queue_wait_seconds`.
- **Background re-warm** — a shed foreground miss schedules a bounded
  background refill (`bouine_rewarm_fill_total`), so a shed miss no longer
  loses the cache refill and miss storms converge back to hits.

---

## Eventual mode

Every node is independent — no sharding, no peer-fetch. Each node caches whatever it receives from origin.

{{< eventual-mode-diagram >}}

**Request flow:**

1. Node receives a request, looks up in local store.
2. HIT → returns immediately. MISS → fetches from origin directly (no peer hop).

**Invalidation:** Purge, ban, and refresh are delivered exclusively via gossip. Convergence window: 1–5 seconds. Stale reads are possible during convergence. Data-plane invalidations (POST/PUT/DELETE) broadcast the same way (since v0.5.26). Since v0.5.26, gossip batch frames larger than the ~1.4 KiB UDP gossip window are split into standalone sub-frames at flush time (previously a full 256-event batch could never fit a gossip round and was re-queued forever, silently dropping the batch — issue #754); `bouine_cluster_gossip_oversized_drops_total` counts frames that could never fit and are dropped defensively.

**When to use:**

- CDN edge deployments where each PoP operates independently.
- Geo-distributed clusters where cross-region latency makes peer-fetch costly.
- Deployments where slightly stale reads are acceptable in exchange for zero miss latency.

---


## Invalidation propagation summary

| Operation | `strong` | `eventual` |
|---|---|---|
| Purge | HTTP fan-out + gossip | Gossip only |
| Ban | HTTP fan-out + gossip | Gossip only |
| Refresh | HTTP POST to owner | Gossip only |
| Data-plane invalidation (POST/PUT/DELETE) | Batched broadcast, all modes (since v0.5.26) | Batched broadcast (gossip) |

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

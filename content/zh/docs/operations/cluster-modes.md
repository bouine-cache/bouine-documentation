---
title: "集群一致性模式"
weight: 3.5
description: "Verify, diagnose, and switch between strong and eventual cluster consistency modes."
---

## Verify your mode

```bash
# Prometheus metric: always 1 with the mode label.
curl -s http://127.0.0.1:9000/metrics | grep bouine_cluster_mode_info

# Admin API: /v1/cluster/peers returns all members in every mode.
curl -s http://127.0.0.1:9000/v1/cluster/peers \
  -H "Authorization: Bearer ${BOUINE_ADMIN_TOKEN}"

# CLI
bouine cluster peers --server 127.0.0.1:9000 --token "${BOUINE_ADMIN_TOKEN}"
```

Expected: every node reports the same `mode` label. If they disagree, the cluster
has a configuration drift — every pod must use the same mode.

## Per-mode expectations

### `strong` (default)

| Check | Expected |
|---|---|
| Dashboard shows ring | Yes — consistent-hash ring with per-node key slices |
| Peer-fetch metrics increment | `bouine_peer_fetch_hits_total` > 0 |
| Purge hits all nodes | < 1 s via HTTP fan-out |
| Node failure | Keys owned by lost node → cold miss on all nodes for those keys |

**When things go wrong:**

- **Purge didn't propagate.** Check `bouine_cluster_invalidations_http_total`.
  If zero, the admin port may be unreachable. Verify `cluster.tls` config and
  network policies. The gossip broadcast queue provides a secondary delivery path
  (check `bouine_cluster_invalidations_gossip_total`).

- **Peer fetch is slow or failing.** Check `bouine_peer_fetch_duration_seconds`
  (should be < 2 ms on LAN). If elevated, check cluster network health (`kubectl
  get endpoints bouine-headless`). Increase `hop_limit` if node churn is high.

### `eventual`

| Check | Expected |
|---|---|
| Dashboard shows ring | No — shows per-node fill rates and gossip stats |
| Peer-fetch metrics | Always zero (no peer fetch) |
| Purge propagation | 1–5 s via gossip; stale reads possible during convergence |
| Node failure | No impact — each node has its own cache |

**When things go wrong:**

- **Purge didn't propagate within 5 seconds.** Check gossip membership:
  ```bash
  curl -s http://127.0.0.1:9000/v1/cluster/peers
  ```
  Should show 3+ nodes on every pod. If a node is missing, check its `cluster.join`
  list and DNS resolution. The headless Service must have
  `publishNotReadyAddresses: true`.

- **Stale reads on one node.** That node may be partitioned. Check
  `bouine_cluster_invalidations_gossip_total` — if the counter hasn't
  incremented recently, the gossip link is broken. Restart the node.

- **Hit rate lower than expected.** Each node cold-starts independently in
  `eventual` mode. Over time, hit rate naturally plateaus as each node fills its
  cache from origin traffic. If load is unevenly distributed across nodes
  (e.g. session affinity), some nodes may have much lower hit rates.

## Memory and bandwidth budget

### `strong` mode

- Memory per node: working set ÷ N (where N = cluster size).
- Bandwidth: minimal. Peer-fetch RPCs are small (key hashes, HTTP headers).
  HTTP fan-out is infrequent (only on invalidation).

### `eventual` mode

- Memory per node: 1–N× depending on traffic overlap. With round-robin load
  balancing, expect ~1× (each node caches ~1/N of the working set).
- Bandwidth: minimal. Gossip invalidations only.

## Switching modes

Mode changes require a full cluster restart. The procedure differs per mode:

### From `strong` to `eventual`

1. Update `cluster.mode` in your ConfigMap.
2. Rolling restart all pods one by one (`kubectl rollout restart statefulset/bouine`).
3. Verify `bouine_cluster_mode_info{mode="..."}` on every pod.

No data migration needed — each node starts with an empty cache.

### From `eventual` to `strong`

1. Update `cluster.mode: strong` in your ConfigMap.
2. Add `hop_limit` field if missing.
3. Rolling restart. The consistent-hash ring forms within seconds of all nodes
   joining.
4. Cache state from `eventual` is **not preserved** — nodes start with
   empty caches. Expect elevated miss rates for the first few minutes until
   caches warm up.

## Alerts

```yaml
# Alert if cluster mode differs across pods (configuration drift).
- alert: ClusterModeMismatch
  expr: count(count by (mode) (bouine_cluster_mode_info == 1)) > 1
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Cluster mode mismatch — pods running different consistency modes"
```

## Troubleshooting quick reference

| Symptom | Mode | Probable cause | Check |
|---|---|---|---|
| Purge doesn't propagate | `strong` | Admin port unreachable | `bouine_cluster_invalidations_http_total` |
| Purge doesn't propagate | `eventual` | Gossip partition | `bouine_cluster_invalidations_gossip_total`, peers list |
| Stale reads | `eventual` | Gossip convergence window | Wait 5 s, re-check. If persistent, check gossip. |
| Low hit rate | `eventual` | Uneven node fill | Check per-node hit rates, consider `strong` |
| Node join fails | all | DNS not resolving | `kubectl get endpoints`, verify `publishNotReadyAddresses` |

---
title: "Troubleshooting"
weight: 99
description: "Troubleshoot common bouine production issues: cache misses, cluster problems, rolling restart failures, invalidation, and origin health."
---

## `X-Cache` is always `MISS`

Check:

1. The response is cacheable (`Cache-Control` is not `no-store`, `private`, `max-age=0`).
2. The route actually matches.
3. The origin returns a cacheable status (usually `200`).
4. Request headers are not producing many variants.

Useful commands:

```bash
curl -sI http://127.0.0.1:8080/path
kubectl logs statefulset/bouine -n bouine | grep cache_status
```

## Pods do not discover each other

Check the headless Service:

```bash
kubectl get svc bouine-headless -n bouine -o yaml | grep publishNotReadyAddresses
```

It must be:

```yaml
publishNotReadyAddresses: true
```

Check peer list:

```bash
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

If each pod only sees itself, look for join logs:

```bash
kubectl logs bouine-1 -n bouine | grep -i 'join\|cluster'
```

## Rolling restart produces 503/502

| Symptom | Likely cause | Fix |
|---|---|---|
| 503 during rollout | `preStop` hook too short; kube-proxy updated Endpoints before pod drained | Increase `sleep` in `preStop` to 10 s |
| 502 after new pod starts | New pod not yet joined gossip ring; peer-fetch fails | Check `/readyz` — should fail until ring joined; increase `initialDelaySeconds` |
| Rollout stuck | PDB `minAvailable` prevents eviction | Check `kubectl get pdb`; verify at least `minAvailable` pods are Ready |
| Long rollout | `terminationGracePeriodSeconds` too high relative to actual drain time | Reduce to `max(in_flight_p99_ms / 1000, 15)` seconds |

## Purge does not propagate across cluster

### In `strong` or `full` mode

- Check `bouine_cluster_invalidations_http_total{type="purge"}`. If zero,
  the admin port may be unreachable. Verify `cluster.tls` config and
  network policies.
- The gossip broadcast queue provides a secondary delivery path
  (check `bouine_cluster_invalidations_gossip_total`).

### In `eventual` mode

- Gossip-only convergence takes 1–5 s. Stale reads are possible during this
  window.
- Check peer list: `curl -s http://127.0.0.1:9000/v1/cluster/peers`. Should
  show 3+ nodes on every pod.
- The headless Service must have `publishNotReadyAddresses: true`.

## Stale reads

- In `eventual` mode: expected during gossip convergence. If persistent,
  check `bouine_cluster_invalidations_gossip_total` — if flat, the gossip
  link is broken. Restart the node.
- In `full` mode: check `bouine_cluster_replications_received_total`. If it
  is zero despite `bouine_cluster_replications_sent_total` > 0,
  the gossip queue may be full.

## Docker build is slow on Apple Silicon

Use `buildx` and cross-compile rather than emulating amd64:

```bash
docker buildx build --platform linux/amd64 -t thylong/bouine:dev --load .
```

bouine's Dockerfile uses `BUILDPLATFORM` and `TARGETARCH` so Go builds natively.

## Memory pressure in `full` mode

`full` mode stores the entire working set on every node.

Symptoms:
- Hit rate drops on nodes that recently received replications.
- SIEVE eviction spikes visible via the dashboard.
- `bouine_hot_store_bytes / bouine_hot_store_max_bytes > 0.9`.

Fixes:
- Increase `hot_max_bytes` to at least the total working set size.
- Switch to `strong` or `eventual` mode.

## Low hit rate in `eventual` mode

Each node cold-starts independently. Over time, hit rate naturally plateaus.
If load is unevenly distributed across nodes (e.g. session affinity), some
nodes may have much lower hit rates. Consider `strong` or `full` mode.

## Runbook quick reference

For detailed procedures, see the operator runbooks in the bouine repository
(`docs/runbook/`):

- [00-lifecycle](https://github.com/thylong/bouine/blob/main/docs/runbook/00-lifecycle.md) — start, stop, reload, drain
- [10-cluster-modes](https://github.com/thylong/bouine/blob/main/docs/runbook/10-cluster-modes.md) — verify, diagnose, and switch between `strong`, `eventual`, and `full` modes
- [20-purge-ban](https://github.com/thylong/bouine/blob/main/docs/runbook/20-purge-ban.md) — cache invalidation via purge, ban, and refresh
- [30-rolling-restart](https://github.com/thylong/bouine/blob/main/docs/runbook/30-rolling-restart.md) — zero-5xx rolling restart in Kubernetes

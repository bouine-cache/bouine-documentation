---
title: "Kubernetes operations"
weight: 5
description: "Scale, update, and verify cluster health for bouine running on Kubernetes."
---

## Scaling

```bash
kubectl scale statefulset/bouine -n <namespace> --replicas=3
```

Gossip auto-discovers peers via the headless Service DNS. New pods join the cluster within 60s.

## Rolling update (zero 5xx)

```bash
kubectl rollout restart statefulset/bouine -n <namespace>
kubectl rollout status statefulset/bouine -n <namespace> --timeout=180s
```

StatefulSet rolls one pod at a time (reverse ordinal). Each pod must pass the readiness probe (`GET /readyz`) before the next is replaced.

### Prerequisites for zero 5xx

| Requirement | Why |
|---|---|
| `PodDisruptionBudget minAvailable: 2` | Prevents evicting two pods simultaneously on a 3-node cluster |
| `preStop: sleep 5` | Gives kube-proxy time to drain the pod from Endpoints before SIGTERM |
| `terminationGracePeriodSeconds: 30` | Must exceed the longest in-flight request + drain budget (10 s) |
| Readiness probe on `/readyz` | Traffic is removed before shutdown, restored only when the new pod is ready |

The Helm chart ships with all of these enabled by default when `podDisruptionBudget.enabled: true`.

### Automated verification

```bash
bash bench/loadtest/scenarios/4.5_rolling_update/run.sh
```

Runs k6 at 1k RPS during the restart and asserts that the 5xx rate stays at 0%.

## Verifying cluster health

```bash
kubectl exec bouine-0 -n <namespace> -- /bouine cluster peers
# or via admin API:
curl -s http://localhost:9000/v1/cluster/peers | jq '.[].name'
```

Should show every pod in the StatefulSet. Each entry includes `addr` (gossip port), `admin_addr`, and `data_addr`.

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
| `terminationGracePeriodSeconds` ≥ 30 s | Must exceed the longest expected in-flight request + cluster leave timeout (10 s). |
| `preStop` hook (sleep 5 s) | Kubernetes removes the pod from Endpoints asynchronously; the hook lets existing connections drain before `SIGTERM` arrives. |
| `PodDisruptionBudget minAvailable: 2` | Prevents evicting two pods simultaneously on a 3-node cluster. |
| `readinessProbe` on `/readyz` | Traffic is removed before the pod enters `Terminating` only if the probe fails; new pod receives traffic only once it passes. |
| `publishNotReadyAddresses: true` on the headless Service | Ensures DNS resolves all StatefulSet pods (including unready ones) for gossip seed discovery. |

The Helm chart ships with all of these enabled by default when `podDisruptionBudget.enabled: true`.

### Step-by-step

```bash
# 1. Check that PDB is in place
kubectl get pdb -n bouine-prod

# 2. Start background traffic monitor (check for 5xx in real time)
kubectl -n bouine-prod logs -f -l app=bouine --prefix=true | \
  grep '"status":5' &
MONITOR_PID=$!

# 3. Trigger rolling restart
kubectl -n bouine-prod rollout restart statefulset/bouine

# 4. Wait for rollout (≈ 3 × terminationGracePeriodSeconds)
kubectl -n bouine-prod rollout status statefulset/bouine --timeout=180s

# 5. Verify no 5xx in the monitoring window
kill $MONITOR_PID 2>/dev/null
kubectl -n bouine-prod exec -it deploy/traffic-gen -- \
  bash -c 'grep -c "HTTP/1.1 5" /tmp/access.log || echo "0 errors"'
```

### Automated verification (SLO DP-5)

The `bench/loadtest/scenarios/4.5_rolling_update/run.sh` scenario runs k6 at
1 k RPS while executing a rolling restart and asserts that the 5xx error rate
stays at 0 %.

```bash
# Against K8s cluster
bash bench/loadtest/scenarios/4.5_rolling_update/run.sh
```

Expected output: `✓ http_req_failed rate<0.001%`.

### Helm chart settings (reference)

```yaml
# deploy/helm/bouine/values.yaml

# Ensures Kubernetes drains endpoints before SIGTERM.
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 5"]

terminationGracePeriodSeconds: 30

# Prevents simultaneous eviction of two pods.
podDisruptionBudget:
  enabled: true
  minAvailable: 2

# Traffic only routed to ready pods.
readinessProbe:
  httpGet:
    path: /readyz
    port: 9000
  initialDelaySeconds: 5
  periodSeconds: 3
  failureThreshold: 3
```

## Troubleshooting

See the [Troubleshooting](/docs/operations/troubleshooting/#rolling-restart-produces-503502) page for rolling restart issues (503/502 during rollout, stuck rollouts, etc.).

## Verifying cluster health

```bash
kubectl exec bouine-0 -n <namespace> -- /bouine cluster peers
# or via admin API:
curl -s http://localhost:9000/v1/cluster/peers | jq '.[].name'
```

Should show every pod in the StatefulSet. Each entry includes `addr` (gossip port), `admin_addr`, and `data_addr`.

---
title: "Lifecycle"
weight: 1
description: "Start, stop, and drain bouine in production and Kubernetes."
---

## Starting bouine

```bash
bouine serve --config /etc/bouine/config.yaml --log-format json
```

On Kubernetes the StatefulSet container runs this command via the Helm
chart (see `deploy/helm/bouine/templates/statefulset.yaml`). The
`--log-format json` flag ensures structured logging for aggregation.

### Startup sequence

1. Config loaded and validated.
2. Storage tiers initialised (hot → warm).
3. Admin server starts on `listen.admin` (default `:9000`).
4. `/readyz` returns `200` once all listeners are bound.
5. Cluster join (if `listen.cluster` is set): memberlist contacts seed nodes
   with retry (every 2s for up to 60s). Join succeeds once at least
   one peer besides self is discovered. StatefulSet headless Service
   must have `publishNotReadyAddresses: true` for DNS to resolve
   during startup.
6. Data-plane listeners start on `listen.http`, `listen.https`.
7. Active health checks begin for all upstream pools.

### Readiness vs liveness

| Probe | Endpoint | Meaning |
|---|---|---|
| Readiness | `/readyz` | All listeners bound, ready for traffic. |
| Liveness | `/healthz` | Process alive, can serve admin requests. |

Kubernetes will not route traffic until `/readyz` returns `200`. A
failed liveness probe triggers a pod restart.

## Stopping (graceful shutdown)

bouine uses a `shutdown.Sequencer` (`internal/runtime/shutdown`) that
runs registered steps in order, each with a time budget:

1. **Mark not ready** — `/readyz` returns `503`. Kubernetes stops
   sending new connections. The `preStop` hook sleeps one readiness
   period to let in-flight probes propagate.
2. **Drain data-plane listeners** — stop accepting new connections,
   finish in-flight requests within budget.
3. **Leave cluster** — `memberlist.Leave` with a timeout so peers
   remove this node from the hash ring.
4. **Flush storage** — WAL sync, warm-tier segment close.
5. **Close admin** — final metrics scrape window, then shutdown.

The total budget is `terminationGracePeriodSeconds` (Helm default: 40s).

### Manual stop

```bash
kill -TERM <pid>
# or on Kubernetes:
kubectl delete pod bouine-0
```

SIGTERM triggers the sequencer. SIGKILL (after grace period) is a hard
kill — avoid if possible.

## Config updates

bouine does not support live config reload. Config changes require a
rolling pod restart. This is intentional: storage, cluster, and TLS
settings cannot be safely reconfigured at runtime, and keeping reload
out of the critical path removes a class of race conditions.

On Kubernetes, update the ConfigMap and rolling-restart:

```bash
kubectl rollout restart statefulset/bouine
```

The graceful shutdown sequence (below) ensures zero-5xx rolling updates
when combined with a PodDisruptionBudget and readiness probes.

## Drain (Kubernetes rolling update)

During a rolling update, Kubernetes sends SIGTERM to the old pod. The
graceful shutdown sequence (above) handles draining.

### Best practices

- Set `terminationGracePeriodSeconds` ≥ 30s (Helm default).
- PodDisruptionBudget (`minAvailable: 1`) prevents draining all replicas
  simultaneously.
- The `preStop` sleep ensures the endpoints controller removes the pod
  from the Service before connections stop.
- Monitor `bouine_inflight_requests` to confirm drain completes.

### Rolling update order

For a 3-replica StatefulSet:

1. `bouine-2` is terminated and drained.
2. New `bouine-2` starts, passes readiness, joins cluster.
3. `bouine-1` is terminated and drained.
4. … and so on.

The consistent-hash ring rebalances automatically as nodes join/leave.

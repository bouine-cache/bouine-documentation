---
title: "故障排查"
weight: 99
description: "Troubleshoot common bouine production issues: cache misses, cluster problems, rolling restart failures, invalidation, and origin health."
---

## Quick reference

| Symptom | Severity | Jump to |
|---------|----------|---------|
| Pods don't discover each other | **Critical** | [Cluster discovery](#pods-do-not-discover-each-other) |
| Rolling restart produces 503/502 | **High** | [Rolling restart](#rolling-restart-produces-503502) |
| Purge doesn't propagate | **High** | [Purge propagation](#purge-does-not-propagate-across-cluster) |
| HIT p99 spikes to 50–100 ms under load | **High** | [GC stop-the-world pauses](#hit-p99-spikes-to-50100-ms-under-load) |
| `X-Cache` always MISS | **Medium** | [Cache misses](#x-cache-is-always-miss) |
| Stale reads on one node | **Medium** | [Stale reads](#stale-reads) |
| Low hit rate in eventual mode | **Low** | [Low hit rate](#low-hit-rate-in-eventual-mode) |
| Docker build slow on Apple Silicon | **Low** | [Docker build](#docker-build-is-slow-on-apple-silicon) |

---

## Cluster discovery

### Pods do not discover each other

**Check the headless Service:**

```bash
kubectl get svc bouine-headless -n bouine -o yaml | grep publishNotReadyAddresses
```

Must be `publishNotReadyAddresses: true`. Without it, DNS does not resolve during pod startup and gossip fails.

**Check peer list:**

```bash
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

If each pod only sees itself, check join logs:

```bash
kubectl logs bouine-1 -n bouine | grep -i 'join\|cluster'
```

---

## Rolling restart produces 503/502

| Symptom | Likely cause | Fix |
|---|---|---|
| 503 during rollout | `preStop` hook too short; kube-proxy updated Endpoints before pod drained | Increase `sleep` in `preStop` to 10 s |
| 502 after new pod starts | New pod not yet joined gossip ring; peer-fetch fails | Check `/readyz` — should fail until ring joined; increase `initialDelaySeconds` |
| Rollout stuck | PDB `minAvailable` prevents eviction | Check `kubectl get pdb`; verify at least `minAvailable` pods are Ready |
| Long rollout | `terminationGracePeriodSeconds` too high relative to actual drain time | Reduce to `max(in_flight_p99_ms / 1000, 15)` seconds |

See [Kubernetes operations](/docs/operations/kubernetes/) for the full zero-5xx rolling update procedure.

---

---

## HIT p99 spikes to 50–100 ms under load

### Symptom

`X-Cache: HIT` responses have p99 latency of 50–100 ms even though the
cache is warm and the origin is healthy. The spike is reproducible under
concurrent load and persists regardless of cluster mode. In Prometheus:

```promql
histogram_quantile(0.99,
  rate(bouine_request_duration_seconds_bucket{cache_result="HIT"}[1m]))
```

### Root cause: Go GC stop-the-world pauses

The most common cause is the Go runtime's garbage collector running too
aggressively because `GOMEMLIMIT` is set too low relative to actual RSS.

**Confirm with:**

```bash
# Check GC worst-case pause and the configured GOMEMLIMIT
curl -s http://127.0.0.1:9000/metrics | grep -E 'go_gc_duration|go_gc_gomemlimit'
```

```
go_gc_duration_seconds{quantile="1"}  0.095   ← worst-case pause ~95 ms
go_gc_gomemlimit_bytes                7.55e+07 ← GOMEMLIMIT = 72 MiB
```

If `go_gc_duration_seconds{quantile="1"}` is in the same range as your
observed HIT p99, GC pauses are the cause. This typically happens when:

- `GOMEMLIMIT` is set well below the pod memory limit.
- The hot cache is near or exceeding `GOMEMLIMIT` — forcing the GC to
  run almost continuously and occasionally triggering a long STW cycle
  to reclaim enough memory to stay under the limit.

### Fix: tune GOMEMLIMIT to 85 % of the pod memory limit

Set `GOMEMLIMIT` to approximately **85 % of `resources.limits.memory`**
so the GC has headroom to collect lazily rather than continuously.

**Kubernetes StatefulSet / Deployment:**

```yaml
env:
  - name: GOMEMLIMIT
    value: "82MiB"   # 85% of a 96Mi pod limit
  - name: GOGC
    value: "100"     # default; keep paired with GOMEMLIMIT
```

**Helm chart (`values.yaml`):**

```yaml
goMemLimit: "3GiB"   # 85% of resources.limits.memory
```

**Rule of thumb:**

| Pod memory limit | Recommended GOMEMLIMIT |
|---|---|
| 128 Mi | 108 Mi |
| 256 Mi | 216 Mi |
| 512 Mi | 435 Mi |
| 1 Gi | 870 Mi |
| 4 Gi | 3.4 Gi |

After the change, verify that `go_gc_duration_seconds{quantile="1"}`
drops to < 5 ms under the same load. If the pod's RSS still exceeds
`GOMEMLIMIT` at peak, consider also increasing `hot_max_bytes` or the
pod memory limit.

### Other causes of HIT p99 spikes

If GC pauses are small but HIT p99 is still elevated, check:

| Metric | What to look for | Fix |
|---|---|---|
| `go_goroutines` growing unboundedly | Goroutine leak | File an issue; check for stuck peer-fetch goroutines |
| `bouine_cluster_invalidations_http_total` spiking | Invalidation fan-out on hot path | Use gossip-only (`eventual` mode) for write-heavy workloads |
| `process_cpu_seconds_total` near `limits.cpu` | CPU throttling (CFS) | Raise `limits.cpu` or reduce VUs |
| `bouine_vary_cap_hits_total` non-zero | Vary header explosion | Add `Vary` normalisation or increase `MaxVariants` |

---

## Cache misses

### `X-Cache` is always `MISS`

Check:

1. The response is cacheable (`Cache-Control` is not `no-store`, `private`, `max-age=0`).
2. The route actually matches — verify with access logs (`route` field).
3. The origin returns a cacheable status (usually `200`).
4. Request headers are not producing many variants — check `bouine_vary_cap_hits_total`.

```bash
curl -sI http://127.0.0.1:8080/path
kubectl logs statefulset/bouine -n bouine | grep cache_status
```

---

## Purge does not propagate across cluster

### In `strong` mode

- Check `bouine_cluster_invalidations_http_total{type="purge"}`. If zero, the admin port may be unreachable. Verify `cluster.tls` config and network policies.
- The gossip broadcast queue provides a secondary delivery path (check `bouine_cluster_invalidations_gossip_total`).

### In `eventual` mode

- Gossip-only convergence takes 1–5 s. Stale reads are expected during this window.
- Check peer list: `curl -s http://127.0.0.1:9000/v1/cluster/peers`. Should show 3+ nodes.
- The headless Service must have `publishNotReadyAddresses: true`.

---

## Stale reads

- **In `eventual` mode**: expected during gossip convergence (1–5 s). If persistent, check `bouine_cluster_invalidations_gossip_total` — if flat, the gossip link is broken. Restart the node.

---

## Low hit rate in `eventual` mode

Each node cold-starts independently. Over time, hit rate naturally plateaus. If load is unevenly distributed across nodes (e.g. session affinity), some nodes may have much lower hit rates. Consider `strong` mode.

---

## Docker build is slow on Apple Silicon

Use `buildx` and cross-compile rather than emulating amd64:

```bash
docker buildx build --platform linux/amd64 -t bouinecache/bouine:dev --load .
```

bouine's Dockerfile uses `BUILDPLATFORM` and `TARGETARCH` so Go builds natively.

---

## Runbook quick reference

For detailed procedures, see the operator runbooks in the bouine repository (`docs/runbook/`):

- [00-lifecycle](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/00-lifecycle.md) — start, stop, reload, drain
- [10-cluster-modes](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/10-cluster-modes.md) — verify, diagnose, and switch modes
- [20-purge-ban](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/20-purge-ban.md) — cache invalidation operations
- [30-rolling-restart](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/30-rolling-restart.md) — zero-5xx rolling restart

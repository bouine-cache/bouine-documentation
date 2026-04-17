---
title: "Monitoring"
weight: 4
description: "Key Prometheus metrics, access log fields, OpenTelemetry tracing, and admin API endpoints for observing bouine."
---

## Metrics overview

All metrics are exposed at `GET /metrics` in Prometheus exposition format.

### Traffic metrics

| Metric | Labels | Description |
|---|---|---|
| `bouine_requests_total` | `method`, `status`, `cache_result`, `route` | Total requests processed |
| `bouine_request_duration_seconds` | `method`, `status`, `cache_result`, `route` | Request latency histogram |
| `bouine_response_bytes_total` | `method`, `route` | Total bytes written in responses |

**`cache_result`** label values: `HIT`, `MISS`, `STALE`, `REVALIDATED`, `BYPASS`.

**`route`** label: set from the `name` field of the matched route (e.g. `"api-v1"`). Falls back to `host:path_prefix` or `_catch-all` when name is empty.

### Cache metrics

| Metric | Description |
|---|---|
| `bouine_hot_store_bytes` | Current hot tier bytes used |
| `bouine_hot_store_max_bytes` | Configured hot tier maximum |
| `bouine_hot_store_objects` | Objects currently in hot tier |
| `bouine_sieve_evictions_total` | Evictions from hot tier (SIEVE algorithm) |
| `bouine_vary_cap_hits_total` | Vary variant storage rejected (MaxVariants = 64 exceeded) |

### Invalidation metrics

| Metric | Labels | Description |
|---|---|---|
| `bouine_purge_total` | — | Total purge operations |
| `bouine_ban_total` | — | Total ban operations |
| `bouine_ban_list_size` | — | Current active ban predicates |
| `bouine_config_reload_total` | `result` | Config reload attempts (`success` or `error`) |

### Cluster metrics

| Metric | Labels | Available in |
|---|---|---|
| `bouine_cluster_mode_info` | `mode` | All modes |
| `bouine_peer_fetch_hits_total` | — | `strong` only |
| `bouine_peer_fetch_misses_total` | — | `strong` only |
| `bouine_peer_fetch_hop_limit_hits_total` | — | `strong` only |
| `bouine_peer_fetch_duration_seconds` | — | `strong` only |
| `bouine_cluster_invalidations_http_total` | `type` | `strong`, `full` |
| `bouine_cluster_invalidations_gossip_total` | `type` | All modes |
| `bouine_cluster_broadcast_failures_total` | `type`, `reason` | `strong`, `full` |
| `bouine_cluster_replications_sent_total` | — | `full` only |
| `bouine_cluster_replications_received_total` | — | `full` only |
| `bouine_cluster_replication_bytes_total` | `direction` | `full` only |

---

## Access logs

bouine logs structured JSON to stdout. Use `--log-format json` (the default on the Docker image).

```json
{
  "method": "GET",
  "host": "example.com",
  "path": "/api/v1/products",
  "status": 200,
  "bytes_out": 1234,
  "dur_ms": 2,
  "cache_status": "HIT",
  "route": "/api/v1",
  "remote": "10.42.0.1:54321"
}
```

> **Sampling**: Only `200 OK` responses are sampled at 1:100. All other status codes (errors, redirects, unusual 2xx) are always logged.

---

## Distributed tracing (OpenTelemetry)

When `tracing.endpoint` is set, bouine exports OTLP/HTTP spans to any OpenTelemetry-compatible backend (Jaeger, Grafana Tempo, Honeycomb, etc.).

```yaml
tracing:
  endpoint: "http://otel-collector:4318"
  service_name: "bouine"
  sampling_rate: 0.1   # 10% in production; 1.0 for 100%
```

Each request produces a nested trace:

```
bouine.listener.http   (L1 — network accept + protocol detection)
  bouine.pipeline      (L2 — route matching, metrics, access log)
    bouine.cache       (L4 — RFC 9111 state machine)
      bouine.origin    (L5 — upstream fetch, miss path only)
```

Leave `endpoint` empty (the default) to disable tracing at zero overhead.

---

## Admin endpoints

| Endpoint | Method | Auth | Description |
|---|---|---|---|
| `/healthz` | GET | — | Liveness probe |
| `/readyz` | GET | — | Readiness probe; returns `503` during drain |
| `/version` | GET | — | Binary version, commit, build date |
| `/metrics` | GET | — | Prometheus metrics |
| `/v1/cluster/peers` | GET | — | Gossip member list |
| `/v1/peer/fetch` | POST | — | Internal: cluster peer-fetch RPC |
| `/v1/purge` | POST | ✓ | Exact URL purge |
| `/v1/ban` | POST | ✓ | Predicate ban |
| `/v1/refresh` | POST | ✓ | Soft-purge (mark stale) |
| `/v1/config/reload` | POST | ✓ | Hot config reload |
| `/dashboard/` | GET | session | Operator dashboard |

---

## Recommended alert rules

### Critical

```yaml
# Cluster mode differs across pods (configuration drift)
- alert: ClusterModeMismatch
  expr: count(count by (mode) (bouine_cluster_mode_info == 1)) > 1
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Cluster mode mismatch — pods running different consistency modes"
```

### Warning

```yaml
# Purge rate spike (possible invalidation storm)
- alert: HighPurgeRate
  expr: rate(bouine_purge_total[5m]) > 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Elevated purge rate on {{ $labels.instance }}"

# Stale serve ratio climbing (possible origin outage)
- alert: HighStaleServeRate
  expr: |
    rate(bouine_requests_total{cache_result="STALE"}[5m])
    /
    rate(bouine_requests_total[5m]) > 0.10
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Stale serve ratio > 10% on {{ $labels.instance }}"

# Full-mode replication stalled
- alert: FullReplicationStalled
  expr: rate(bouine_cluster_replications_sent_total[5m]) > 0
    and rate(bouine_cluster_replications_received_total[5m]) == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Full-mode replication sending but not receiving — gossip may be broken"

# Memory pressure in full mode
- alert: FullModeMemoryPressure
  expr: bouine_hot_store_bytes / bouine_hot_store_max_bytes > 0.9
    and on() bouine_cluster_mode_info{mode="full"} == 1
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Full-mode node at >90% hot store capacity"
```

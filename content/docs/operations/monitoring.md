---
title: "Monitoring"
weight: 4
description: "Prometheus metrics, access log fields, OpenTelemetry tracing, and admin API endpoints for observing bouine."
---

## Prometheus metrics

All metrics are exposed at `GET /metrics` on the admin port (default `:9000`) in Prometheus text format. No authentication is required to scrape this endpoint.

### Traffic (RED)

| Metric | Labels | Description |
|---|---|---|
| `bouine_requests_total` | `method`, `status`, `cache_result`, `route` | Total requests processed. **This is the primary RED counter.** |
| `bouine_request_duration_seconds` | `method`, `status`, `cache_result`, `route` | Request latency histogram. Includes native histogram buckets for higher-resolution percentiles. Carries Prometheus **exemplars** linking high-latency observations to a trace ID when tracing is enabled. |
| `bouine_response_bytes_total` | `method`, `route` | Total bytes written in responses. |

**`cache_result`** values: `HIT`, `MISS`, `STALE`, `REVALIDATED`, `BYPASS`.

**`route`** label: the `name` field of the matched route config entry. Falls back to `host:path_prefix` when name is empty, or `_default` for unmatched requests.

**Hit ratio** (PromQL):
```promql
sum(rate(bouine_requests_total{cache_result="HIT"}[1m]))
/
sum(rate(bouine_requests_total[1m]))
```

**Error rate** (PromQL):
```promql
sum(rate(bouine_requests_total{status=~"5.."}[1m]))
/
sum(rate(bouine_requests_total[1m]))
```

### Hot-tier cache storage

| Metric | Type | Description |
|---|---|---|
| `bouine_hot_store_bytes` | gauge | Current bytes used by the hot in-memory tier (body + per-entry overhead). |
| `bouine_hot_store_entries` | gauge | Number of objects currently stored in the hot tier. |
| `bouine_hot_store_evictions_total` | counter | Total objects evicted by SIEVE since boot. Rising rate indicates cache churn. |
| `bouine_vary_cap_hits_total` | counter | Vary-variant insertions rejected because `MaxVariants` (64) was exceeded. |

**Cache utilisation** (PromQL):
```promql
bouine_hot_store_bytes / <hot_max_bytes_from_config>
```

> **Note.** There is no `bouine_hot_store_max_bytes` metric — the configured maximum is a static config value, not a gauge. Use `bouine_hot_store_bytes` against the known `hot_max_bytes` config value for utilisation calculations.

### Cluster

| Metric | Labels | Available in |
|---|---|---|
| `bouine_cluster_mode_info` | `mode` | all |
| `bouine_peer_fetch_hits_total` | — | `strong` |
| `bouine_peer_fetch_misses_total` | — | `strong` |
| `bouine_peer_fetch_hop_limit_hits_total` | — | `strong` |
| `bouine_peer_fetch_duration_seconds` | — | `strong` |
| `bouine_cluster_invalidations_http_total` | `type` | `strong`, `full` |
| `bouine_cluster_invalidations_gossip_total` | `type` | all |
| `bouine_cluster_broadcast_failures_total` | `type`, `reason` | `strong`, `full` |
| `bouine_cluster_replications_sent_total` | — | `full` |
| `bouine_cluster_replications_received_total` | — | `full` |
| `bouine_cluster_replication_bytes_total` | `direction` | `full` |

### Cloudflare propagation

| Metric | Labels | Description |
|---|---|---|
| `bouine_cloudflare_purge_total` | `operation`, `status` | CF Cache API calls by type and outcome |
| `bouine_cloudflare_purge_duration_seconds` | `operation` | Latency of CF API calls |
| `bouine_cloudflare_purge_skipped_total` | `reason` | Invalidations not forwarded to CF |

### Go runtime

The standard `go_*` and `process_*` metrics from the Prometheus Go client are automatically included. The most operationally relevant:

| Metric | Why it matters |
|---|---|
| `go_gc_duration_seconds{quantile="1"}` | Worst-case GC stop-the-world pause. If this approaches your HIT p99, raise `GOMEMLIMIT`. See [Troubleshooting → GC pauses](/docs/operations/troubleshooting/#hit-p99-spikes-to-50100-ms-under-load). |
| `process_resident_memory_bytes` | Actual RSS. Compare with `go_gc_gomemlimit_bytes`. |
| `go_gc_gomemlimit_bytes` | Configured `GOMEMLIMIT`. Set to ~85 % of `resources.limits.memory`. |

---

## Access logs

bouine emits a structured JSON access log line to **stdout** for every request.

```json
{
  "time":         "2026-06-07T12:00:00Z",
  "level":        "INFO",
  "msg":          "access",
  "method":       "GET",
  "host":         "example.com",
  "path":         "/posts/hello/",
  "proto":        "HTTP/1.1",
  "status":       200,
  "bytes_out":    15234,
  "dur_ms":       1,
  "cache_status": "HIT",
  "route":        "/",
  "remote":       "10.42.0.1:54321"
}
```

### ⚠️ Access log sampling — use Prometheus for throughput

**`200 OK` responses are sampled at 1:100.** All other status codes (errors, redirects, unusual 2xx) are always logged.

This is intentional: at high RPS the log write would otherwise dominate the hot path. The trade-off is that **you cannot compute accurate hit ratio or request rate from logs alone.** Use `bouine_requests_total` in Prometheus for throughput and cache result distribution. Use access logs for error diagnosis and per-request debugging.

```
Rate accuracy from logs:  ❌ (1:100 sampling for 200s)
Error investigation:      ✅ (all non-200 always logged)
Slow request debugging:   ✅ (dur_ms present on sampled 200s)
```

---

## Distributed tracing (OpenTelemetry)

When `tracing.endpoint` is set, bouine exports OTLP/HTTP spans to any OpenTelemetry-compatible backend (Grafana Tempo, Jaeger, Honeycomb, etc.).

### ⚠️ Endpoint format: `host:port`, not a URL

`tracing.endpoint` takes a bare `host:port` string — **not** a full URL. The `http://` scheme is added automatically via `WithInsecure()`.

```yaml
# ✅ correct
tracing:
  endpoint: "otel-collector.monitoring.svc.cluster.local:4318"
  service_name: "bouine"
  sampling_rate: 0.1

# ❌ wrong — the http:// prefix will be treated as part of the hostname
#    and the tracer will silently produce no spans
tracing:
  endpoint: "http://otel-collector.monitoring.svc.cluster.local:4318"
```

Leave `endpoint` empty (the default) to disable tracing at zero overhead.

### Trace structure

Each request produces a nested span tree:

```
bouine.listener.http   (L1 — network accept + protocol detection)
  bouine.pipeline      (L2 — route matching, metrics, access log)
    bouine.cache       (L4 — RFC 9111 state machine)
      bouine.origin    (L5 — upstream fetch, miss/revalidate path only)
```

The `bouine.origin` span carries **W3C TraceContext headers** (`traceparent`, `tracestate`) injected into the upstream request, so the origin server can continue the trace if it also exports spans.

### Exemplars

When tracing is active, `bouine_request_duration_seconds` observations carry a Prometheus **exemplar** with `trace_id`. In Grafana, click any histogram bar and select "Query with exemplar" to jump directly from a high-latency bucket to the matching trace in Tempo.

---

## Admin API

| Endpoint | Method | Auth required | Description |
|---|---|---|---|
| `/healthz` | GET | — | Liveness probe |
| `/readyz` | GET | — | Readiness probe; `503` during drain |
| `/version` | GET | — | Binary version, commit, build date |
| `/metrics` | GET | — | Prometheus metrics |
| `/v1/cluster/peers` | GET | — | Gossip member list |
| `/v1/peer/fetch` | POST | — | Internal: cluster peer-fetch RPC |
| `/v1/purge` | POST | ✓ | Exact URL purge |
| `/v1/ban` | POST | ✓ | Predicate ban |
| `/v1/refresh` | POST | ✓ | Soft-purge (mark stale) |
| `/v1/config/reload` | POST | ✓ | Hot config reload |
| `/dashboard/` | GET | session | Operator web dashboard |

---

## Grafana dashboard

An official RED dashboard JSON is shipped in the bouine repository at `deploy/grafana/bouine-red.json`. Import it into Grafana via **Dashboards → Import → Upload JSON file**.

The dashboard covers five rows:

| Row | Contents |
|---|---|
| **Rate** | RPS, hit ratio %, error rate %, active pod count, cluster mode, peer-fetch hit ratio |
| **Errors** | 5xx rate by route, error ratio by status, live error log stream |
| **Duration** | HIT/MISS/REVALIDATED p50/p99/p999, p99 by route |
| **Cache internals** | Result mix, response throughput, peer-fetch hits/misses/latency |
| **Go runtime / GC** | GC pause vs HIT p99, RSS vs GOMEMLIMIT, goroutines, heap |

---

## Recommended alert rules

```yaml
groups:
  - name: bouine
    rules:

    # ── Traffic ───────────────────────────────────────────────────────────
    - alert: BouineHighErrorRate
      expr: |
        sum(rate(bouine_requests_total{status=~"5.."}[5m]))
        /
        sum(rate(bouine_requests_total[5m])) > 0.01
      for: 5m
      labels: { severity: critical }
      annotations:
        summary: "bouine 5xx error rate > 1%"

    - alert: BouineHighStaleRate
      expr: |
        sum(rate(bouine_requests_total{cache_result="STALE"}[5m]))
        /
        sum(rate(bouine_requests_total[5m])) > 0.10
      for: 10m
      labels: { severity: warning }
      annotations:
        summary: "Stale serve ratio > 10% — possible origin outage"

    # ── Storage ───────────────────────────────────────────────────────────
    - alert: BouineHighEvictionRate
      expr: rate(bouine_hot_store_evictions_total[5m]) > 100
      for: 10m
      labels: { severity: warning }
      annotations:
        summary: "High SIEVE eviction rate — working set may exceed hot_max_bytes"

    # ── GC / Runtime ──────────────────────────────────────────────────────
    - alert: BouineGCPauseHigh
      expr: |
        max(rate(go_gc_duration_seconds_sum[1m])
            / rate(go_gc_duration_seconds_count[1m])) > 0.01
      for: 5m
      labels: { severity: warning }
      annotations:
        summary: "GC average pause > 10 ms — raise GOMEMLIMIT (see troubleshooting)"

    # ── Cluster ───────────────────────────────────────────────────────────
    - alert: BouineClusterModeMismatch
      expr: count(count by (mode) (bouine_cluster_mode_info == 1)) > 1
      for: 2m
      labels: { severity: critical }
      annotations:
        summary: "Pods running different cluster modes — configuration drift"

    - alert: BouineFullReplicationStalled
      expr: |
        rate(bouine_cluster_replications_sent_total[5m]) > 0
        and rate(bouine_cluster_replications_received_total[5m]) == 0
      for: 5m
      labels: { severity: warning }
      annotations:
        summary: "Full-mode replication sending but not receiving"
```

---
title: "监控"
weight: 4
description: "Prometheus metrics, access log fields, OpenTelemetry tracing, and admin API endpoints for observing bouine."
---

## Prometheus metrics

All metrics are exposed at `GET /metrics` on the admin port (default `:9000`) in Prometheus text format. No authentication is required to scrape this endpoint.

### Traffic (RED)

| Metric | Labels | Description |
|---|---|---|
| `bouine_requests_total` | `status`, `cache_result`, `source`, `upstream_pool` | Total requests processed, carrying the exact status code. **This is the primary RED counter.** |
| `bouine_request_duration_seconds` | `status` (response class), `cache_result`, `upstream_pool` | Request latency histogram. The status label carries the response class (`1xx`–`5xx`), not the exact code; exact codes stay on `bouine_requests_total`. Also exposed as a **native histogram** for high-resolution percentiles — see [below](#native-histogram-cardinality). |
| `bouine_response_bytes_total` | `cache_result`, `source`, `upstream_pool` | Total bytes written in responses. |
| `bouine_fetch_shed_total` | — | Foreground origin fetches shed after waiting `fetch_wait_timeout` for a fetch-semaphore slot. Non-zero rate means miss demand exceeds `max_fetch_concurrency`. See [Streaming and live responses](/docs/configuration/streaming/). |

**`cache_result`** values: `HIT`, `MISS`, `STALE`, `REVALIDATED`, `BYPASS`.

**`source`** values: `hot` (hot in-memory tier), `warm` (warm disk-backed tier), `peer` (cluster peer via peer-fetch), `origin` (fetched from upstream, including errors and write-through proxy).

**`upstream_pool`** label: the matched route's upstream pool name (a small config-bounded set — "which upstream is slow or 5xx-ing"). Pool-less routes (static files, catch-all) and unmatched traffic land on `_default`. The dashboard rings keep per-route attribution, so per-route views lose nothing.

> **v0.5.8 changes:** the `method` label was dropped from the data-plane RED metrics (no dashboard or SLO query used it; the access log keeps the method), and the duration histogram dropped its `source` axis and the 2.5/5/10 s tail buckets — a cache's latency mass sits far below 1 s, and hung-fetch tails are already 5xx counts on `bouine_requests_total`. The top bucket is now 1 s. Together these shrink the histogram footprint ~90 %. Update any dashboard queries that filtered on `method` or `source`.

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

**Per-pool error rate** (PromQL) — the `upstream_pool` label answers which upstream is failing:
```promql
sum by (upstream_pool) (rate(bouine_requests_total{status=~"5.."}[5m]))
```

### Native histogram cardinality

Since v0.5.8, `bouine_request_duration_seconds` is registered with
native-histogram support (client_golang dual representation): classic
`_bucket`/`_sum`/`_count` series stay on the wire for layout-agnostic
consumers, and the sparse-bucket native form lets Grafana Cloud / Mimir
`histogram_quantile` work without materializing bucket series
server-side. Resolution factor 1.1, capped at 80 sparse buckets, 1 h
minimum reset window.

The native form does not reduce scrape cardinality by itself — the win
requires dropping the classic `_bucket` series server-side. Add to your
scrape config for bouine pods:

```yaml
metric_relabel_configs:
  - action: drop
    regex: bouine_request_duration_seconds_bucket
    source_labels: [__name__]
```

Keep `_sum`/`_count` (average latency) and the native histogram (all
quantiles). With the Helm chart, pass the same rule via
`serviceMonitor.metricRelabelings`. See the
[`native-histogram` runbook](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/native-histogram.md)
for cost numbers and rollback.

### Hot-tier cache storage

| Metric | Type | Description |
|---|---|---|
| `bouine_hot_store_bytes` | gauge | Current bytes used by the hot in-memory tier (body + per-entry overhead). |
| `bouine_hot_store_entries` | gauge | Number of objects currently stored in the hot tier. |
| `bouine_hot_store_max_bytes` | gauge | Configured hot-tier byte budget, set once at startup. |
| `bouine_hot_store_evictions_total` | counter | Total objects evicted by SIEVE since boot. Rising rate indicates cache churn. |
| `bouine_vary_cap_hits_total` | counter | Vary-variant insertions rejected because `MaxVariants` (64) was exceeded. |

**Cache utilisation** (PromQL):
```promql
bouine_hot_store_bytes / bouine_hot_store_max_bytes
```

> **Note.** `bouine_hot_store_max_bytes` (and `bouine_warm_store_max_bytes`) are
> gauges exported since v0.5.1 — compute fill ratios directly. On older
> versions, use the configured `hot_max_bytes` value instead.

### Streaming and load shedding

| Metric | Type | Description |
|---|---|---|
| `bouine_fetch_shed_total` | counter | Foreground fetches shed after `fetch_wait_timeout` waiting for a slot (503 + `Retry-After` served, or stale). |
| `bouine_streaming_buffer_bytes` | gauge | Total bytes held in live streaming tee buffers across concurrent miss-fetches. |
| `bouine_streaming_fallback_total` | counter | Cacheable misses that fell back to synchronous buffering because the streaming memory cap was exceeded. |
| `bouine_request_queue_depth` | gauge | Current in-flight requests being processed. A rising value indicates CPU starvation before timeouts appear. |
| `bouine_metrics_reset_total` | counter | Metrics re-initialization events. Non-zero explains histogram count discontinuities after restart. |

### Warm-tier storage

| Metric | Type | Description |
|---|---|---|
| `bouine_warm_store_bytes` | gauge | Current bytes used by the warm disk-backed tier. |
| `bouine_warm_store_entries` | gauge | Number of objects currently stored in the warm tier. |
| `bouine_warm_store_self_heals_total` | counter | Warm-tier self-heal events (segment recovery). |
| `bouine_wal_dropped_entries_total` | counter | WAL entries dropped due to pressure (async fsync batching). |
| `bouine_wal_last_sync_timestamp_seconds` | gauge | Timestamp of the last WAL fsync. |

### Security

| Metric | Type | Description |
|---|---|---|
| `bouine_http_smuggling_rejected_total` | counter | HTTP/1.1 requests rejected by the fast-path parser's smuggling detection. |

### Cluster

| Metric | Labels | Available in |
|---|---|---|
| `bouine_cluster_mode_info` | `mode` | all |
| `bouine_peer_fetch_hits_total` | — | `strong` |
| `bouine_peer_fetch_misses_total` | — | `strong` |
| `bouine_peer_fetch_hop_limit_hits_total` | — | `strong` |
| `bouine_peer_fetch_duration_seconds` | — | `strong` |
| `bouine_cluster_invalidations_http_total` | `type` | `strong` |
| `bouine_cluster_invalidations_gossip_total` | `type` | all |
| `bouine_cluster_broadcast_failures_total` | `type`, `reason` | `strong` |
| `bouine_cluster_gossip_drops_total` | — | all |

### Startup

| Metric | Type | Labels | Description |
|---|---|---|---|
| `bouine_startup_phase` | gauge | `phase` | Current startup phase (WAL replay, ring build, etc.). 1 = active, 0 = complete. |
| `bouine_startup_condition_ready` | gauge | `condition` | Readiness condition status during startup. |
| `bouine_startup_duration_seconds` | histogram | — | Total startup duration. |

### Cloudflare propagation

| Metric | Labels | Description |
|---|---|---|
| `bouine_cloudflare_purge_total` | `operation`, `status` | CF Cache API calls by type and outcome |
| `bouine_cloudflare_purge_duration_seconds` | `operation` | Latency of CF API calls |
| `bouine_cloudflare_purge_skipped_total` | `reason` | Invalidations not forwarded to CF |

### Refresh before expiry

These metrics are emitted when `refresh_before_expiry` is enabled on at
least one route. All carry a `route` label matching the route name.

| Metric | Type | Labels | Description |
|---|---|---|---|
| `bouine_refresh_total` | counter | `route`, `result` | Background refresh fetches by result (`304`, `200`, `error`, `persist_cycle`). |
| `bouine_refresh_errors_total` | counter | `route`, `error_type` | Failed background refresh fetches by error type. |
| `bouine_refresh_skips_total` | counter | `route`, `reason` | Skipped background refreshes by reason (`not_found`, `stale`, `semaphore_full`, `rate_limited`, `not_registered`, `bad_url`, `below_min_hits`, `negative`). |
| `bouine_refresh_in_flight` | gauge | `route` | Current in-flight background refresh goroutines. |
| `bouine_refresh_scheduled` | gauge | `route` | Entries currently in the refresh scheduler heap. |
| `bouine_refresh_registry_size` | gauge | `route` | Entries currently in the refresh registry. |

**Refresh rate** (PromQL):
```promql
sum(rate(bouine_refresh_total[1m])) by (route)
```

**Refresh skip ratio** (PromQL):
```promql
sum(rate(bouine_refresh_skips_total{reason="below_min_hits"}[5m]))
/
sum(rate(bouine_refresh_total[5m]))
```

A high `below_min_hits` skip ratio indicates the popularity gate
(`refresh_min_hits`) is filtering out many objects — adjust the
threshold if too many popular objects are expiring.

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

### Endpoint format

`tracing.endpoint` accepts either a bare `host:port` string or a full URL with `http://` / `https://` scheme. The scheme prefix is stripped automatically; `WithInsecure()` is used for plain HTTP.

```yaml
# canonical form (host:port)
tracing:
  endpoint: "otel-collector.monitoring.svc.cluster.local:4318"
  service_name: "bouine"
  sampling_rate: 0.1

# also accepted (scheme is stripped)
tracing:
  endpoint: "http://otel-collector.monitoring.svc.cluster.local:4318"
```

Leave `endpoint` empty (the default) to disable tracing at zero overhead.

### Trace structure

Each request produces a nested span tree:

```
bouine.pipeline      (L2 — route matching, metrics, access log; one span per request)
  bouine.origin      (L5 — upstream fetch, miss/revalidate path only)
```

The `bouine.origin` span carries **W3C TraceContext headers** (`traceparent`, `tracestate`) injected into the upstream request, so the origin server can continue the trace if it also exports spans.

### Correlating traces with slow requests

The data-plane middleware produces a single `bouine.pipeline` span per
request, and `bouine.origin` spans (miss/revalidate path only) carry the
W3C trace context forward to the origin. To jump from a slow access-log
line to its trace, correlate the request timestamp and URL in your trace
backend. Prometheus exemplars were removed in the v0.5.0 `fasthttp`
migration — the histogram no longer carries per-observation trace IDs.

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
| `/v1/stats` | GET | ✓ | Runtime stats (store entries, ring info) |
| `/v1/config` | GET | ✓ | Read-only view of running configuration |
| `/v1/debug/cachecheck?url=...` | GET | ✓ | Cache debug info for a URL |
| `/debug/pprof/*` | GET | ✓ | Go pprof profiling endpoints (when `admin.pprof_enabled`) |
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

```

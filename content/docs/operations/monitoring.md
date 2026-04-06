---
title: "Monitoring"
weight: 4
description: "Key Prometheus metrics, access log fields, OpenTelemetry tracing, and admin API endpoints for observing bouine."
---

## Key metrics

| Metric | Labels | Description |
|---|---|---|
| `bouine_requests_total` | `method`, `status`, `cache_result`, `route` | Total requests processed |
| `bouine_request_duration_seconds` | `method`, `status`, `cache_result`, `route` | Request latency histogram |
| `bouine_response_bytes_total` | `method`, `route` | Total bytes written in responses |
| `bouine_vary_cap_hits_total` | — | Vary variant storage rejected (MaxVariants = 64 exceeded) |
| `bouine_peer_fetch_hits_total` | — | Objects served from a cluster peer (L0 promotion) |
| `bouine_peer_fetch_misses_total` | — | Peer-fetch RPCs that returned a miss; fell through to origin |
| `bouine_peer_fetch_hop_limit_hits_total` | — | Peer-fetch attempts aborted because MaxHops was reached |
| `bouine_peer_fetch_duration_seconds` | — | Round-trip time histogram for successful peer-fetch RPCs |
| `bouine_cluster_mode_info` | `mode` | Always 1; the `mode` label identifies the active consistency mode (`strong`, `eventual`, `full`) |
| `bouine_cluster_invalidations_http_total` | `type` | Invalidation events sent via HTTP fan-out (`purge`, `ban`). Strong and full modes only. |
| `bouine_cluster_invalidations_gossip_total` | `type` | Invalidation events received via gossip — all modes. |
| `bouine_cluster_replications_sent_total` | — | Cached objects broadcast to peers via gossip in full mode. |
| `bouine_cluster_replications_received_total` | — | Cached objects received from peers via gossip and stored locally in full mode. |
| `bouine_cluster_replication_bytes_total` | `direction` | Approximate byte size of replicated objects (`sent` or `received`). Full mode only. |

### Label values

**`cache_result`** takes one of: `HIT`, `MISS`, `STALE`, `REVALIDATED`, `BYPASS`.

**`route`** is set from the `name` field of the matched route (e.g. `"api-v1"`). Falls back to `host:path_prefix` or `_catch-all` when name is empty.

## Access log fields

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

> **Sampling** Only `200 OK` responses are sampled at 1:100. All other status codes (errors, redirects, unusual 2xx) are always logged.

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

Leave `endpoint` empty (the default) to disable tracing at zero overhead — the no-op tracer is installed automatically.

## Admin endpoints

| Endpoint | Method | Auth | Description |
|---|---|---|---|
| `/healthz` | GET | — | Liveness probe |
| `/readyz` | GET | — | Readiness probe; returns `503` during graceful shutdown drain |
| `/version` | GET | — | Binary version, commit, build date |
| `/metrics` | GET | — | Prometheus metrics |
| `/v1/cluster/peers` | GET | — | Gossip member list |
| `/v1/peer/fetch` | POST | — | Internal: cluster peer-lookup RPC (no bearer token required; network-policy protected) |
| `/v1/purge` | POST | ✓ | Exact URL purge |
| `/v1/ban` | POST | ✓ | Predicate ban (host regex, path regex, surrogate key) |
| `/v1/refresh` | POST | ✓ | Soft-purge (mark stale; revalidates on next request) |
| `/v1/config/reload` | POST | ✓ | Hot config reload |
| `/dashboard/` | GET | session | Operator dashboard (browser) |

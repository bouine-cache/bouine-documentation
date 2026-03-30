---
title: "Monitoring"
weight: 4
description: "Key Prometheus metrics, access log fields, and admin API endpoints for observing bouine."
---

## Key metrics

| Metric | Labels | Description |
|---|---|---|
| `bouine_requests_total` | `method`, `status`, `route` | Total requests; `route` reflects the matched route name (or `_catch-all`) |
| `bouine_request_duration_seconds` | `method`, `status`, `route` | Request latency histogram |
| `bouine_response_bytes_total` | `method`, `route` | Total bytes written in responses |
| `bouine_vary_cap_hits_total` | — | Vary variant storage rejected because `MaxVariants` (64) was exceeded |

> **Note** The `route` label is populated from the `name` field of the matching config route (e.g. `"api-v1"`). If no name is set it defaults to `host:path_prefix` or `_catch-all`. Before Phase 6.9 all requests were labelled `_default`.

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

## Admin endpoints

| Endpoint | Method | Auth | Description |
|---|---|---|---|
| `/healthz` | GET | — | Liveness probe |
| `/readyz` | GET | — | Readiness probe |
| `/version` | GET | — | Binary version |
| `/metrics` | GET | — | Prometheus metrics |
| `/v1/cluster/peers` | GET | — | Gossip member list |
| `/v1/purge` | POST | ✓ | Exact URL purge |
| `/v1/ban` | POST | ✓ | Predicate ban |
| `/v1/refresh` | POST | ✓ | Soft-purge |
| `/v1/config/reload` | POST | ✓ | Hot config reload |
| `/dashboard/` | GET | session | Operator dashboard (browser) |

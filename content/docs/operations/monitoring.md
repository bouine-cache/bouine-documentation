---
title: "Monitoring"
weight: 4
description: "Key Prometheus metrics, access log fields, and admin API endpoints for observing bouine."
---

## Key metrics

| Metric | Description |
|---|---|
| `bouine_requests_total` | Total requests by method, status, cache result |
| `bouine_request_duration_seconds` | Request latency histogram |
| `bouine_cache_result_total` | HIT / MISS / STALE_HIT / REVALIDATED / BYPASS |
| `bouine_purge_total` | Purge operations |
| `bouine_ban_total` | Ban operations |
| `bouine_ban_list_size` | Active ban predicates |
| `bouine_inflight_requests` | Currently in-flight requests |

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

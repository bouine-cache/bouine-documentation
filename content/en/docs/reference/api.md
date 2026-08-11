---
title: "Admin API"
weight: 92
description: "Admin API endpoints, authentication, and response formats."
---

## Authentication

All write endpoints require a bearer token. See [Authentication](../operations/authentication/) for full details on token resolution, environment variables, and config file setup.

Pass the token in requests:

```bash
curl -X POST http://127.0.0.1:9000/v1/purge \
  -H "Authorization: Bearer your-secret-token" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/page"}'
```

## Exempt endpoints (no token required)

These are always accessible without authentication — required for K8s probes and Prometheus scraping:

| Endpoint | Method |
|----------|--------|
| `/healthz` | GET |
| `/readyz` | GET |
| `/drain` | GET |
| `/version` | GET |
| `/metrics` | GET |
| `/v1/cluster/peers` | GET |

> Internal peer RPC endpoints (`/v1/peer/purge`, `/v1/peer/ban`, `/v1/peer/fetch`, `/v1/peer/metrics`) are also auth-exempt. They are used for cluster-internal communication and not listed here.

## Endpoints

| Endpoint | Method | Auth | Body | Response |
|----------|--------|------|------|----------|
| `/healthz` | GET | — | — | `{"status":"ok"}` |
| `/readyz` | GET | — | — | `{"status":"ready"}` |
| `/readyz?detail=1` | GET | — | — | `{"status":"...","conditions":[...]}` |
| `/version` | GET | — | — | `{"version":"...","commit":"...","date":"..."}` |
| `/drain` | GET | — | — | `{"status":"drained"}` |
| `/metrics` | GET | — | — | Prometheus text format |
| `/v1/cluster/peers` | GET | — | — | Peer list JSON array |
| `/v1/purge` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"purged"}` |
| `/v1/purge/batch` | POST | ✓ | `{"urls":["..."]}` | `{"status":"purged","count":N,"failed":N}` |
| `/v1/ban` | POST | ✓ | `{"host_regex":"...","path_regex":"..."}` | `{"status":"banned","count":N}` |
| `/v1/refresh` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"refreshed"}` |
| `/v1/auth/check` | GET | ✓ | — | `{"status":"ok"}` _(only mounted when admin token is configured)_ |
| `/v1/cloudflare/status` | GET | ✓ | — | Cloudflare status JSON _(only mounted when Cloudflare is configured)_ |
| `/v1/stats` | GET | ✓ | — | Runtime stats JSON (store entries, ring info, URL ring) |
| `/v1/config` | GET | ✓ | — | Read-only JSON view of the running configuration |
| `/v1/debug/cachecheck?url=...` | GET | ✓ | — | Cache debug info for a URL (key, hit/miss, source) |
| `/debug/pprof/*` | GET | ✓ | — | Go pprof profiling endpoints _(only when `admin.pprof_enabled: true`)_ |

## OpenAPI spec

A formal OpenAPI 3.0 specification is available at
[`api/openapi.yaml`](https://github.com/bouine-cache/bouine/blob/main/api/openapi.yaml)
in the repository. Use it with `openapi-generator` to produce SDKs in
Python, TypeScript, and other languages.
---
title: "API d'administration"
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

> Internal peer RPC endpoints (`/v1/peer/purge`, `/v1/peer/ban`, `/v1/peer/fetch`, `/v1/peer/metrics`, and since v0.6.0 `/v1/peer/config/hot` and `/v1/peer/keys/find`) are also auth-exempt. They are used for cluster-internal communication and not listed here. Peer routes use strict JSON framing: unknown fields and trailing data are rejected.

## Endpoints

| Endpoint | Method | Auth | Body | Response |
|----------|--------|------|------|----------|
| `/healthz` | GET | — | — | `{"status":"ok"}` |
| `/readyz` | GET | — | — | `{"status":"ready"}` |
| `/readyz?detail=1` | GET | — | — | `{"status":"...","conditions":[...]}` |
| `/version` | GET | — | — | `{"version":"...","commit":"...","date":"..."}` |
| `/drain` | GET | — | — | `{"status":"drained"}` |
| `/metrics` | GET | — | — | Prometheus text format |
| `/v1/cluster/peers` | GET | — | — | Peer list JSON array. On a local-mode daemon, answers 503 with the reason since v0.6.0 |
| `/v1/purge` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"purged"}` |
| `/v1/purge/batch` | POST | ✓ | `{"urls":["..."]}` | `{"status":"purged","count":N,"failed":N}` |
| `/v1/ban` | POST | ✓ | `{"host_regex":"...","path_regex":"..."}` | `{"status":"banned","count":N}` |
| `/v1/refresh` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"refreshed"}` |
| `/v1/auth/check` | GET | ✓ | — | `{"status":"ok"}` _(only mounted when admin token is configured)_ |
| `/v1/cloudflare/status` | GET | ✓ | — | Cloudflare status JSON _(only mounted when Cloudflare is configured)_ |
| `/v1/stats` | GET | ✓ | — | Runtime stats JSON (store entries, ring info, URL ring) |
| `/v1/config` | GET | ✓ | — | Read-only JSON view of the running configuration |
| `/v1/config/hot` | GET | ✓ | — | List hot-config knobs with live value and source (since v0.6.0) |
| `/v1/config/hot` | POST | ✓ | — | Apply a validated hot-config point mutation (since v0.6.0); fans out to peers in strong mode |
| `/v1/config/reload` | POST | ✓ | — | Apply a config file to the running daemon (since v0.6.0, experimental, behind `experimental.config_reload`) |
| `/v1/status` | GET | ✓ | — | Node overview: node, cache, origins, cluster, insights (since v0.6.0) |
| `/v1/explain?url=...` | GET | ✓ | — | Structured cache-decision tree for one URL (since v0.6.0) |
| `/v1/keys/find?url=...` | GET | ✓ | — | Cache state of a URL via a side-effect-free store probe (since v0.6.0) |
| `/v1/keys/top` | GET | ✓ | — | Most-requested URL prefixes with per-cache-result breakdown (since v0.6.0) |
| `/v1/keys/recent` | GET | ✓ | — | Most recently active URL prefixes (since v0.6.0) |
| `/v1/debug/cachecheck?url=...` | GET | ✓ | — | Cache debug info for a URL (key, hit/miss, source) |
| `/debug/pprof/*` | GET | ✓ | — | Go pprof profiling endpoints _(only when `admin.pprof_enabled: true`)_ |

> Since v0.5.14, `/v1/purge/batch` performs a single local purge pass, one
> batched cluster fan-out for the whole batch (instead of one broadcast per
> URL), and per-URL Cloudflare propagation only for successfully purged
> entries.
>
> Since v0.6.0, the new introspection and runtime-config endpoints
> (`/v1/status`, `/v1/explain`, `/v1/keys/*`, `/v1/config/hot`,
> `/v1/config/reload`) are documented in [CLI](../cli/) with their
> matching `bouine` subcommands.

## OpenAPI spec

A formal OpenAPI 3.0 specification is available at
[`api/openapi.yaml`](https://github.com/bouine-cache/bouine/blob/main/api/openapi.yaml)
in the repository. Use it with `openapi-generator` to produce SDKs in
Python, TypeScript, and other languages.
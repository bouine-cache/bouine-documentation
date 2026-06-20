---
title: "Reference"
weight: 90
description: "CLI, headers, admin API, and authentication quick reference."
---


## CLI

```bash
bouine serve --config /etc/bouine/config.yaml
bouine purge <url>  --token <token>
bouine ban host_regex=example.com path_regex=^/api  --token <token>
bouine refresh <url>  --token <token>
bouine cluster peers
bouine version
```

`--server` defaults to `127.0.0.1:9000`. All commands default to port 9000 so `--server` is optional when running locally.

## Admin authentication

All write endpoints require a bearer token. The token is resolved in priority order:

1. `BOUINE_ADMIN_TOKEN` environment variable
2. `admin.token` in the config file
3. Auto-generated random token (logged as `WARN`)

### Environment variable

```bash
export BOUINE_ADMIN_TOKEN=your-secret-token
```

### Config file

```yaml
admin:
  token: your-secret-token
```

If neither is set, bouine auto-generates a random token at startup and logs it:

```json
{"level":"WARN","msg":"admin token not configured — using auto-generated token","token":"a3f9...","hint":"set admin.token in config or BOUINE_ADMIN_TOKEN env var to silence this warning"}
```

Retrieve the token from a config file:

```bash
make admin-token CONFIG=config.yaml
```

Pass it in requests:

```bash
curl -X POST http://127.0.0.1:9000/v1/purge \
  -H "Authorization: Bearer your-secret-token" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/page"}'
```

## Exempt endpoints (no token required)

These are always accessible without authentication — required for K8s probes and Prometheus scraping:

| Endpoint | Method |
|---|---|
| `/healthz` | GET |
| `/readyz` | GET |
| `/version` | GET |
| `/metrics` | GET |
| `/v1/cluster/peers` | GET |

## Admin API

| Endpoint | Method | Auth | Body | Response |
|---|---|---|---|---|
| `/healthz` | GET | — | - | `{"status":"ok"}` |
| `/readyz` | GET | — | - | `{"status":"ready"}` |
| `/version` | GET | — | - | version metadata |
| `/metrics` | GET | — | - | Prometheus metrics |
| `/v1/cluster/peers` | GET | — | - | peer list |
| `/v1/purge` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"purged"}` |
| `/v1/ban` | POST | ✓ | `{"host_regex":"example.com"}` | `{"status":"banned","count":N}` |
| `/v1/refresh` | POST | ✓ | `{"url":"https://example.com/a"}` | `{"status":"refreshed"}` |
| `/v1/config/reload` | POST | ✓ | - | `{"status":"reload-requested"}` |

## Response headers

| Header | Values | Description |
|---|---|---|
| `X-Cache` | `HIT`, `MISS`, `STALE`, `BYPASS`, `REVALIDATED` | How the response was served |
| `Age` | seconds | Current cached object age |

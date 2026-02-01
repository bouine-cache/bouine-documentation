---
title: "Reference"
weight: 90
description: "CLI, headers, and admin API quick reference."
---


## CLI

```bash
bouine serve --config /etc/bouine/config.yaml
bouine purge <url>
bouine ban host_regex=example.com path_regex=^/api
bouine refresh <url>
bouine cluster peers
bouine version
```

## Response headers

| Header | Values | Description |
|---|---|---|
| `X-Cache` | `HIT`, `MISS` | How the response was served |
| `Age` | seconds | Current cached object age |

## Admin API

| Endpoint | Method | Body | Response |
|---|---|---|---|
| `/healthz` | GET | - | `{"status":"ok"}` |
| `/readyz` | GET | - | `{"status":"ready"}` |
| `/version` | GET | - | version metadata |
| `/metrics` | GET | - | Prometheus metrics |
| `/v1/cluster/peers` | GET | - | peer list |
| `/v1/purge` | POST | `{"url":"https://example.com/a"}` | `{"status":"purged"}` |
| `/v1/ban` | POST | `{"host_regex":"example.com"}` | `{"status":"banned","count":N}` |
| `/v1/refresh` | POST | `{"url":"https://example.com/a"}` | `{"status":"refreshed"}` |
| `/v1/config/reload` | POST | - | `{"status":"reload-requested"}` |

---
title: "Lifecycle"
weight: 1
description: "Start, stop, hot reload, and drain bouine in production and Kubernetes."
---

## Starting bouine

```bash
bouine serve --config /etc/bouine/config.yaml --log-format json
```

Startup sequence:
1. Config loaded and validated
2. Storage tiers initialised (hot → warm)
3. Admin server starts on `listen.admin` (default `:9000`)
4. `/readyz` returns `200` once all listeners are bound
5. Cluster join with retry (every 2s for up to 60s, succeeds when `Members() > 1`)
6. Data-plane listeners start
7. Active health checks begin

## Stopping (graceful shutdown)

On `SIGTERM`, bouine executes an ordered shutdown:

1. **Mark not ready** — `/readyz` returns 503
2. **Drain data-plane** — stop accepting new connections, finish in-flight
3. **Leave cluster** — gossip Leaving update to peers
4. **Flush storage** — WAL sync, warm-tier segment close
5. **Close admin** — final metrics scrape window

Total budget: `terminationGracePeriodSeconds` (default 30s).

## Hot reload

| Component | Hot-reloadable | Notes |
|---|---|---|
| Routes | Yes | New routes take effect immediately |
| Upstream pools | Yes | Targets, health check config |
| Cache TTLs | Yes | Per-route cache settings |
| TLS certificates | Yes | Cert + key files watched |
| Listen addresses | **No** | Requires restart |
| Storage settings | **No** | Requires restart |
| Cluster settings | **No** | Requires restart |

Trigger: `kill -HUP <pid>` or `POST /v1/config/reload`.

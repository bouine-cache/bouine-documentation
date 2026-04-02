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

1. **Mark not ready** — `/readyz` returns `503`; kube-proxy removes the pod from `Endpoints`. A 1-second pause lets existing connections drain before the next step.
2. **Flush storage** — WAL sync, warm-tier segment close (budget: 10 s).
3. **Leave cluster** — gossip `Leaving` update to peers so the ring rebalances before the pod disappears (budget: 10 s).
4. **Listeners close** — data-plane stops accepting new connections.

Total budget: `terminationGracePeriodSeconds` (default 30 s). Set it to at least 30 s and add a `preStop: sleep 5` hook so kube-proxy propagates the readiness change before SIGTERM arrives.

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

Trigger reload via any of:

- `kill -HUP <pid>`
- `curl -X POST http://localhost:9000/v1/config/reload -H "Authorization: Bearer <token>"`
- The **Config** page in the operator dashboard — validates first, shows a confirm dialog, applies on confirmation

The dashboard reload uses a validate → confirm → apply flow: if the config file fails to parse, the running configuration is never touched and a 422 error is shown inline.

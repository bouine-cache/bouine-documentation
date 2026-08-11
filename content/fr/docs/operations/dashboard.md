---
title: "Tableau de bord"
weight: 5
description: "Access the built-in operator dashboard for live cache metrics, route performance, cluster health, and one-click invalidation."
---

The operator dashboard is embedded directly in the admin server — no extra process, no Node toolchain. Open it at:

```
http://<admin-addr>/dashboard/
```

Default on localhost: **[http://localhost:9000/dashboard/](http://localhost:9000/dashboard/)**

---

## Logging in

The dashboard uses a session cookie derived from the admin bearer token.

1. Navigate to `/dashboard/login`
2. Paste the admin token (same value as `admin.token` in config)
3. The session lasts 24 hours and slides on every request

> **Multi-pod requirement**
>
> All pods must share the same admin token. Each pod independently generates a random token if none is set, but session cookies are HMAC-signed with that token — a cookie issued by pod A is rejected by pod B if they have different tokens.
>
> Set the token via the `BOUINE_ADMIN_TOKEN` environment variable (recommended for Kubernetes):
> ```bash
> # Injected from Vault via chassis AppSecretSet — all pods get the same value
> ```
>
> Or via the config file:
> ```yaml
> # Required for dashboard consistency across replicas
> admin:
>   token: "your-shared-secret"
> ```
>
> On Kubernetes, set it via Helm:
> ```bash
> helm upgrade bouine deploy/helm/bouine \
>   --reuse-values \
>   --set "config.admin.token=your-shared-secret"
> ```

---

## Views

### Overview

Live cluster-wide metrics polled every 5 seconds:

- **Requests/s, Hit ratio, p99 latency, Error rate** — with trend arrows vs the prior 60s window
- **Throughput chart** — 6h time series with 1H / 6H / 24H range selector
- **Cache split donut** — HIT / MISS / STALE / BYPASS / REVALIDATED breakdown
- **Route performance table** — per-route hit%, req/min, TTL, trend sparkline
- **Hot & Warm store** — tier fill bars, entry counts, evictions/min
- **Consistent hash ring** — proportional key-space ownership per pod
- **Quick Purge** — purge a URL directly from the overview

### Performance

Latency distribution and throughput analysis:

- **p50 / p90 / p99 latency** — per route and cluster-wide, updated every 5 s
- **Stale-serving panel** — STALE and REVALIDATED counts over time
- **Throughput time series** — requests/s with cache result breakdown

### Routes

Full route performance table with all cache policy columns (Pool, TTL, SWR, SIE, stayin\_alive, jitter) plus:

- **Hit ratio and req/min bar charts** — per route, updated every 10 s
- **URL drill-down** — top URL paths (first 3 segments) sorted by request count

### Cluster

Live peer health table showing each pod's Data addr, Admin addr, Weight, Joined time, and Status (online / stale). Includes:

- **Ring stats** — virtual nodes, load factor, hop limit, peer fetch timeout
- **Circular ring SVG** — key-space distribution with per-node labels and vnode counts
- **Peer fetch stats** — cluster-wide hit/miss counts and average peer latency

### Invalidation

Purge, Ban, and Refresh forms with real-time input validation:

| Form | Validates |
|---|---|
| Purge / Refresh URL | Must start with `http://` or `https://` and include a host |
| Ban host regex | Must be a valid RE2 regex |
| Ban path regex | Must be a valid RE2 regex; at least one field required |

The **Recent invalidations** list updates immediately after each successful operation.

### Config

- **Running config viewer** — structured read-only view of the live configuration (listen, storage, cluster, routes) with type-coloured values and inline hints
- Shows config file path and process uptime

### Insights

Rule-based operational insights that flag suboptimal configurations and anomalies across six categories:

- **Cache** — low hit rate, disabled caching on high-traffic routes, no TTL, no SWR, high eviction rate, warm tier near full
- **Anomaly** — bypass floods, p99 latency spikes, revalidation storms, vary explosion
- **Upstream** — unhealthy targets, high 5xx rate, no health checks, no hedge, missing ETag or surrogate keys
- **CDN** — Cloudflare not configured, async latency, purge errors or skips
- **Cluster** — stale peers, hop limit ineffective, broadcast failures, degraded peer health
- **Config** — query params not stripped, allow-set-cookie enabled, zero jitter, TLS below 1.2, tracing sampling at zero

Each insight shows a severity badge, the affected route or component, and a recommended action. The page refreshes automatically every 30 seconds.

---

## Time-range selector

The **1H / 6H / 24H** buttons in the tabs bar apply globally. The Overview throughput chart and route charts both respect the selected range. The default is 6H.

---

## Theme

Click **☀ light** / **🌙 dark** in the bottom-right corner. The preference is stored in `localStorage` and restored on page load.

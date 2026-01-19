---
title: "Operations"
weight: 3
description: "Runbook for operating bouine: lifecycle, hot reload, invalidation, monitoring, Kubernetes scaling, and releases."
---


## Lifecycle

### Starting bouine

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

### Stopping (graceful shutdown)

On `SIGTERM`, bouine executes an ordered shutdown:

1. **Mark not ready** — `/readyz` returns 503
2. **Drain data-plane** — stop accepting new connections, finish in-flight
3. **Leave cluster** — gossip Leaving update to peers
4. **Flush storage** — WAL sync, warm-tier segment close
5. **Close admin** — final metrics scrape window

Total budget: `terminationGracePeriodSeconds` (default 30s).

### Hot reload

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

---

## Cache invalidation

### Purge (exact URL)

```bash
# CLI
bouine purge https://example.com/products/123 --server 127.0.0.1:9000

# API
curl -X POST http://127.0.0.1:9000/v1/purge \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/products/123"}'
```

In a cluster, the purge is forwarded to the key's owner node.

### Ban (predicate-based)

```bash
# CLI
bouine ban host_regex=example.com path_regex=^/api/ --server 127.0.0.1:9000

# API
curl -X POST http://127.0.0.1:9000/v1/ban \
  -H "Content-Type: application/json" \
  -d '{"host_regex":"example.com","path_regex":"^/api/"}'
```

Bans are lazy — entries are checked against active bans on each lookup. Broadcast to all peers.

### Refresh (soft-purge)

```bash
# CLI
bouine refresh https://example.com/products/123 --server 127.0.0.1:9000

# API
curl -X POST http://127.0.0.1:9000/v1/refresh \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/products/123"}'
```

Marks the entry stale — the next request triggers revalidation. If the origin returns 304, the cached body is reused.

| Scenario | Use |
|---|---|
| Content is wrong / security issue | **Purge** |
| Content updated, old is OK temporarily | **Refresh** |
| Bulk invalidation by pattern | **Ban** |

---

## Monitoring

### Key metrics

| Metric | Description |
|---|---|
| `bouine_requests_total` | Total requests by method, status, cache result |
| `bouine_request_duration_seconds` | Request latency histogram |
| `bouine_cache_result_total` | HIT / MISS / STALE_HIT / REVALIDATED / BYPASS |
| `bouine_purge_total` | Purge operations |
| `bouine_ban_total` | Ban operations |
| `bouine_ban_list_size` | Active ban predicates |
| `bouine_inflight_requests` | Currently in-flight requests |

### Access log fields

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

### Admin endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/healthz` | GET | Liveness probe |
| `/readyz` | GET | Readiness probe |
| `/version` | GET | Binary version |
| `/metrics` | GET | Prometheus metrics |
| `/v1/cluster/peers` | GET | Gossip member list |
| `/v1/purge` | POST | Exact URL purge |
| `/v1/ban` | POST | Predicate ban |
| `/v1/refresh` | POST | Soft-purge |
| `/v1/config/reload` | POST | Hot config reload |

---

## Kubernetes operations

### Scaling

```bash
kubectl scale statefulset/bouine -n <namespace> --replicas=3
```

Gossip auto-discovers peers via the headless Service DNS. New pods join the cluster within 60s.

### Rolling update

```bash
kubectl rollout restart statefulset/bouine -n <namespace>
```

StatefulSet rolls one pod at a time (reverse ordinal). Each pod must pass readiness before the next is replaced.

### Verifying cluster health

```bash
kubectl exec bouine-0 -n <namespace> -- /bouine cluster peers --server 127.0.0.1:9000
```

Should show all replicas.

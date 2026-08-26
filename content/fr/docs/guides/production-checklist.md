---
title: "Production readiness checklist"
weight: 7
description: "Checklist to review before deploying bouine to production."
---

Before deploying bouine to production, verify each item below. Items
are grouped by area. Skip items that don't apply to your deployment.

## TLS and network security

- [ ] Data-plane TLS configured (if terminating HTTPS at bouine)
- [ ] Cluster mTLS enabled (cert + key + CA bundle for peer-to-peer)
- [ ] Admin port not exposed externally (NetworkPolicy or firewall)
- [ ] Admin token set via Secret or environment variable (not auto-generated)
- [ ] `insecure_skip_verify` is not set in any upstream pool TLS config
- [ ] Hop-by-hop headers stripped (handled automatically by bouine)

## Resource sizing

- [ ] `resources.limits.memory` set and GOMEMLIMIT auto-computed (Helm chart does this)
- [ ] `hot_max_bytes` sized to fit in RAM without GC pressure (default: 75% of GOMEMLIMIT)
- [ ] Warm tier PVC sized for working set (`warmVolume.size`)
- [ ] `warm_max_bytes` set below PVC capacity to leave headroom
- [ ] `max_object_size` configured per route to reject oversized responses
- [ ] `max_response_bytes` configured to prevent memory exhaustion from large bodies

## Cluster and high availability

- [ ] `replicaCount >= 3` for quorum
- [ ] `podDisruptionBudget.enabled: true` with `minAvailable >= 2`
- [ ] Topology spread constraints set across zones
- [ ] `hop_limit` configured (default 2 is fine for most deployments)
- [ ] `terminationGracePeriodSeconds >= 40` to allow graceful drain
- [ ] `minReadySeconds >= 30` to let the ring converge before traffic

## Caching policy

- [ ] Every route has `ttl_default` set explicitly
- [ ] `stale_while_revalidate` configured for routes that can serve stale
- [ ] `stale_if_error` configured for origin-outage resilience
- [ ] `negative_ttl` set for routes that return errors (prevents error storms)
- [ ] `jitter_percent > 0` to prevent synchronized revalidation bursts
- [ ] `allow_set_cookie` is off unless you explicitly need Set-Cookie caching
- [ ] Cache key configuration reviewed (query param stripping, header includes)

## Upstream and origin

- [ ] Active health checks enabled per pool
- [ ] Passive health checks enabled (`consecutive_5xx`, `eject_for`)
- [ ] Upstream connection timeout and response header timeout configured
- [ ] `max_connections` set per pool to prevent FD exhaustion
- [ ] `listen.max_connections` set to bound total data-plane connections
- [ ] `response_header_timeout` configured to prevent slow-origin connection churn
- [ ] Hedged requests enabled for latency-sensitive routes

## Observability

- [ ] Prometheus scraping enabled (ServiceMonitor or PodMonitor)
- [ ] Grafana dashboards imported (RED, storage, cluster, ops)
- [ ] Alerting rules deployed (hit rate, error rate, peer fetch, warm tier)
- [ ] OpenTelemetry tracing endpoint configured (or disabled explicitly)
- [ ] Access log sampling rate appropriate (default 1:100 for 200s)
- [ ] `pprof_enabled` is off in production (default)

## Kubernetes deployment

- [ ] Helm chart deployed with production values (`values-production.yaml` as base)
- [ ] `NetworkPolicy.enabled: true` to isolate admin and cluster ports
- [ ] `serviceAccount.automount: false` (bouine doesn't need K8s API access)
- [ ] Probes configured: startup (30 min budget), readiness (`/readyz`), liveness (`/healthz`)
- [ ] Rolling update strategy: `maxUnavailable: 1` for sequential pod restarts
- [ ] Config changes deployed via rolling update (no live config reload)

## Operations

- [ ] Purge and ban workflows documented for on-call
- [ ] Runbook accessible (see [operations docs](../operations/))
- [ ] Backup strategy for warm tier (PVC snapshots or rebuild from origin)
- [ ] Drain procedure tested (`/drain` endpoint + preStop hook)
- [ ] Config file stored in version control
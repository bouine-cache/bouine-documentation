---
title: "Helm chart reference"
weight: 6
description: "All configurable values for the bouine Helm chart with defaults, descriptions, and production deployment tips."
---

The Helm chart deploys bouine as a StatefulSet with headless Service for gossip peer discovery. Source: [`deploy/helm/bouine/`](https://github.com/bouine-cache/bouine/tree/main/deploy/helm/bouine).

## Install

```bash
helm repo add bouine https://charts.bouine.org
helm repo update

helm install bouine bouine/bouine \
  --namespace bouine --create-namespace \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app"
```

To install from a local checkout, replace `bouine/bouine` with the chart
directory `deploy/helm/bouine`.

### Preconfigured value files

The chart ships with several value profiles for common deployment patterns:

| File | Profile | Use case |
|------|---------|----------|
| `values-dev.yaml` | Development | Minimal resources, single replica, no warm tier |
| `values-ha.yaml` | High availability | 5 replicas, PDB, topology spread, larger resources |
| `values-production.yaml` | Production | Hardened security, autoscaling, service monitors, SLO alerts |

Use them with `-f`:

```bash
helm install bouine bouine/bouine \
  -n bouine --create-namespace \
  -f values-production.yaml \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080"
```

## All values

### Image

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `bouinecache/bouine` | Container image repository (Docker Hub) |
| `image.tag` | `""` (appVersion) | Image tag; defaults to chart's `appVersion` |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `nameOverride` | `""` | Override chart name |
| `fullnameOverride` | `""` | Override fully qualified name |

### Replicas

| Key | Default | Description |
|-----|---------|-------------|
| `replicaCount` | `3` | Number of StatefulSet replicas |

### bouine config

Rendered into a ConfigMap and mounted at `/etc/bouine/config.yaml`.

| Key | Default | Description |
|-----|---------|-------------|
| `config.listen.http` | `":80"` | HTTP listener |
| `config.listen.https` | `":443"` | HTTPS listener |
| `config.listen.admin` | `":9000"` | Admin API listener |
| `config.listen.cluster` | `":8443"` | Gossip cluster port |
| `config.tls.certs` | `[]` | TLS certificate list; mount via Secret |
| `config.storage.hot_max_bytes` | `2GiB` | RAM cache size |
| `config.storage.warm_dir` | `/var/lib/bouine` | Warm-tier mmap directory |
| `config.storage.warm_max_bytes` | `20GiB` | Warm-tier size limit |
| `config.cluster.join` | `[]` | Seed addresses (auto-populated from headless Service DNS) |
| `config.cluster.hop_limit` | `2` | Max peer-fetch hops (strong mode) |
| `config.upstream_pools` | `[]` | Upstream pool definitions |
| `config.routes` | `[]` | Route definitions |

### Service

| Key | Default | Description |
|-----|---------|-------------|
| `service.type` | `ClusterIP` | Kubernetes Service type |
| `service.httpPort` | `80` | HTTP port |
| `service.httpsPort` | `443` | HTTPS port |
| `service.adminPort` | `9000` | Admin port |
| `headlessService.clusterPort` | `8443` | Gossip peer discovery port |

### Resources

| Key | Default | Description |
|-----|---------|-------------|
| `resources.requests.cpu` | `1000m` | CPU request |
| `resources.requests.memory` | `2Gi` | Memory request |
| `resources.limits.cpu` | `4` | CPU limit |
| `resources.limits.memory` | `8Gi` | Memory limit |

### Go runtime tuning

| Key | Default | Description |
|-----|---------|-------------|
| `goMemLimit` | `""` (auto) | `GOMEMLIMIT` — auto-computed as 75% of `resources.limits.memory` |
| `goGC` | `100` | `GOGC` — Go GC target percentage |

### Pod configuration

| Key | Default | Description |
|-----|---------|-------------|
| `terminationGracePeriodSeconds` | `40` | Grace period for shutdown sequencer |
| `podDisruptionBudget.enabled` | `true` | Enable PDB |
| `podDisruptionBudget.minAvailable` | `2` | Minimum available pods during disruption |
| `topologySpreadConstraints` | Zone anti-affinity | Spreads pods across availability zones |

### Security context

| Key | Default | Description |
|-----|---------|-------------|
| `podSecurityContext.runAsNonRoot` | `true` | Run as non-root |
| `podSecurityContext.runAsUser` | `65534` | UID (nobody) |
| `containerSecurityContext.readOnlyRootFilesystem` | `true` | Read-only root FS |
| `containerSecurityContext.allowPrivilegeEscalation` | `false` | No privilege escalation |

### Probes

| Key | Default | Description |
|-----|---------|-------------|
| `startupProbe.httpGet.path` | `/readyz` | Startup probe endpoint |
| `startupProbe.periodSeconds` | `10` | Startup check interval |
| `startupProbe.failureThreshold` | `180` | Max failures (30 min timeout) |
| `readinessProbe.httpGet.path` | `/readyz` | Readiness endpoint |
| `readinessProbe.periodSeconds` | `5` | Readiness check interval |
| `livenessProbe.httpGet.path` | `/healthz` | Liveness endpoint |
| `livenessProbe.periodSeconds` | `10` | Liveness check interval |

### Autoscaling

| Key | Default | Description |
|-----|---------|-------------|
| `autoscaling.enabled` | `false` | Enable HorizontalPodAutoscaler |
| `autoscaling.minReplicas` | `3` | Minimum pod count |
| `autoscaling.maxReplicas` | `6` | Maximum pod count |
| `autoscaling.targetCPUUtilizationPercentage` | `70` | CPU target for scale-up |

### Warm volume

| Key | Default | Description |
|-----|---------|-------------|
| `warmVolume.enabled` | `true` | Create a PVC for the warm tier |
| `warmVolume.size` | `50Gi` | PVC size |
| `warmVolume.storageClass` | `""` | Storage class (default = cluster default) |

### Observability

| Key | Default | Description |
|-----|---------|-------------|
| `serviceMonitor.enabled` | `false` | Create a Prometheus ServiceMonitor |
| `serviceMonitor.interval` | `15s` | Scrape interval |
| `serviceMonitor.labels` | `{}` | Extra labels for ServiceMonitor |
| `networkPolicy.enabled` | `false` | Create NetworkPolicy to isolate admin port |
| `podMonitor.enabled` | `false` | Create a Prometheus PodMonitor |
| `prometheusRule.enabled` | `false` | Create PrometheusRule with SLO alert thresholds |
| `ingress.enabled` | `false` | Create an Ingress resource |
| `updateStrategy.maxUnavailable` | `1` | Max unavailable pods during rolling update |
| `minReadySeconds` | `30` | Minimum time a pod must be ready before next update |

### Cloudflare CDN propagation

| Key | Default | Description |
|-----|---------|-------------|
| `cloudflare.apiTokenSecretName` | `""` | Name of the Secret containing `CF_API_TOKEN` |
| `cloudflare.apiTokenSecretKey` | `CF_API_TOKEN` | Key inside the Secret |

See [Cloudflare CDN propagation](/docs/operations/cloudflare/) for config-level settings (`config.cloudflare.*`).

### Extra environment variables

| Key | Default | Description |
|-----|---------|-------------|
| `extraEnv` | `[]` | Additional env vars for the bouine container |

Example — inject admin token from a Secret:

```yaml
extraEnv:
  - name: BOUINE_ADMIN_TOKEN
    valueFrom:
      secretKeyRef:
        name: bouine-admin-token
        key: token
```

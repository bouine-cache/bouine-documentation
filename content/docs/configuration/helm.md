---
title: "Helm chart reference"
weight: 6
description: "All configurable values for the bouine Helm chart with defaults, descriptions, and production deployment tips."
---

The Helm chart deploys bouine as a StatefulSet with headless Service for gossip peer discovery. Source: [`deploy/helm/bouine/`](https://github.com/thylong/bouine/tree/main/deploy/helm/bouine).

## Install

```bash
helm install bouine deploy/helm/bouine \
  --namespace bouine --create-namespace \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app"
```

## All values

### Image

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `ghcr.io/thylong/bouine` | Container image repository |
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
| `config.storage.eviction` | `sieve` | Eviction algorithm |
| `config.cluster.enabled` | `true` | Enable gossip clustering |
| `config.cluster.join` | `[]` | Seed addresses (auto-populated from headless Service DNS) |
| `config.cluster.replicas` | `2` | Write replication factor (strong mode) |
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
| `resources.requests.cpu` | `500m` | CPU request |
| `resources.requests.memory` | `512Mi` | Memory request |
| `resources.limits.cpu` | `2` | CPU limit |
| `resources.limits.memory` | `4Gi` | Memory limit |

### Go runtime tuning

| Key | Default | Description |
|-----|---------|-------------|
| `goMemLimit` | `3GiB` | `GOMEMLIMIT` — set to ~75% of `resources.limits.memory` |
| `goGC` | `100` | `GOGC` — Go GC target percentage |

### Pod configuration

| Key | Default | Description |
|-----|---------|-------------|
| `terminationGracePeriodSeconds` | `30` | Grace period for shutdown sequencer |
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
| `readinessProbe.httpGet.path` | `/readyz` | Readiness endpoint |
| `readinessProbe.periodSeconds` | `5` | Readiness check interval |
| `livenessProbe.httpGet.path` | `/healthz` | Liveness endpoint |
| `livenessProbe.periodSeconds` | `10` | Liveness check interval |

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
| `networkPolicy.enabled` | `false` | Create NetworkPolicy |

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

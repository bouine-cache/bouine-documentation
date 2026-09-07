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
| `image.pullSecrets` | `[]` | List of Kubernetes Secret names for pulling from private registries |
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
| `config.listen.max_connections` | `4096` | Cap on simultaneously open data-plane connections. Under HTTP/1.1 a parked handler holds its connection, so this bounds the in-flight pile a slow origin can cause; over-limit connections get 503 + close at accept. Production / HA values: 8192 / 16384. |
| `config.tls.certs` | `[]` | TLS certificate list; mount via Secret |
| `config.storage.hot_max_bytes` | `2GiB` | RAM cache size |
| `config.storage.warm_dir` | `/var/lib/bouine` | Warm-tier mmap directory |
| `config.storage.warm_max_bytes` | `20GiB` | Warm-tier size limit |
| `config.cluster.join` | `[]` | Seed addresses (auto-populated from headless Service DNS) |
| `config.cluster.hop_limit` | `2` | Max peer-fetch hops (strong mode) |
| `config.upstream_pools` | `[]` | Upstream pool definitions |
| `config.routes` | `[]` | Route definitions |

### Services

The chart renders **three** Services: a data-plane Service, a dedicated admin Service, and a headless Service for gossip peer discovery.

The dedicated admin Service (`ClusterIP` by default) splits the admin plane (metrics, pprof, `/drain`, admin API) off the data-plane Service — so exposing the data plane via LoadBalancer can never expose the admin surface. Prometheus ServiceMonitors scrape via the admin Service (label `bouine-cache.io/plane: management`).

| Key | Default | Description |
|-----|---------|-------------|
| `service.type` | `ClusterIP` | Kubernetes Service type |
| `service.httpPort` | `80` | HTTP port |
| `service.httpsPort` | `443` | HTTPS port |
| `service.adminPort` | `9000` | Admin port (exposed on the admin Service) |
| `service.annotations` | `{}` | Annotations on the data-plane Service |
| `service.labels` | `{}` | Extra labels on the data-plane Service |
| `service.loadBalancerSourceRanges` | `[]` | Restrict ingress CIDRs when `type: LoadBalancer` |
| `service.externalTrafficPolicy` | `""` | `Local` preserves the client source IP and avoids a second node hop (recommended for `type: LoadBalancer`) |
| `adminService.type` | `ClusterIP` | Admin-plane Service type |
| `adminService.port` | `""` (falls back to `service.adminPort`) | Admin-plane Service port |
| `adminService.annotations` | `{}` | Annotations on the admin Service |
| `adminService.labels` | `{}` | Extra labels on the admin Service |
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
| `podDisruptionBudget.annotations` | `{}` | PDB annotations |
| `topologySpreadConstraints` | Zone + hostname spread | Spreads pods across availability zones and hosts (`ScheduleAnyway`) |
| `podAnnotations` / `podLabels` | `{}` | Pod metadata |
| `statefulsetAnnotations` / `statefulsetLabels` | `{}` | StatefulSet metadata (wins over `commonLabels` on key collision) |
| `affinity` | `{}` | Affinity rules (explicit affinity takes precedence over topology spread) |
| `nodeSelector` | `{}` | Node selector |
| `tolerations` | `[]` | Tolerations |
| `priorityClassName` | `""` | Pod priority class |
| `dnsPolicy` / `dnsConfig` | `""` / `{}` | DNS policy/config overrides |
| `podManagementPolicy` | `Parallel` | Parallel pod start (correct for strong-mode gossip join); `maxUnavailable: 1` rolls one pod at a time |
| `updateStrategy.type` | `RollingUpdate` | StatefulSet update strategy |
| `updateStrategy.maxUnavailable` | `1` | Max unavailable pods during rolling update |
| `minReadySeconds` | `30` | Seconds a pod must be ready before entering Service endpoints — lets the cluster ring converge |

### Metadata and labels

| Key | Default | Description |
|-----|---------|-------------|
| `commonLabels` | `{}` | Labels applied to **every** rendered resource |
| `commonAnnotations` | `{}` | Annotations applied to every rendered resource |
| `autoscaling.annotations` | `{}` | HPA annotations |
| `serviceMonitor.annotations` | `{}` | ServiceMonitor annotations |
| `prometheusRule.annotations` / `.labels` | `{}` | PrometheusRule metadata |
| `ingress.annotations` | `{}` | Ingress annotations |
| `networkPolicy.annotations` | `{}` | NetworkPolicy annotations |
| `warmVolume.annotations` / `.labels` | `{}` | Warm PVC metadata |
| `serviceAccount.annotations` | `{}` | ServiceAccount annotations |

### Warm volume retention

| Key | Default | Description |
|-----|---------|-------------|
| `persistentVolumeClaimRetentionPolicy.enabled` | `false` | Preserve warm-tier data across StatefulSet changes when enabled |
| `persistentVolumeClaimRetentionPolicy.whenScaled` | `Retain` | PVC retention when scaled |
| `persistentVolumeClaimRetentionPolicy.whenDeleted` | `Retain` | PVC retention when deleted |

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
| `autoscaling.cpuTrigger.averageUtilization` | `70` | CPU target for scale-up |
| `autoscaling.scaleDownStabilizationSeconds` | `120` | Scale-down stabilization window |
| `autoscaling.annotations` | `{}` | HPA annotations |

> **GitOps note.** With `autoscaling.enabled: true` the StatefulSet does
> not render `spec.replicas` — the HPA owns the replica count. ArgoCD
> users should add an `ignoreDifferences` entry for `/spec/replicas` on
> the StatefulSet to stop perpetual drift.

### Warm volume

| Key | Default | Description |
|-----|---------|-------------|
| `warmVolume.enabled` | `true` | Create a PVC for the warm tier |
| `warmVolume.size` | `50Gi` | PVC size |
| `warmVolume.storageClass` | `""` | Storage class (default = cluster default) |
| `warmVolume.annotations` | `{}` | PVC annotations |
| `warmVolume.labels` | `{}` | PVC labels |

### Observability

| Key | Default | Description |
|-----|---------|-------------|
| `serviceMonitor.enabled` | `false` | Create a Prometheus ServiceMonitor (scrapes via the dedicated admin Service) |
| `serviceMonitor.interval` | `60s` | Scrape interval |
| `serviceMonitor.scrapeTimeout` | `""` | Scrape timeout (default) |
| `serviceMonitor.relabelings` | `[]` | Endpoint relabelings |
| `serviceMonitor.metricRelabelings` | `[]` | Metric relabelings — see [native histogram cardinality](../monitoring/#native-histogram-cardinality) for a recipe |
| `serviceMonitor.labels` | `{}` | Extra labels for ServiceMonitor |
| `serviceMonitor.annotations` | `{}` | ServiceMonitor annotations |
| `networkPolicy.enabled` | `false` | Create NetworkPolicy to isolate admin port |
| `prometheusRule.enabled` | `false` | Create PrometheusRule with SLO alert thresholds (thresholds overridable) |
| `ingress.enabled` | `false` | Create an Ingress resource |

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

### Service account

| Key | Default | Description |
|-----|---------|-------------|
| `serviceAccount.create` | `true` | Create a dedicated service account for the bouine pods |
| `serviceAccount.automount` | `false` | Auto-mount the service account token. Enable for IRSA / workload identity (AWS EKS, GCP workload identity). |
| `serviceAccount.annotations` | `{}` | Annotations to add to the service account (e.g. `eks.amazonaws.com/role-arn`) |
| `serviceAccount.name` | `""` | Name of an existing service account to use when `create` is false |

### Extra volumes

| Key | Default | Description |
|-----|---------|-------------|
| `extraVolumes` | `[]` | Additional volumes for the bouine pod (e.g. TLS secrets, custom CA bundles, static files) |
| `extraVolumeMounts` | `[]` | Additional volume mounts for the bouine container |

Example — mount TLS certs from a Secret:

```yaml
extraVolumes:
  - name: tls-certs
    secret:
      secretName: bouine-tls
extraVolumeMounts:
  - name: tls-certs
    mountPath: /etc/bouine/tls
    readOnly: true
```

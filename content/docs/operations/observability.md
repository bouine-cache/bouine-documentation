---
title: "Observability guide"
weight: 5
description: "End-to-end guide for wiring Prometheus, Loki, Tempo, and Grafana Alloy to collect metrics, logs, and traces from a bouine cluster."
---

This guide walks you through deploying a complete observability stack for bouine using the **Grafana LGTM** components (Loki, Grafana, Tempo, Mimir/Prometheus) and **Grafana Alloy** as the unified collection agent.

## Architecture

```
                     monitoring namespace
  ┌──────────────────────────────────────────────────┐
  │  Grafana ──queries──▶ Prometheus (metrics)        │
  │                        Loki       (logs)          │
  │                        Tempo      (traces)        │
  │                        ▲    ▲    ▲                 │
  │              Grafana Alloy (single agent)          │
  └─────────────────────│────│────│──────────────────┘
                 scrape :9000│    │OTLP :4318
         tail pod logs (k8s API)  │
                                  │
              bouine pods
```

**Grafana Alloy** replaces three separate agents:
- Prometheus scraper → scrapes `bouine:9000/metrics`
- Promtail → streams pod logs from the Kubernetes API
- OTel Collector → receives OTLP traces from bouine, forwards to Tempo

## Prerequisites

- Helm 3
- `kubectl` access to your cluster
- A dedicated `monitoring` namespace

```bash
kubectl create namespace monitoring
kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring
```

## Step 1 — Deploy the stack

Add the Grafana Helm repository:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Prometheus (with remote-write receiver)

```yaml
# values-prometheus.yaml
server:
  retention: "15d"
  extraFlags:
    - "web.enable-remote-write-receiver"   # required — Alloy pushes via remote-write
  persistentVolume:
    enabled: true
    size: 10Gi
alertmanager:
  enabled: false
kube-state-metrics:
  enabled: false
prometheus-node-exporter:
  enabled: false
```

```bash
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring -f values-prometheus.yaml
```

### Loki (single-binary, filesystem)

```yaml
# values-loki.yaml
deploymentMode: SingleBinary
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 10Gi
backend: { replicas: 0 }
read:   { replicas: 0 }
write:  { replicas: 0 }
chunksCache: { enabled: false }
gateway:     { enabled: false }
minio:       { enabled: false }
```

```bash
helm upgrade --install loki grafana/loki \
  --namespace monitoring -f values-loki.yaml
```

### Tempo (single-binary, filesystem)

```yaml
# values-tempo.yaml
tempo:
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
      wal:
        path: /var/tempo/wal
  receivers:
    otlp:
      protocols:
        grpc: { endpoint: "0.0.0.0:4317" }
        http: { endpoint: "0.0.0.0:4318" }
persistence:
  enabled: true
  size: 5Gi
```

```bash
helm upgrade --install tempo grafana/tempo \
  --namespace monitoring -f values-tempo.yaml
```

### Grafana Alloy

Create an admin secret for Grafana first, then configure Alloy:

```yaml
# values-alloy.yaml
crds:
  create: false

alloy:
  configMap:
    create: true
    content: |
      // ── Metrics: scrape bouine admin port ──────────────────────────
      discovery.kubernetes "bouine" {
        role = "pod"
        namespaces { names = ["<your-namespace>"] }   // e.g. "default"
        selectors {
          role  = "pod"
          label = "app=bouine"
        }
      }

      discovery.relabel "bouine_metrics" {
        targets = discovery.kubernetes.bouine.targets
        rule {
          // Set __address__ to <pod_ip>:9000 (admin port)
          source_labels = ["__meta_kubernetes_pod_ip"]
          target_label  = "__address__"
          replacement   = "$1:9000"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }
      }

      prometheus.scrape "bouine" {
        targets         = discovery.relabel.bouine_metrics.output
        forward_to      = [prometheus.remote_write.local.receiver]
        scrape_interval = "15s"
        metrics_path    = "/metrics"
      }

      prometheus.remote_write "local" {
        endpoint {
          url = "http://prometheus-server.monitoring.svc.cluster.local/api/v1/write"
        }
      }

      // ── Logs: stream bouine pod logs ────────────────────────────────
      loki.source.kubernetes "bouine" {
        targets    = discovery.kubernetes.bouine.targets
        forward_to = [loki.write.local.receiver]
      }

      loki.write "local" {
        endpoint {
          url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
        }
      }

      // ── Traces: OTLP receiver → Tempo ───────────────────────────────
      otelcol.receiver.otlp "bouine" {
        grpc { endpoint = "0.0.0.0:4317" }
        http { endpoint = "0.0.0.0:4318" }
        output {
          traces = [otelcol.exporter.otlp.tempo.input]
        }
      }

      otelcol.exporter.otlp "tempo" {
        client {
          endpoint = "tempo.monitoring.svc.cluster.local:4317"
          tls { insecure = true }
        }
      }

  extraPorts:
    - { name: otlp-grpc, port: 4317, targetPort: 4317, protocol: TCP }
    - { name: otlp-http, port: 4318, targetPort: 4318, protocol: TCP }

  securityContext:
    runAsUser: 0

controller:
  type: daemonset

rbac:
  create: true
  extraRules:
    - apiGroups: [""]
      resources: ["pods", "pods/log", "nodes", "services", "endpoints"]
      verbs: ["get", "list", "watch"]
```

```bash
helm upgrade --install alloy grafana/alloy \
  --namespace monitoring -f values-alloy.yaml
```

### Grafana

```bash
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -hex 16)"

helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --set "admin.existingSecret=grafana-admin" \
  --set "admin.userKey=admin-user" \
  --set "admin.passwordKey=admin-password" \
  --set "service.type=ClusterIP" \
  --set "ingress.enabled=false" \
  --set "initChownData.enabled=false" \
  --set "securityContext.runAsUser=0"
```

## Step 2 — Configure bouine

### ⚠️ Tracing endpoint format

`tracing.endpoint` takes a **bare `host:port`** string — not a full URL. The `http://` scheme is added automatically.

```yaml
# ✅ correct
tracing:
  endpoint: "alloy.monitoring.svc.cluster.local:4318"
  service_name: "bouine"
  sampling_rate: 0.1   # 10% in production; raise to 1.0 when debugging

# ❌ wrong — http:// is treated as part of the hostname; tracer silently no-ops
tracing:
  endpoint: "http://alloy.monitoring.svc.cluster.local:4318"
```

### NetworkPolicy

If you use NetworkPolicy, add these rules to your bouine policy:

```yaml
# Allow Alloy to scrape :9000/metrics
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports:
      - protocol: TCP
        port: 9000

# Allow bouine to send OTLP traces to Alloy
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports:
      - protocol: TCP
        port: 4318
```

## Step 3 — Provision Grafana datasources

Apply this ConfigMap (Grafana sidecar picks it up automatically if `sidecar.datasources.enabled=true`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        uid: prometheus
        url: http://prometheus-server.monitoring.svc.cluster.local
        isDefault: true
        jsonData:
          timeInterval: "15s"
          exemplarTraceIdDestinations:
            - name: trace_id
              datasourceUid: tempo

      - name: Loki
        type: loki
        uid: loki
        url: http://loki.monitoring.svc.cluster.local:3100
        jsonData:
          derivedFields:
            - name: trace_id
              matcherRegex: '"trace_id":"(\w+)"'
              datasourceUid: tempo
              urlDisplayLabel: "View trace"

      - name: Tempo
        type: tempo
        uid: tempo
        url: http://tempo.monitoring.svc.cluster.local:3200
        jsonData:
          nodeGraph: { enabled: true }
          lokiSearch: { datasourceUid: loki }
          tracesToLogsV2: { datasourceUid: loki }
          tracesToMetrics: { datasourceUid: prometheus }
```

## Step 4 — Import the dashboard

Import `deploy/grafana/bouine-red.json` from the bouine repository (**Dashboards → Import → Upload JSON**). This is the official RED dashboard covering rate, errors, duration, cache internals, and Go runtime diagnostics.

## Step 5 — Access Grafana

Everything runs as `ClusterIP` — no external exposure. Use `kubectl port-forward`:

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
# open http://localhost:3000
# credentials: admin / $(kubectl get secret grafana-admin -n monitoring \
#   -o jsonpath='{.data.admin-password}' | base64 -d)
```

## What to look at

| Signal | Best tool | Notes |
|---|---|---|
| Request rate, hit ratio, error rate | Prometheus / Grafana | Accurate; counters never sampled |
| HIT p99 latency | `bouine_request_duration_seconds` histogram | Click a high bucket → exemplar → Tempo trace |
| 5xx errors | Loki (`status >= 500`) | All errors always logged (no sampling) |
| Cache eviction pressure | `bouine_hot_store_evictions_total` rate | Rising rate means working set > hot_max_bytes |
| GC pauses causing latency | `go_gc_duration_seconds{quantile="1"}` | >10 ms → raise GOMEMLIMIT (see Troubleshooting) |
| Origin fetch latency | Tempo, `bouine.origin` span | Only present on MISS/REVALIDATE path |
| Cluster membership | `/v1/cluster/peers` admin API | Or `bouine cluster peers` CLI |

> **Access log throughput is sampled 1:100 for HTTP 200s.** Do not use log volume to compute request rate. Use `bouine_requests_total` in Prometheus instead.

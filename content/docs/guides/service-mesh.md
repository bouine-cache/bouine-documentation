---
title: "Service mesh compatibility"
weight: 8
description: "Run bouine alongside Istio, Linkerd, and Cilium service meshes."
---

bouine works with any service mesh that operates at L4/L7. The main
consideration is the double-TLS problem: if the mesh enforces mTLS
between sidecars, bouine must either terminate TLS itself or let the
sidecar handle it.

## General guidance

### Two deployment patterns

**Pattern 1: Mesh terminates TLS, bouine receives plaintext**

```
Client → Sidecar (mTLS) → bouine (plaintext :80) → Origin
```

- Sidecar handles mTLS, bouine listens on `http: ":80"` only
- No TLS config needed in bouine
- Simplest setup; mesh handles all transport security
- bouine sees the sidecar's IP, not the client IP (use `X-Forwarded-For`)

**Pattern 2: bouine terminates TLS, mesh in passthrough**

```
Client → Sidecar (passthrough) → bouine (TLS :443) → Origin
```

- bouine terminates TLS with its own certs
- Sidecar must be configured for TLS passthrough (not mTLS termination)
- Useful when bouine needs to inspect TLS or use SNI-based routing

### Metrics coexistence

bouine exports Prometheus metrics on `:9000/metrics` with the `bouine_`
namespace. Mesh sidecars (Envoy, Linkerd proxy) export their own metrics
with different namespaces. No conflict — but if both are scraped, ensure
your dashboards filter by namespace to avoid noise.

### Tracing context propagation

bouine propagates W3C `traceparent` headers on outbound origin requests
(via OpenTelemetry injection). If the mesh also injects trace context,
ensure both use the same propagation format (W3C TraceContext). Duplicate
spans from the mesh and bouine will be nested, not duplicated, if the
trace context is properly propagated.

## Istio

### Sidecar injection

Enable sidecar injection on the bouine namespace:

```bash
kubectl label namespace bouine istio-injection=enabled
```

Deploy bouine with the Helm chart. The sidecar is injected automatically.
bouine listens on `:80` (HTTP) and `:9000` (admin). The sidecar captures
inbound traffic on `:80` and enforces mTLS.

### Peer-to-peer mTLS

bouine's cluster protocol uses its own mTLS on `:8443`. Istio's sidecar
will also intercept this port. To avoid double-encryption, configure
Istio to bypass the cluster port:

```yaml
# Istio PeerAuthentication: permissive mode for the cluster port
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: bouine-cluster
  namespace: bouine
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: bouine
  portLevelMtls:
    8443:
      mode: DISABLE
```

This lets bouine's own mTLS handle the cluster port without Istio
interfering.

### Admin port

The admin port (`:9000`) should not be intercepted by the sidecar
(metrics scraping, health probes, dashboard). Exclude it from the
sidecar:

```yaml
# Istio Sidecar resource to exclude admin port
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: bouine-admin
  namespace: bouine
spec:
  workloadSelector:
    labels:
      app.kubernetes.io/name: bouine
  ingress:
    - port:
        number: 80
        protocol: HTTP
      captureMode: INTERCEPTION
    - port:
        number: 9000
        protocol: HTTP
      captureMode: NONE
```

## Linkerd

Linkerd is simpler than Istio — it uses Rust-based lightweight proxies
and automatic mTLS without per-port configuration.

### Setup

```bash
kubectl annotate namespace bouine linkerd.io/inject=enabled
kubectl label namespace bouine linkerd.io/inject=enabled
```

### Cluster port

Linkerd does not intercept ports that are not declared in the Service.
Since bouine's cluster port (`:8443`) is only in the headless Service
(not the ClusterIP Service), Linkerd typically leaves it alone. If
Linkerd does intercept it, add an annotation to skip the port:

```yaml
config.linkerd.io/skip-inbound-ports: "8443,9000"
```

### Admin port

Add the admin port to skip-inbound-ports so metrics and probes work:

```yaml
config.linkerd.io/skip-inbound-ports: "8443,9000"
```

## Cilium

Cilium uses eBPF at the node level (no sidecars). bouine works with
Cilium without any special configuration.

### Network policies

Cilium Network Policies (CNP) can restrict traffic to bouine:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: bouine
  namespace: bouine
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: bouine
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: bouine
      toPorts:
        - ports:
            - port: "8443"
              protocol: TCP
```

### L7 visibility

Cilium's Hubble can observe L7 traffic to/from bouine. No
configuration needed — Hubble sees the connections at the socket level.
bouine's own metrics provide cache-specific visibility (hit rate,
evictions) that Hubble cannot see.
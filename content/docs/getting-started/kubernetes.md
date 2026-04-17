---
title: "Kubernetes"
weight: 4
description: "Deploy bouine to Kubernetes with Helm, configure StatefulSet gossip, verify peer discovery, and perform rolling updates."
---


## Helm quickstart

```bash
helm install bouine deploy/helm/bouine \
  --namespace bouine --create-namespace \
  --set image.repository=thylong/bouine \
  --set image.tag=latest \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app" \
  --set config.cluster.enabled=true
```

See [Helm chart reference](/docs/configuration/helm/) for all configurable values.

## StatefulSet requirements

For multi-pod clustering, use a StatefulSet and a headless Service with `publishNotReadyAddresses: true`. See [Clustering → Headless Service](/docs/configuration/cluster-modes/#headless-service-kubernetes) for the full manifest.

## Admin token (multi-pod requirement)

All pods **must share the same `admin.token`**. See [Authentication](/docs/operations/authentication/) for setup instructions.

## Scaling

```bash
kubectl scale statefulset/bouine -n bouine --replicas=3
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

## Rolling updates

```bash
kubectl rollout restart statefulset/bouine -n bouine
kubectl rollout status statefulset/bouine -n bouine
```

bouine marks itself not-ready during shutdown and leaves the gossip cluster cleanly. See [Kubernetes operations](/docs/operations/kubernetes/) for zero-5xx rolling update procedures.

## PROXY Protocol

bouine supports PROXY Protocol v1 and v2 for deployments behind AWS NLB, GCP Internal LB, or HAProxy where the real client IP is carried in the PROXY header rather than the TCP source address.

Enable per listener in config:

```yaml
listen:
  http: ":80"
  proxy_protocol: true
```

When enabled, bouine parses the PROXY header on the raw TCP stream (before TLS) and overrides `RemoteAddr` with the upstream-reported client IP. This IP appears in access logs and is visible to upstream pools.

> **Important**: only enable `proxy_protocol` when the load balancer is configured to send PROXY headers. Enabling it without a PROXY-aware upstream will cause all connections to fail.

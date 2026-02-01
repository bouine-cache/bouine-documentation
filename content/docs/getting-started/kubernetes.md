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

## StatefulSet requirements

For multi-pod clustering, use a StatefulSet and headless Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: bouine-headless
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: bouine
  ports:
    - name: cluster-tcp
      port: 8443
      protocol: TCP
    - name: cluster-udp
      port: 8443
      protocol: UDP
```

> **Important**
>
> `publishNotReadyAddresses: true` is required. Without it, StatefulSet pod DNS records may not resolve during startup, and memberlist gossip may fail to form a cluster.

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

bouine marks itself not-ready during shutdown and leaves the gossip cluster cleanly.

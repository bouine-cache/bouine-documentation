---
title: "Cluster configuration"
weight: 3
description: "Configure bouine clustering with StatefulSet DNS, headless Services, gossip membership, peer fetch, and Kubernetes scaling."
---


Cluster mode lets multiple bouine pods share cache reads and invalidations.

## Minimal cluster config

```yaml
listen:
  cluster: ":8443"

cluster:
  enabled: true
  join:
    - "bouine-0.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-1.bouine-headless.default.svc.cluster.local:8443"
    - "bouine-2.bouine-headless.default.svc.cluster.local:8443"
  replicas: 2
  hop_limit: 2
```

## Headless Service

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

## How read sharing works

1. Node computes cache key.
2. Consistent-hash ring determines owner.
3. If owner is remote, requester peer-fetches from owner.
4. If owner misses, requester falls back to origin.

This is read sharing, not write-through replication. New cache entries are stored on the node that fetched them unless replication is enabled in a future release.

## Debugging peers

```bash
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

You should see every pod in the StatefulSet.

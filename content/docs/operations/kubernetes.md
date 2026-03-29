---
title: "Kubernetes operations"
weight: 5
description: "Scale, update, and verify cluster health for bouine running on Kubernetes."
---

## Scaling

```bash
kubectl scale statefulset/bouine -n <namespace> --replicas=3
```

Gossip auto-discovers peers via the headless Service DNS. New pods join the cluster within 60s.

## Rolling update

```bash
kubectl rollout restart statefulset/bouine -n <namespace>
```

StatefulSet rolls one pod at a time (reverse ordinal). Each pod must pass readiness before the next is replaced.

## Verifying cluster health

```bash
kubectl exec bouine-0 -n <namespace> -- /bouine cluster peers
```

Should show all replicas.

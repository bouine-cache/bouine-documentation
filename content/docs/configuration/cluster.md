---
title: "Cluster configuration"
weight: 3
description: "Configure bouine clustering with StatefulSet DNS, gossip membership, peer fetch, mTLS, and Kubernetes scaling."
---

Cluster mode lets multiple bouine pods share cache reads, broadcast invalidations, and reduce origin load.

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

## Cluster TLS (mTLS)

Peer-to-peer RPCs (`/v1/peer/fetch`, gossip) can be secured with mutual TLS:

```yaml
cluster:
  enabled: true
  join: [...]
  tls:
    ca_bundle: /etc/bouine/cluster-ca.crt
    cert_file: /etc/bouine/cluster-client.crt
    key_file:  /etc/bouine/cluster-client.key
```

Leave `tls` empty for plain HTTP (acceptable inside a private Kubernetes cluster protected by NetworkPolicy). In multi-tenant or public-cloud environments, always enable cluster TLS.

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

`publishNotReadyAddresses: true` is required so gossip DNS resolves during startup.

## How read sharing works

1. Receiving node computes the cache key (`xxhash64(scheme|host|path|query|method)`).
2. Consistent-hash ring (256 virtual nodes) determines the key's owner.
3. If the owner is a remote peer, the receiving node issues a `POST /v1/peer/fetch` RPC to the owner's admin port.
4. On a peer hit: the object is returned and promoted to the local hot tier.
5. On a peer miss or error: the request falls back to origin.

Typical peer-fetch latency: ~0.5–2 ms on the same datacenter LAN.

> **Anti-entropy** Nodes exchange ring digests on every gossip push/pull cycle. If a peer was unreachable during a rolling restart, it is automatically re-added to the ring when digests diverge.

## Invalidation propagation

| Operation | Delivery |
|---|---|
| Purge | HTTP POST to owner node + gossip broadcast |
| Ban | HTTP POST to all live peers + gossip broadcast |
| Refresh | HTTP POST to owner node |

The gossip broadcast queue provides a secondary delivery path for purge/ban events: if a peer's admin HTTP port is temporarily unreachable, the message is still delivered via the next memberlist gossip round.

## Debugging peers

```bash
kubectl exec bouine-0 -n bouine-prod -- /bouine cluster peers
# or via the admin API:
curl http://localhost:9000/v1/cluster/peers
```

Should show every pod in the StatefulSet with `addr` set to the pod IP (not `0.0.0.0`).

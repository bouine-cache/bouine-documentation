---
title: "TLS"
weight: 4
description: "Configure TLS termination with certificate management, SNI, and automatic reload."
---

bouine terminates TLS natively for HTTP/1.1 and HTTP/2. No external TLS proxy is needed.

## Minimal TLS config

```yaml
listen:
  https: ":443"
  admin: ":9000"

tls:
  certs:
    - cert_file: /etc/bouine/tls/cert.pem
      key_file: /etc/bouine/tls/key.pem
```

## Multiple certificates (SNI)

Serve different certificates per hostname:

```yaml
tls:
  certs:
    - cert_file: /etc/bouine/tls/example.pem
      key_file: /etc/bouine/tls/example-key.pem
      sni: ["example.com", "*.example.com"]
    - cert_file: /etc/bouine/tls/other.pem
      key_file: /etc/bouine/tls/other-key.pem
      sni: ["other.com"]
```

bouine selects the certificate whose `sni` list matches the client's SNI extension. If no match is found, the first certificate is used as the default.

## Full reference

| Field | Default | Description |
|-------|---------|-------------|
| `tls.certs[].cert_file` | — | Path to the PEM certificate (or chain) |
| `tls.certs[].key_file` | — | Path to the PEM private key |
| `tls.certs[].sni` | `[]` | Hostnames this cert serves; empty = default cert |
| `tls.min_version` | `"1.2"` | Minimum TLS version (`"1.2"` or `"1.3"`) |

## Certificate rotation

TLS certificates are loaded at startup. To rotate certificates, use a Kubernetes rolling restart. cert-manager renews the Secret, and the StatefulSet rollout picks up the new cert.

## Kubernetes with cert-manager

Mount certificates from a cert-manager `Certificate` resource:

```yaml
# values.yaml
config:
  listen:
    https: ":443"
  tls:
    certs:
      - cert_file: /etc/bouine/tls/tls.crt
        key_file: /etc/bouine/tls/tls.key
    reload:

# Mount the cert-manager Secret as a volume
extraVolumeMounts:
  - name: tls
    mountPath: /etc/bouine/tls
    readOnly: true
extraVolumes:
  - name: tls
    secret:
      secretName: bouine-tls
```

## Cluster TLS (mTLS)

Peer-to-peer RPCs (`/v1/peer/fetch`, gossip) use a **separate** TLS configuration from the data-plane listeners. This secures inter-node traffic independently.

```yaml
cluster:
  tls:
    ca_bundle: /etc/bouine/cluster-ca.crt
    cert_file: /etc/bouine/cluster-client.crt
    key_file:  /etc/bouine/cluster-client.key
```

Leave `tls` empty for plain HTTP (acceptable inside a private Kubernetes cluster protected by NetworkPolicy). In multi-tenant or public-cloud environments, always enable cluster TLS.

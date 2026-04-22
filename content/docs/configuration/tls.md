---
title: "TLS"
weight: 4
description: "Configure TLS termination with certificate management, ALPN negotiation, OCSP stapling, and automatic reload."
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
| `tls.alpn` | `[h2, http/1.1]` | ALPN protocols to advertise |
| `tls.min_version` | `"1.2"` | Minimum TLS version (`"1.2"` or `"1.3"`) |
| `tls.ocsp_stapling` | `""` | OCSP stapling mode (empty = disabled) |
| `tls.reload.fsnotify` | `false` | Watch cert/key files for changes |
| `tls.reload.sighup` | `false` | Reload certs on `SIGHUP` |

## Certificate reload

TLS certificates are **hot-reloadable** without process restart.

### File-based reload (recommended)

```yaml
tls:
  reload:
    fsnotify: true
```

bouine watches the certificate and key files via `fsnotify`. When a file changes (e.g., cert-manager renews a certificate), the new cert is loaded within seconds.

### Signal-based reload

```yaml
tls:
  reload:
    sighup: true
```

Send `SIGHUP` to reload certificates manually:

```bash
kill -HUP $(pgrep bouine)
```

Both methods can be enabled simultaneously.

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
      fsnotify: true

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
  enabled: true
  tls:
    ca_bundle: /etc/bouine/cluster-ca.crt
    cert_file: /etc/bouine/cluster-client.crt
    key_file:  /etc/bouine/cluster-client.key
```

Leave `tls` empty for plain HTTP (acceptable inside a private Kubernetes cluster protected by NetworkPolicy). In multi-tenant or public-cloud environments, always enable cluster TLS.

---
title: "TLS"
weight: 4
description: "Configure TLS termination with certificate management, ALPN negotiation, OCSP stapling, HTTP/3, and automatic reload."
---

bouine terminates TLS natively for HTTP/1.1, HTTP/2, and HTTP/3 (QUIC). No external TLS proxy is needed.

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
| `tls.http3.enable_0rtt` | `false` | Enable 0-RTT for HTTP/3 (QUIC early data) |

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

## HTTP/3 (QUIC)

Enable HTTP/3 alongside HTTPS:

```yaml
listen:
  https: ":443"
  http3: ":443/udp"

tls:
  certs:
    - cert_file: /etc/bouine/tls/cert.pem
      key_file: /etc/bouine/tls/key.pem
  http3:
    enable_0rtt: false
```

HTTP/3 uses the same certificate as HTTPS. The `http3` listener must be on the same port number as `https` but uses UDP.

> **0-RTT**: Enabling `enable_0rtt` allows clients to send data before the TLS handshake completes. This reduces latency for repeat visitors but is vulnerable to replay attacks. Only enable for idempotent GET requests.

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

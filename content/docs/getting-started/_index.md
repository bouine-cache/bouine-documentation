---
title: "Getting Started"
weight: 1
bookCollapseSection: false
---

# Getting started

## Installation

### Binary

Download the latest release from [GitHub Releases](https://github.com/thylong/bouine/releases):

```bash
# Linux amd64
curl -fSL -o bouine https://github.com/thylong/bouine/releases/latest/download/bouine-linux-amd64
chmod +x bouine
./bouine version
```

### Docker

```bash
docker pull thylong/bouine:latest
docker run --rm -p 8080:80 -p 9000:9000 thylong/bouine:latest
```

### From source

```bash
git clone https://github.com/thylong/bouine.git
cd bouine
make build    # -> ./bin/bouine
```

Requires Go 1.26+.

## Your first config

Create `config.yaml`:

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 256Mo
  eviction: sieve

upstream_pools:
  - name: backend
    targets: ["localhost:3000"]

routes:
  - match: { path_prefix: / }
    pool: backend
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

Run:

```bash
bouine serve --config config.yaml
```

Test:

```bash
# First request — MISS
curl -sI http://localhost:8080/ | grep X-Cache
# X-Cache: MISS

# Second request — HIT
curl -sI http://localhost:8080/ | grep X-Cache
# X-Cache: HIT

# Admin health
curl -s http://localhost:9000/healthz
# {"status":"ok"}
```

## Kubernetes quickstart

```bash
docker buildx build --platform linux/amd64 -t bouine:dev --load .

helm install bouine deploy/helm/bouine \
  --namespace bouine --create-namespace \
  --set image.repository=bouine \
  --set image.tag=dev \
  --set image.pullPolicy=Never \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app" \
  --set config.cluster.enabled=true
```

The Helm chart deploys a 3-replica StatefulSet with gossip clustering, a headless Service for peer discovery, and a PodDisruptionBudget.

## What's next

- [Configuration reference]({{< relref "/docs/configuration" >}}) — all config options
- [Operations runbook]({{< relref "/docs/operations" >}}) — start, stop, purge, ban
- [Architecture]({{< relref "/docs/architecture" >}}) — how bouine works inside

---
title: "bouine"
description: "Documentation for bouine, a Kubernetes-native HTTP reverse-proxy cache with RFC 9111 semantics and gossip clustering."
---

# bouine

<p align="center">
  <img src="/logo.png" alt="bouine anglerfish" width="180">
</p>

**bouine** is a Kubernetes-native HTTP reverse-proxy cache for teams that want Varnish/NGINX-style caching without running an external cache service.

It is built for:

- **End users and operators** who need a reliable, observable cache in front of APIs, static sites, or SSR applications.
- **Platform teams** who need horizontal scaling, safe invalidation, and Kubernetes-first deployment patterns.
- **Contributors** who want a small, layered Go codebase with clear performance and correctness gates.

> **Current status**
>
> The implementation has completed phases 0–7 and has been validated on k3s with a 3-node gossip cluster. The project is release-candidate quality, but production users should still treat it as young software and deploy progressively.

## Why bouine?

| Need | bouine provides |
|---|---|
| Cache HTTP responses correctly | RFC 9111 state machine, `Vary`, conditional revalidation, `stale-while-revalidate`, `stale-if-error` |
| Scale in Kubernetes | StatefulSet-friendly gossip membership and consistent hashing |
| Avoid Redis/Memcached | Embedded hot tier in RAM and optional mmap warm tier |
| Operate safely | Prometheus metrics, JSON access logs, health/readiness, admin API |
| Invalidate precisely | Purge by URL, predicate bans, soft-purge refresh |
| Keep origins safe | Request collapsing, health checks, hedged origin requests |

## Quick start

```bash
docker run --rm -p 8080:80 -p 9000:9000 thylong/bouine:latest
curl -s http://127.0.0.1:9000/healthz
```

Or install from source:

```bash
git clone https://github.com/thylong/bouine.git
cd bouine
make build
./bin/bouine version
```

## Documentation map

- [Getting started](docs/getting-started/) — install bouine and cache your first response.
- [Configuration](docs/configuration/) — learn the YAML schema and cache policy knobs.
- [Operations](docs/operations/) — run, monitor, reload, purge, ban, and troubleshoot bouine.
- [Architecture](docs/architecture/) — understand the cache engine, storage, clustering, and performance model.
- [Migration](docs/migration/) — map NGINX `proxy_cache` concepts to bouine.
- [Contributing](docs/contributing/) — setup, workflow, code standards, and security.

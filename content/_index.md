---
title: "bouine"
type: docs
---

<p align="center">
  <img src="/logo.png" alt="bouine" width="160">
</p>

# bouine

A horizontally-scalable, observability-first HTTP reverse-proxy cache written in Go.

bouine targets the same problem space as Varnish and NGINX `proxy_cache` — RFC 9111 caching, fast purge, predicate-based bans — but is designed from day one for **Kubernetes**, **multi-instance clustering**, and **first-class observability**.

## Key features

- **HTTP/1.1, HTTP/2, HTTP/3** on the data plane
- **Embedded storage**: sharded in-RAM hot tier + mmap warm tier, no external KV
- **Gossip clustering**: consistent-hash ring, peer fetch, cache sharing across pods
- **RFC 9111 compliance**: 84.7% on [http-tests/cache-tests](https://github.com/http-tests/cache-tests)
- **Zero-alloc hit path**: benchmark-gated CI, <5 µs per cache hit
- **Negative caching, jittered TTLs, soft-purge, prefetching**
- **Go SDK** (`pkg/bouineapi`) for programmatic admin access
- **Prometheus metrics, OpenTelemetry traces, structured slog logs, pprof**
- **Helm chart** with StatefulSet, gossip, PDB, NetworkPolicy, ServiceMonitor

## Quick links

- [Getting started]({{< relref "/docs/getting-started" >}})
- [Configuration reference]({{< relref "/docs/configuration" >}})
- [Operations runbook]({{< relref "/docs/operations" >}})
- [Architecture]({{< relref "/docs/architecture" >}})
- [Contributing]({{< relref "/docs/contributing" >}})
- [GitHub](https://github.com/thylong/bouine) · [Docker Hub](https://hub.docker.com/r/thylong/bouine)

---
title: "bouine"
description: "Documentation for bouine, a Kubernetes-native HTTP reverse-proxy cache with RFC 9111 semantics and gossip clustering."
---

# bouine

<p align="center">
  <img src="/logo.png" alt="bouine anglerfish" width="180">
</p>

**bouine** is a Kubernetes-native HTTP reverse-proxy cache for teams that want Varnish/NGINX-style caching without running an external cache service.

<div class="row g-4 my-4">
  <div class="col-md-4">
    <div class="card h-100 border-0 shadow-sm">
      <div class="card-body">
        <h5 class="card-title">End users &amp; operators</h5>
        <p class="card-text">A reliable, observable cache in front of APIs, static sites, or SSR applications — with Prometheus metrics, structured logs, and a purge API.</p>
      </div>
    </div>
  </div>
  <div class="col-md-4">
    <div class="card h-100 border-0 shadow-sm">
      <div class="card-body">
        <h5 class="card-title">Platform teams</h5>
        <p class="card-text">Horizontal scaling via gossip clustering and consistent hashing, safe invalidation propagation, and a Helm chart for Kubernetes-first deployment.</p>
      </div>
    </div>
  </div>
  <div class="col-md-4">
    <div class="card h-100 border-0 shadow-sm">
      <div class="card-body">
        <h5 class="card-title">Contributors</h5>
        <p class="card-text">A small, layered Go codebase with strict layer boundaries, benchmark-gated CI, RFC 9111 conformance tests, and clear per-package ownership.</p>
      </div>
    </div>
  </div>
</div>

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

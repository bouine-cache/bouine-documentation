---
title: "Early benchmarks"
description: "First look at bouine's cache performance: hit-path latency, throughput, and cache-hit ratio compared to traditional reverse-proxy caches."
date: 2026-08-26
draft: true
categories:
  - Performance
tags:
  - benchmarks
  - cache
  - performance
summary: "First look at bouine's cache performance: hit-path latency, throughput, and cache-hit ratio compared to traditional reverse-proxy caches."
---

## Why benchmark now?

Bouine is still pre-1.0, but the core caching pipeline — RFC 9111 compliant HTTP
cache, zero-allocation hit path, and gossip-based cluster awareness — is stable
enough to put real numbers on. This post shares our first benchmark results and
explains what they mean for production deployments.

## Test setup

| Component | Details |
|---|---|
| Hardware | Single node, AMD EPYC 7763, 64 vCPU, 256 GB RAM |
| OS | Linux 6.6 (kernel-tuned, `net.core.somaxconn=65535`) |
| bouine | v0.5.0, default config, 4 GB disk cache, 1 GB RAM cache |
| Origin | nginx serving 10 000 unique 64 KB objects (200 OK, `Cache-Control: max-age=3600`) |
| Load generator | `wrk2` with constant-rate scheduling, 10 minutes per run |

## Hit-path latency

The most critical metric for any HTTP cache is the latency of a cache **hit**.
Bouine's hit path is designed to be zero-allocation after warmup.

| Percentile | bouine (p50) | nginx proxy_cache | Varnish |
|---|---|---|---|
| p50 | **0.18 ms** | 0.42 ms | 0.21 ms |
| p99 | **0.61 ms** | 1.83 ms | 0.74 ms |
| p99.9 | **1.24 ms** | 4.12 ms | 1.58 ms |

Bouine's zero-alloc hit path shows its advantage most clearly at the tail: p99.9
is roughly 3x lower than nginx proxy_cache and 1.3x lower than Varnish.

## Throughput

At 64 concurrent connections with 100% cache-hit ratio:

| Cache | Requests/sec | CPU utilisation |
|---|---|---|
| bouine | **486 000 rps** | 38% |
| Varnish | 412 000 rps | 44% |
| nginx proxy_cache | 178 000 rps | 71% |

Bouine sustains higher throughput at lower CPU utilisation, thanks to the
zero-allocation design and Go's efficient goroutine scheduling.

## Cache-hit ratio under cluster load

With a 3-node bouine cluster (gossip enabled) and 50 000 unique objects, we
measured the steady-state cache-hit ratio as the working set rotates:

| Working-set rotation | Hit ratio (bouine) | Hit ratio (single-node) |
|---|---|---|
| 0% (static) | 100% | 100% |
| 10% per minute | **97.8%** | 91.2% |
| 50% per minute | **89.3%** | 72.1% |

The gossip-based peer-fetch protocol keeps the cluster-wide hit ratio high even
under significant working-set churn. A single-node cache degrades much faster
because every rotation is a cold miss.

## What's next

These are early numbers on a single-node setup with a controlled workload. We
are working on:

- Multi-node benchmarks with realistic traffic patterns
- Disk-cache performance under SSD and NVMe
- Comparison against cloud CDN edge caching
- Impact of `no-store` and `no-cache` directive frequency

Stay tuned for a follow-up post with cluster-scale results.
---
title: "Codebase guide"
weight: 2
description: "Contributor-oriented map of bouine packages, layers, good first tasks, and rules for safely changing cache behavior."
---


## Package map

| Package | Layer | Purpose |
|---|---:|---|
| `internal/server` | L1 | HTTP/1.1 (`fasthttp`), TLS, route matching |
| `internal/storage` | L2 | Hot store, warm tier, WAL, SIEVE |
| `internal/cache` | L3 | RFC 9111 state machine and handler |
| `internal/origin` | L4 | Upstream pools, health checks, hedged transport |
| `internal/cluster` | L5 | memberlist gossip, hash ring, peer fetch |
| `internal/admin` | L6 | Admin HTTP API |
| `internal/observability` | L7 | Metrics, logs, access log |

| `pkg/api` | public | Wire types shared by SDK and admin |
| `pkg/bouineapi` | public | Go SDK |

## Good first tasks

- Add an admin API test.
- Add a cache engine table case.
- Improve a runbook page.
- Add a benchmark for a hot path before changing it.

## Before changing cache behavior

1. Add a unit test in `internal/cache`.
2. Run `make conformance`.
3. Run `make bench` if the change touches hit-path code.
4. Update docs if operator-visible behavior changes.

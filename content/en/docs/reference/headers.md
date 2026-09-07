---
title: "Response headers"
weight: 93
description: "HTTP response headers added by bouine."
---

## X-Cache

Indicates how the response was served.

| Value | Description |
|-------|-------------|
| `HIT` | Served from cache (fresh) |
| `MISS` | Fetched from origin and cached |
| `STALE` | Served from cache (stale, within stale-while-revalidate or stale-if-error window) |
| `BYPASS` | Cache bypassed (no-store, no-cache, cache disabled for route, or SSE request) |
| `REVALIDATED` | Conditional request to origin returned 304, served from cache with updated freshness |

```bash
curl -sI http://localhost:8080/get | grep x-cache
# X-Cache: HIT
```

## Age

The age of the cached object in seconds, calculated as the time since the
`Date` header of the original response plus any time spent in upstream
forward proxies. Updated on every cache hit.

```bash
curl -sI http://localhost:8080/get | grep age
# Age: 42
```

## X-Cache-Source

Indicates which storage tier served the response.

| Value | Description |
|-------|-------------|
| `hot` | Served from the in-RAM hot tier (L0) |
| `warm` | Served from the mmap-backed warm tier (L1) |
| `peer` | Served from a cluster peer via peer fetch |
| `origin` | Fetched from the upstream origin |
| _(empty)_ | Not served from any storage tier (BYPASS or only-if-cached 504) |

## X-Bouine-Route

The route label that matched the request. Used by the dashboard for
per-route attribution and by the access log. It is **not** a Prometheus
label anymore: since v0.5.8 the data-plane RED metrics attribute by
`upstream_pool` (a small config-bounded set) instead of per-route names;
see [Monitoring](/docs/operations/monitoring/#traffic-red).

## X-Bouine-Pool

The upstream pool of the serving route. Set by the router as a
process-local value and consumed by the metrics middleware as the
`upstream_pool` Prometheus label; the inbound header form is forwarded
verbatim. Pool-less routes (static, catch-all) report `_default`.

## Warning: 110

Set to `110 - "Response is stale"` on stale responses served within the
`stale-while-revalidate` or `stale-if-error` window, per RFC 9111
section 5.5.
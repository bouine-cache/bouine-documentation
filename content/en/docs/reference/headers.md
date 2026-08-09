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
| `BYPASS` | Cache bypassed (no-store, no-cache, or cache disabled for route) |
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
---
title: "静态文件服务"
weight: 3
description: "Serve files directly from a local directory without a separate origin server. Path traversal defense, MIME types, ETags, range requests, and optional cache integration."
---

## Overview

A route can serve files from a local directory instead of proxying to an
upstream pool. This eliminates the need for a separate origin server (nginx,
Caddy) when the content is already on the same machine as bouine — useful
for single-node CDN edges, sidecar deployments, and static asset routes.

A route must specify **exactly one** of `pool` or `static.root`. Specifying
both is a validation error.

## Minimal example

```yaml
listen:
  http: ":8080"
  admin: ":9000"

routes:
  - name: assets
    match: { path_prefix: /assets/ }
    static:
      root: /var/www/assets
    request:
      strip_prefix: /assets/
    response:
      header_set:
        X-Content-Type-Options: nosniff
```

No `upstream_pools` section is needed — bouine reads files from disk
directly. The OS page cache provides hot caching in RAM at no extra cost.

## Field reference

### `routes[].static`

| Field | Default | Description |
|---|---|---|
| `root` | — | Absolute path to the directory from which files are served. Symlinks in `root` are resolved once at startup. |
| `index` | `[]` | Files to try (in order) when the request path maps to a directory, e.g. `[index.html]`. If none match, bouine returns 404. Entries must not contain `/`. |
| `max_file_size` | `10MiB` | Per-file size cap. Files larger than this are rejected with 413. |

### Reused fields

The following existing route fields also apply to static routes:

- `request.strip_prefix` — strip a path prefix before mapping to the filesystem (same mechanism as proxied routes).
- `request.header_set` / `request.header_remove` — modify request headers.
- `response.header_set` / `response.header_remove` — set response headers (e.g. `X-Content-Type-Options: nosniff`, CSP).
- `cache.*` — all cache policy fields apply when cache is enabled (see below).
- `match.host` / `match.path_prefix` / `match.methods` — route matching works identically.

## Cache integration

Cache is **off by default** for static routes. The OS page cache already
keeps frequently-accessed files in RAM. Adding bouine's hot tier on top
doubles memory usage for zero latency benefit on a single node.

Enable cache explicitly when you need:

- **Cluster invalidation** — peers without local files can serve cached copies.
- **TTL-based eviction** — automatic expiry and revalidation.
- **Stale serving** — `stale_while_revalidate` / `stale_if_error` for static files.

```yaml
routes:
  - name: assets
    match: { path_prefix: /assets/ }
    static:
      root: /var/www/assets
    request:
      strip_prefix: /assets/
    cache:
      enabled: true
      ttl_default: 3600s
```

When cache is enabled, the static handler is wrapped in the cache handler
as its "upstream." On a cache miss, bouine reads from disk and stores the
response. On a hit, bouine serves from cache without touching the filesystem.
All cache features (TTL, SWR, SIE, eviction) apply
identically to proxied responses.

## Security

- **Path traversal**: prevented by `path.Clean` + `filepath.Rel` containment
  check. The root directory is symlink-evaluated once at startup.
- **No directory listing**: directories without a matching index file return
  404.
- **File size cap**: `max_file_size` (default 10 MiB) prevents serving
  arbitrarily large files.
- **Methods**: only `GET` and `HEAD` are accepted. All other methods return
  `405 Method Not Allowed`. This is enforced in the handler, not via route
  config — operators cannot accidentally allow `PUT` or `DELETE`.
- **MIME types**: a bundled map ensures consistent `Content-Type` across all
  nodes. Unknown extensions fall back to `application/octet-stream`.
- **Symlinks after startup**: if an operator creates a symlink inside the
  root after bouine starts, and that symlink escapes root, bouine may serve
  a file outside root. The root directory should be controlled by the
  operator. Per-request symlink evaluation is not performed for performance
  reasons.

## HTTP features

### Conditional requests

Static routes support `If-None-Match` (ETag) and `If-Modified-Since`
conditional requests. When the condition is met, bouine returns `304 Not
Modified` with an empty body — no file read needed.

ETags are strong (xxhash64 of file content), cached by path + mtime so
unchanged files are only hashed once. The first request for a file incurs
one full read for the hash; subsequent requests for unchanged files reuse
the cached ETag.

### Range requests

Single range → `206 Partial Content` with `Content-Range`. Multipart range
→ collapsed to the first range as `206` (per RFC 9110 §14.3.2, a server
MAY collapse multipart to single). Unsatisfiable range (e.g.
`bytes=999999-` on a 500-byte file) → `416 Range Not Satisfiable`.

### HEAD requests

`HEAD` returns the same headers as `GET` (Content-Length, Content-Type,
ETag, Last-Modified) without a body.

## Metrics

| Metric | Labels | Description |
|---|---|---|
| `bouine_staticfile_requests_total` | `route`, `result` | Total requests to static file routes. `result` is one of: `served`, `not_found`, `too_large`, `traversal_blocked`, `method_not_allowed`. |
| `bouine_staticfile_bytes_total` | `route` | Total bytes served from static file routes. |

Cardinality is bounded by the number of routes × 5 result values.

## Mixed static and proxied routes

Static and proxied routes can coexist in the same config. Routes are matched
in declaration order; the first match wins.

```yaml
upstream_pools:
  - name: api
    targets: ["api.default.svc:8080"]

routes:
  - name: assets
    match: { path_prefix: /assets/ }
    static:
      root: /var/www/assets
    request:
      strip_prefix: /assets/

  - name: api
    match: { path_prefix: /api/ }
    pool: api
    cache:
      ttl_default: 30s

  - name: fallback
    match: {}
    static:
      root: /var/www/html
      index: [index.html]
```

---
title: "实验性功能"
weight: 7
description: "Opt-in experimental features that may become stable in future releases."
---

Experimental features are opt-in capabilities that bypass some of bouine's standard processing paths for improved performance. They are gated behind the `experimental` config section and default to off.

> **Warning:** Experimental features may change or be removed between releases. Test thoroughly before enabling in production.

## Configuration

All experimental fields live under the top-level `experimental` key:

```yaml
experimental:
  h1_fast_path: true
```

## Field reference

| Field | Default | Description |
|---|---|---|
| `h1_fast_path` | `false` | Enable the custom HTTP/1.1 parser for zero-allocation cache hits. See below. |

## H1 fast path

When `h1_fast_path` is enabled, bouine uses a custom HTTP/1.1 request parser (`internal/server/h1parser`) that bypasses `net/http` on cache hits. This eliminates `*http.Request` allocation, `http.ResponseWriter` wrapping, header-map operations, and tracing/metrics middleware for cacheable GET/HEAD requests.

### What it does

1. **Parses HTTP/1.1 requests** from the raw `net.Conn` into a stack-allocated `RawRequest` struct using zero-copy `unsafe.String` conversion (113 ns/op, 0 allocations).
2. **Serves cache hits directly** by looking up the key in the hot tier, computing freshness, and writing the response via `net.Buffers.WriteTo` (single `writev` syscall) — no `*http.Request` or `http.ResponseWriter` constructed.
3. **Falls through to `net/http`** for misses, non-GET/HEAD methods, conditional requests, HTTP/1.0, and HTTP/2.

### What stays on the standard path

The following request types always go through `net/http` regardless of the fast path setting:

- **HTTP/2** (h2 over TLS via ALPN, or h2c upgrade preface)
- **HTTP/1.0** requests (different keep-alive semantics)
- **Non-GET/HEAD methods** (POST, PUT, DELETE, etc.)
- **Conditional requests** (`If-None-Match`, `If-Modified-Since`, `If-Match`, `If-Unmodified-Since`, `If-Range`, `Range`)
- **Requests with `Cache-Control: no-cache` or `no-store`**
- **Requests with `Pragma: no-cache`**
- **Headers exceeding 16 KiB** (fall through to `net/http`)

### Fall-through behavior

When the fast path cannot serve a request (cache miss, non-cacheable method, etc.), it constructs an `*http.Request` from the parsed data and delegates to the standard `net/http` handler chain. The connection is closed after the response (`Connection: close`) — keep-alive is not maintained on fall-through.

### Performance impact

| Metric | Standard path | Fast path |
|---|---|---|
| Allocations per hit | 8 (2032 B) | 0 (0 B) |
| CPU per hit | ~780 ns | ~475 ns |
| H1 parsing | ~200 ns (net/http) | ~113 ns (h1parser) |

### Enabling in production

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 2GiB

upstream_pools:
  - name: app
    targets: ["app.default.svc:8080"]

routes:
  - match: {}
    pool: app

experimental:
  h1_fast_path: true
```

### Verifying with conformance tests

Run the cache-tests conformance suite with the fast path enabled to verify no regressions:

```bash
make conformance-fastpath
```

This runs the standard `http-tests/cache-tests` harness with `experimental.h1_fast_path: true` and reports the pass rate. The fast path should match the baseline conformance score (no regressions).

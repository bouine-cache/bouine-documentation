---
title: "Experimental features"
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
  h1_reactor: true   # Linux only; requires h1_fast_path
```

## Field reference

| Field | Default | Description |
|---|---|---|
| `h1_fast_path` | `false` | Enable the custom HTTP/1.1 parser for zero-allocation cache hits. See below. |
| `h1_reactor` | `false` | Enable the single-goroutine epoll event loop that batch-serves cache hits (Linux only; requires `h1_fast_path`). See [H1 reactor](#h1-reactor). |

## H1 fast path

When `h1_fast_path` is enabled, bouine uses a custom HTTP/1.1 request parser (`internal/server/h1parser`) that bypasses `fasthttp` on cache hits. This eliminates `*http.Request` allocation, `http.ResponseWriter` wrapping, header-map operations, and tracing/metrics middleware for cacheable GET/HEAD requests.

> **v0.5.0 context:** The entire data plane was migrated to `fasthttp` in
> v0.5.0. The `h1_fast_path` goes one step further by bypassing
> `fasthttp` entirely on cache hits, using a stack-allocated parser that
> avoids all allocations on the hot path.

### What it does

1. **Parses HTTP/1.1 requests** from the raw `net.Conn` into a stack-allocated `RawRequest` struct using zero-copy `unsafe.String` conversion (113 ns/op, 0 allocations).
2. **Serves cache hits directly** by looking up the key in the hot tier, computing freshness, and writing the response via `net.Buffers.WriteTo` (single `writev` syscall) — no `*http.Request` or `http.ResponseWriter` constructed.
3. **Falls through to `fasthttp`** for misses, non-GET/HEAD methods, conditional requests, and HTTP/1.0.

### What stays on the standard path

The following request types always go through the standard `fasthttp` handler chain regardless of the fast path setting:

- ~~**HTTP/2** (h2 over TLS via ALPN, or h2c upgrade preface)~~ — HTTP/2 was dropped in v0.5.0 when the data plane migrated to `fasthttp` (HTTP/1.1 only). Reintroduction is in progress as a `fasthttp`-native implementation.
- **HTTP/1.0** requests (different keep-alive semantics)
- **Non-GET/HEAD methods** (POST, PUT, DELETE, etc.)
- **Conditional requests** (`If-None-Match`, `If-Modified-Since`, `If-Match`, `If-Unmodified-Since`, `If-Range`, `Range`)
- **Requests with `Cache-Control: no-cache` or `no-store`**
- **Requests with `Pragma: no-cache`**
- **Headers exceeding 16 KiB** (fall through to the standard handler)
- **Requests announcing `Accept: text/event-stream`** — SSE is always served as a live unbuffered stream, see [Streaming and live responses](../streaming/)

### Fall-through behavior

When the fast path cannot serve a request (cache miss, non-cacheable method, etc.), it hands off to the standard `fasthttp` handler chain with the bytes already parsed replayed — the request is re-parsed from a buffered prefix plus the live socket, so request bodies spanning multiple TCP reads, pipelined bytes after a hit, and headers larger than the 16 KiB parser buffer are all served correctly.

The H1 parser includes HTTP request smuggling detection. Ambiguous framing (Content-Length + Transfer-Encoding, duplicate Content-Length) is rejected with `400` and connection close per RFC 9110 §6.6.2, and counted in the `bouine_http_smuggling_rejected_total` Prometheus metric.

### Performance impact

| Metric | Standard path | Fast path |
|---|---|---|
| Allocations per hit | 8 (2032 B) | 0 (0 B) |
| Full hit (`FastPath_Hit` gate) | ~312 ns | ~129 ns |
| H1 parsing (`H1Parse_Get` gate) | ~200 ns (fasthttp) | ~113 ns (h1parser) |

Keep-alive is preserved on fall-through, so mixed hit/miss workloads do not
pay connection churn. Fast-path hits within the same wall-clock second
reuse a fully serialized response head stored on the object, skipping
per-hit header appends entirely.

## H1 reactor

> Available since v0.5.5, Linux only, experimental. Requires
> `h1_fast_path`; config validation rejects `h1_reactor` without it.

The reactor is a single-goroutine event loop per plaintext listener that
serves batches of cache hits from one `epoll_wait` wakeup — parse, cache
lookup, and `writev` flush all happen inline on raw file descriptors, with
no goroutine park/unpark per request. This is the residual structural gap
to nginx's worker event loop, closed.

- Gate benchmark: ~129 ns and 0 allocs/op per reactor hit
- Hit flush: one zero-copy, zero-alloc `writev` with exact-offset resume on partial writes
- Keep-alive RTT: a bounded adaptive busy-poll after each served batch (single-client keep-alive p50 41.7 → 10.2 µs; +16% sustained throughput at equal CPU; zero CPU ticks while idle)

```yaml
experimental:
  h1_fast_path: true
  h1_reactor: true
```

### Bounds and handoff

The reactor is bounded by design:

- **4096 connections per loop** — over-cap connections fall back to the blocking parser path.
- **Bounded handoff-spawn queue** (128 slots) — under extreme miss storms, excess miss connections are reset rather than letting the queue stall every cache hit on the listener.
- **Handoff before any response byte**: misses, conditional requests, ranges, pipelined bodies, and oversize headers hand off to the existing blocking parser with the buffered bytes replayed, so fall-through framing, smuggling 400s, and SWR semantics are shared, not reimplemented.
- **TLS listeners are never reactor-served.**
- **Sweep safety nets**: a 5-minute write-timeout sweep drops clients that stop reading mid-response; an idle sweep closes keep-alive connections at `listen.idle_timeout` parity with the blocking path.

### Rollback

`BOUINE_REACTOR_SPIN_BUDGET=0` disables the adaptive busy-poll (A/B
comparisons), and `experimental.h1_reactor: false` falls back to the
blocking parser path entirely — same fast-path hit core,
goroutine-per-connection scheduling. The spin budget defaults to 80.

If the reactor is suspected mid-incident, see the
[`51-h1-reactor` runbook](https://github.com/bouine-cache/bouine/blob/main/docs/runbook/51-h1-reactor.md)
in the bouine repository.

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
  h1_reactor: true
```

### Verifying with conformance tests

Run the cache-tests conformance suite with the fast path enabled to verify no regressions:

```bash
make conformance-fastpath
```

This runs the standard `http-tests/cache-tests` harness with `experimental.h1_fast_path: true` and reports the pass rate. The fast path should match the baseline conformance score (no regressions).

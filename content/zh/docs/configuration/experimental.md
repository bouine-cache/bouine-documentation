---
title: "实验性功能"
weight: 7
description: "Opt-in experimental features that may become stable in future releases."
---

Experimental features are opt-in capabilities behind the `experimental` config section and default to off.

> **Warning:** Experimental features may change or be removed between releases. Test thoroughly before enabling in production.

## Configuration

All experimental fields live under the top-level `experimental` key:

```yaml
experimental:
  config_reload: true
```

## Field reference

| Field | Default | Description |
---|---|---|
| `config_reload` | `false` | Enable `bouine config reload` / `POST /v1/config/reload` to apply a config file to a running daemon without a restart (since v0.6.0, issue #817, phase 1). See [Hot configuration](../#hot-configuration). |

## Retired keys (accepted but ignored, since v0.6.0)

Three keys that gated the H1 fast path are **retired in v0.6.0** (ADR-0069).
They still parse — any combination loads, so pre-promotion configs keep
working — but they are ignored and a retirement notice is logged at startup
when set. There is no opt-out.

| Field | Status | Description |
---|---|---|
| `h1_fast_path` | always on since v0.6.0 | The zero-allocation HTTP/1.1 hit path (`internal/server/h1parser`) is now built whenever a store exists, with no config gate. |
| `h1_fast_peer_path` | always on since v0.6.0 | The fast-path peer branch is wired on every strong-mode cluster — the same owner-first miss path the slow path has always taken, closing a consistency gap where identical traffic took different miss paths depending on the parser. |
| `h1_reactor` | **removed** in v0.6.0 | The single-goroutine epoll event loop (ADR-0041) is deleted; configs setting it now fail strict parsing with an unknown-field error. Remove the key. All fast-path traffic uses the blocking h1parser path (one goroutine per connection). |

## H1 fast path (now the default path)

Since v0.6.0 the fast path is the default path. When a store exists, bouine
uses the custom HTTP/1.1 request parser (`internal/server/h1parser`) that
bypasses `fasthttp` on cache hits. This eliminates `*http.Request`
allocation, `http.ResponseWriter` wrapping, header-map operations, and
tracing/metrics middleware for cacheable GET/HEAD requests.

> **Since v0.5.21 the fast path is built per route** (issue #696): fast-path
> hits are attributed to the route's configured `upstream_pool` (previously
> every fast-path hit was recorded with `upstream_pool="_default"`, so
> enabling the fast path fleet-wide made per-pool dashboard series vanish),
> and run under the route's `cache.key` policy. Requests matching no route or
> a non-cached route fall through to the slow path instead of being served
> store-level ghost hits. Route resolution adds 0 allocs/op and ~22 ns per
> hit. The unified RFC 9111 evaluation (v0.5.21, issue #589) also brought the
> fast path to feature parity with the slow path: stale-if-error,
> validator-aware no-cache, and heuristic-freshness branches now run on all
> three paths, and its variant-key overflow falls back to the allocation
> path instead of silently returning the primary key.
>
> **v0.5.0 context:** The entire data plane was migrated to `fasthttp` in
> v0.5.0. The H1 fast path goes one step further by bypassing `fasthttp`
> entirely on cache hits, using a stack-allocated parser that avoids all
> allocations on the hot path.
>
> **Since v0.6.0** the fast path also grows the shutdown drain the fasthttp
> path already had: `serveFastPath` tracks each connection's idle/in-flight
> state through a zero-allocation h1parser conn-state hook, closes idle
> keep-alive connections immediately on shutdown, and lets in-flight
> responses finish (`fasthttp.Server.Shutdown` parity). Previously a shutdown
> with open idle connections hung the listener goroutine until every idle
> deadline expired.

### What it does

1. **Parses HTTP/1.1 requests** from the raw `net.Conn` into a stack-allocated `RawRequest` struct using zero-copy `unsafe.String` conversion (113 ns/op, 0 allocations).
2. **Serves cache hits directly** by looking up the key in the hot tier, computing freshness, and writing the response via `net.Buffers.WriteTo` (single `writev` syscall) — no `*http.Request` or `http.ResponseWriter` constructed.
3. **Falls through to `fasthttp`** for misses, non-GET/HEAD methods, conditional requests, and HTTP/1.0.

### What stays on the standard path

The following request types always go through the standard `fasthttp` handler chain regardless:

- **HTTP/1.0** requests (different keep-alive semantics)
- **Non-GET/HEAD methods** (POST, PUT, DELETE, etc.)
- **Conditional requests** (`If-None-Match`, `If-Modified-Since`, `If-Match`, `If-Unmodified-Since`, `If-Range`, `Range`)
- **Requests with `Cache-Control: no-cache` or `no-store`**
- **Requests with `Pragma: no-cache`**
- **Headers exceeding 16 KiB** (fall through to the standard handler)
- **Requests announcing `Accept: text/event-stream`** — SSE is always served as a live unbuffered stream, see [Streaming and live responses](../streaming/)
- **Paths the fasthttp normalization would rewrite** (since v0.6.0): the fast path hashes the raw path, so dot-segment, percent-escaped, or fragment-bearing spellings can never fast-path-hit — they are declined up front instead of paying a doomed lookup. The origin-bound request-target is normalized through fasthttp's own URI parser so the origin always receives the spelling the cache key hashed (issue #847).

### Fall-through behavior

When the fast path cannot serve a request (cache miss, non-cacheable method, etc.), it hands off to the standard `fasthttp` handler chain with the bytes already parsed replayed — the request is re-parsed from a buffered prefix plus the live socket, so request bodies spanning multiple TCP reads, pipelined bytes after a hit, and headers larger than the 16 KiB parser buffer are all served correctly. `bufio.Reader`s on the fall-through paths are pooled per listener (`sync.Pool`, since v0.6.0) instead of allocated per request.

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

## Config reload (experimental)

> Available since v0.6.0, experimental, off by default. Enable with
> `experimental.config_reload: true`.

`bouine config reload` (and `POST /v1/config/reload`) applies a config file
to a running daemon without a restart:

1. Re-parse and validate the file — any failure leaves the running config untouched.
2. Apply the hot-appliable subset through the hot-config knob registry (which reverts runtime drift back to the file).
3. Report three sections: **applied** (old → new values), **unchanged**, and **NEEDS RESTART** for cold-only fields and knobs that refused, each with its reason.

A daemon with the flag off answers 503 with the opt-in instructions.
The CLI prints `needs_restart` loudly; rollback is operational (reload the
previous git-tracked file). Reload is per-node — cluster-coordinated switch
and the route/pool phase 2 land separately. Audit rides slog plus
`bouine_config_reloads_total{result}` and the admin write rate limit.

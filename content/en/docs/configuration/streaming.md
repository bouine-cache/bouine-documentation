---
title: "Streaming and live responses"
weight: 2
description: "How bouine streams response bodies, serves Server-Sent Events, and sheds excess load when the origin is slow."
---

bouine never buffers a response body when it does not have to. This page
documents the three streaming behaviours and the two overload protections
that interact with them.

## Server-Sent Events (SSE)

bouine serves Server-Sent Events as **live end-to-end streams**. A request
announcing `Accept: text/event-stream` (the WHATWG client contract — what
browsers, `EventSource`, and AI SDKs send) is served as an unbuffered
stream, never cached, and never collapsed by singleflight onto another
client's stream.

```yaml
routes:
  - match: { path_prefix: /chat/ }
    pool: llm
    cache:
      ttl_default: 60s
```

No route-level configuration is required: the `Accept` header is the
contract. POST-based SSE (the dominant AI API shape — a request body
followed by a streamed response) works the same way, and its
[write-method invalidation](../cache-policy/#write-method-invalidation-postputdelete)
semantics are preserved: a 2xx/3xx response purges the affected cache entry
at header time, not after the (endless) body.

### SSE serving contract

| Behaviour | Detail |
|---|---|
| `X-Cache` | `BYPASS` — the cache read is skipped entirely |
| Storage | Never stored |
| Singleflight | Never collapsed; each client gets its own origin fetch |
| Fetch slot | Released at header time — a live stream does not hold a `max_fetch_concurrency` slot |
| Flushing | Each event is flushed to the client as it arrives |
| Origin read budget | 10-minute **idle** budget, reset on every event — a live stream is never cut by wall clock |
| Client write budget | Idle-based (5 min re-armed per write on the H1 fast path, 1 h absolute without it) |

The last two rows are the key property: a stream whose origin keeps
sending events stays open indefinitely, while a dead peer or a client that
stops reading is still cut.

### Non-hinted SSE

An origin may respond `Content-Type: text/event-stream` to a request that
did not announce the `Accept` header. Such responses are still streamed
unbuffered, but they are **bounded by the route's `fetch_timeout`** (the
origin connection's read deadline was armed before the response was known
to be a stream). Fix the client to send the header; do not raise
`fetch_timeout`. Concurrent non-hinted requests for the same URL are not
collapsed onto one stream — nothing is buffered, so there is no shareable
result.

### Tuning SSE routes

- **Sparse event feeds** (gaps > 10 min without heartbeats): raise nothing.
  The origin must send SSE comment-line heartbeats, or the stream is cut
  after the 10-minute idle budget and clients reconnect. This matches
  nginx `proxy_read_timeout` / Varnish `between_bytes_timeout` in spirit.
- **Many concurrent streams**: each stream holds one client connection and
  one origin connection for its lifetime. Raise
  `upstream_pools[].connect.max_connections` (default 64) on pools fronting
  SSE-heavy routes, and `listen.max_connections` for the data plane.
  `max_fetch_concurrency` does **not** need raising — streams release
  their fetch slot at header time.
- **Hung origins**: a hinted fetch whose origin accepts the connection but
  never sends headers pins one fetch slot for up to the 10-minute idle
  budget (instead of `response_header_timeout`). Only requests that
  explicitly announce stream intent take this path.

### Failure modes

| Symptom | Cause |
|---|---|
| Stream ends after ~10 min of silence | Idle budget fired — the origin stopped sending without heartbeats |
| Stream ends at exactly `fetch_timeout` | The client did not send `Accept: text/event-stream` (non-hinted path) |
| Stream ends at 1 h with the fast path disabled | Expected on the plain fasthttp serving path; enable `experimental.h1_fast_path` or rely on client reconnects |
| `503 + Retry-After` at stream start | Fetch queue was full for `fetch_wait_timeout` — raise `max_fetch_concurrency` or investigate origin latency |

## Streaming misses

Cacheable misses are streamed to the client while the body is teed to
storage in the background, so the client does not wait for the full body
before the first byte. The tee buffers are capped:

- Per stream: `max_response_bytes` (the fetch is aborted with 502 beyond it).
- Per route: `max_streaming_buffer_bytes` — the total bytes held in live
  tee buffers across concurrent miss-fetches on the route. When exceeded,
  new cacheable misses fall back to synchronous buffering (the client
  waits for the full body, the buffer is no longer live). Default derives
  from GOMEMLIMIT (7%), with a 64 MiB built-in floor. Watch
  `bouine_streaming_buffer_bytes` and `bouine_streaming_fallback_total` to
  see pressure.

## Origin-fetch shedding

Slow origins are the classic reverse-proxy failure mode: request
goroutines park waiting for a fetch slot, pile up without bound, and the
pod enters a non-recovering livelock. bouine sheds instead.

When a foreground miss cannot acquire an origin-fetch slot (bounded by
`max_fetch_concurrency` per route) within `fetch_wait_timeout`
(default 100 ms, validated max 1 s):

1. A **stale object in scope is served stale** (RFC 5861-style, within
   `stale_if_error` semantics), or
2. the client receives **503 + `Retry-After: 1`** — distinct from the 502
   origin-failure mapping.

Singleflight followers and inflight-stream followers un-park with the
leader's shed result, so a shed affects the whole collapsed group
consistently. The `bouine_fetch_shed_total` counter exposes the shed rate
for alerting.

```yaml
routes:
  - match: { path_prefix: / }
    pool: app
    cache:
      max_fetch_concurrency: 32
      fetch_wait_timeout: 100ms
```

The wait bound exists to absorb sub-second fetch-queue bursts, not to
queue through a sustained overload: when arrival rate exceeds drain rate,
no finite wait drains the queue, so a longer bound only holds goroutines
(and their connections) longer before shedding them. Raise
`max_fetch_concurrency` or scale out instead of raising
`fetch_wait_timeout`.
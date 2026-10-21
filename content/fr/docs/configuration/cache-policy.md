---
title: "Politique de cache"
weight: 2
description: "Understand how bouine chooses TTLs, overrides them per-route, serves stale content, applies negative caching, jitters expirations, refreshes proactively before expiry, and builds cache keys."
---

## TTL selection

bouine picks freshness in this order:

1. `CDN-Cache-Control` (RFC 9211 targeted header — overrides `Cache-Control` for shared caches)
2. `s-maxage`
3. `max-age`
4. `Expires` (valid dates only; syntactically invalid Expires values are ignored)
5. Route `ttl_default` (operator fallback when origin sends no freshness)
6. Heuristic freshness from `Last-Modified` (10% of `Date − Last-Modified`, where allowed by status code)

If the route has `ttl_override` set, its value **replaces** the result of
this waterfall entirely. See [TTL override](#ttl-override) below.


## TTL override

`ttl_override` forces bouine's internal cache lifetime to a specific value,
regardless of what `max-age`, `s-maxage`, `CDN-Cache-Control`, or `Expires`
the origin sends. The upstream's response headers are forwarded to downstream
clients **unaltered** — only bouine's internal freshness counter changes.

```yaml
routes:
  - name: api
    match: { path_prefix: /api/ }
    pool: backend
    cache:
      ttl_override: 1h    # bouine caches for 1 h
      ttl_default:  30s   # fallback if origin sends no freshness headers
      stale_while_revalidate: 5m
```

### Why it exists: bouine in front of a downstream CDN

The canonical use case is a **bouine → Cloudflare** (or bouine → any CDN)
stack where you want to control the two caches independently:

```
Service → bouine → Cloudflare → Client
```

The service emits `Cache-Control: max-age=60`. Without `ttl_override`:

- bouine caches for 60 s, revalidates after each minute.
- Cloudflare sees `Cache-Control: max-age=60` and also caches for 60 s.

With `ttl_override: 1h`:

- bouine caches for **1 h**. The service is hit once per hour per bouine
  node instead of once per minute.
- Cloudflare still receives `Cache-Control: max-age=60` unaltered and
  caches for **60 s** at the edge.
- Clients get low edge latency (Cloudflare's 60 s cache) while the
  origin is shielded by bouine's much longer storage window.

> **TTL override does not mutate the forwarded headers.** `Cache-Control: max-age=60`
> is what Cloudflare (and browsers) see. Only bouine's internal
> storage lifetime changes.

### What the override does NOT affect

| Upstream directive | Behaviour with `ttl_override` set |
|---|---|
| `no-store` | Response is **not cached at all**. Override has no effect. |
| `private` | Response is **not cached at all**. Override has no effect. |
| `no-cache` | Response is stored but **revalidated on every request**. Override is bypassed. |
| `must-revalidate` | Honoured after the override TTL expires. |
| `proxy-revalidate` | Honoured after the override TTL expires. |
| `jitter_percent` | Applied to the override value (not the origin's max-age). |

`no-store` and `private` are evaluated before the object is stored;
the override never runs for these responses.

### Revalidation behaviour

When bouine's override TTL expires it performs a conditional revalidation
(`If-None-Match` / `If-Modified-Since`). If the origin returns `304 Not Modified`,
the override TTL is **re-applied** to the refreshed object — the object does
not revert to the origin's `max-age`. A full `200` is stored fresh with the
override TTL.

### Error responses (since v0.5.29)

The override applies to **success and redirect responses only** (status < 400).
Storable error responses follow the negative-caching TTL ladder — origin
explicit freshness > `negative_ttl` > heuristic > `ttl_default` — instead of
being pinned fresh for the full override duration. Previously an origin that
opted a 404 into negative caching (`Cache-Control: public, max-age=30`) got
cached for the full override duration (30 minutes instead of 30 seconds),
bypassing `negative_ttl` policies entirely. Re-check routes that pair
`ttl_override` with `negative_ttl`: storable errors now expire per the ladder.

### Combining with other cache fields

`ttl_override` composes cleanly with the rest of the cache policy:

```yaml
cache:
  ttl_override: 2h                # bouine keeps for 2 h
  stale_while_revalidate: 10m     # serve stale during background refresh
  stale_if_error: 24h             # serve if origin is down for up to 24 h
  jitter_percent: 5               # ±5 % jitter on the 2 h override
  negative_ttl: 10s               # cache 404s for 10 s (applies to storable errors since v0.5.29)
```

`ttl_default` is not superseded when `ttl_override` is set — it remains the
fallback for responses the origin sends **without any freshness headers**.
Set both if your origin is inconsistent about emitting `Cache-Control`.


## Stale serving

```yaml
cache:
  ttl_default: 60s
  stale_while_revalidate: 10s
  stale_if_error: 300s
```

- `stale_while_revalidate`: serve stale immediately and trigger a background revalidation. The next request gets a fresh `HIT` without any blocking. Concurrency is bounded to 256 simultaneous background revalidations.
- `stale_if_error`: serve stale when the origin returns 5xx or is unreachable, up to the configured window. Unlike SWR, bouine always attempts the origin first and only falls back to stale on error.

## Stayin Alive

When `stale_if_error` expires and the upstream is still down, bouine normally starts returning errors to clients. **Stayin Alive** prevents this — the cached object is served indefinitely until the upstream recovers, regardless of how long ago it expired.

```yaml
routes:
  - match: { path_prefix: /products/ }
    pool: backend
    cache:
      ttl_default: 60s
      stale_if_error: 5m
      stayin_alive: true   # serve stale forever if upstream is down
```

When `stayin_alive: true`:

- If the upstream returns 5xx, bouine serves the last known good response.
- If the upstream is unreachable (connection error, timeout), bouine serves the last known good response.
- If the upstream returns 2xx, the fresh response replaces the stale one as normal.
- If there is **no cached entry at all**, bouine cannot help — it returns 502.
- **Since v0.5.22 the TTL reaper holds expired entries while the route's origin pool has no healthy target** (grace retention): the serve-stale-while-outage promise now survives outages longer than `TTL + stale_while_revalidate + stale_if_error`. When a healthy target returns, the next reaper pass collects expired entries normally. The hold is visible as `bouine_hot_store_reaper_grace_holds_total`; full protection requires passive (`health.passive.consecutive_5xx`) or active health checks on the pool. Related: the cache-path fetch client now records passive health exactly like the proxy path, so pool ejection works on cached routes.

A `WARN` log is emitted on every stale-served request while the upstream is unhealthy:

```json
{"level":"WARN","msg":"stayin-alive: upstream 5xx, serving stale indefinitely","status":503,"key":12345}
```

**When to use it**

Use Stayin Alive for routes where showing slightly stale content is far better than showing an error — product pages, homepages, navigation menus, search results. Do **not** use it for checkout, cart, account, or any route that must reflect real-time state.

## Negative caching

```yaml
cache:
  negative_ttl: 5s
```

Caches 404, 405, 410, and 501 responses briefly. Use this to protect origins from repeated misses.

### Per-status TTLs (since v0.5.22)

`negative_ttl` also accepts a map mirroring Cloudflare's "Cache TTL by status code":

```yaml
cache:
  negative_ttl:
    404: 1m
    5xx: 10s
    503: 30s    # exact code shadows its class — "blanket + exception"
    410: 0      # zero explicitly disables caching for this status
```

Keys are a single error status (`"404"`) or a class (`4xx`, `5xx`); exact codes are limited to 400–599 (2xx/3xx entries are rejected as configuration errors). The scalar form (`negative_ttl: 30s`) is shorthand for the default error set (404/405/410/501) — the same setting written two ways. Since v0.5.22 the negative-caching policy outranks `ttl_default` and heuristic (Last-Modified) freshness **for the statuses it covers**, and objects with a covered error status are never proactively refreshed regardless of how they were cached. The policy only applies when the origin sends no explicit freshness; RFC 9111 blocking directives still win.

## Set-Cookie caching

By default, a response carrying a `Set-Cookie` header is **never cached** — even
if it has explicit freshness (`max-age`). This matches nginx's `proxy_cache`
behaviour and prevents one user's session cookie from being replayed to other
users (a session-fixation vector).

```yaml
cache:
  allow_set_cookie: false   # default — Set-Cookie blocks caching
```

To cache such responses anyway, opt in explicitly. When enabled, bouine still
delivers the cookie to the **first** client (the MISS), but **strips
`Set-Cookie` from the stored copy** so subsequent HITs never replay it:

```yaml
cache:
  allow_set_cookie: true    # cache, but strip Set-Cookie from stored object
```

| Upstream sends | `allow_set_cookie: false` (default) | `allow_set_cookie: true` |
|---|---|---|
| `Set-Cookie` + `max-age=60` | Not cached (proxied through) | Cached without `Set-Cookie` |
| `Set-Cookie` + `no-store` | Not cached | Not cached |
| No `Set-Cookie` | Cached normally | Cached normally |

> **Only enable `allow_set_cookie` on routes where the `Set-Cookie` is not
> user-specific** (e.g. a non-personalised A/B cookie). Never enable it on
> authentication or session routes.

## Cookie bypass (since v0.5.26)

`Set-Cookie` blocking protects against cookies the **origin sends**. The
mirror-image risk is a cookie the **client sends**: an SSR origin that renders
per-user HTML from the request's session cookie. Such a response must never be
stored under a shared key (served to other users) and never shared in-flight
(another user's body handed to a concurrent request). Enable `bypass_on_cookie`
on those routes and any request carrying a non-empty `Cookie` header never
touches the cache — the Varnish `return (pass)` equivalent for
`req.http.Cookie`:

```yaml
routes:
  - match: { path_prefix: /account/ }
    pool: ssr
    cache:
      ttl_default: 60s
      bypass_on_cookie: true
```

With the flag on, a cookied request is **never served from cache, never
stored, and never shares an in-flight origin fetch** — it proxies to origin
(`X-Cache: BYPASS`). Anonymous requests on the same route keep full MISS/HIT
semantics, and invalidating methods (POST/PUT/DELETE) keep invalidating the
shared GET key regardless of cookies. SSE-intent requests keep live-stream
semantics.

The trigger is Cookie-header **presence**, not a name list (fails closed): an
A/B or analytics cookie also bypasses — strip those at the ingress, or accept
the origin-render cost. The dashboard insight
`config-cookie-bypass-missing` flags storing routes whose traffic is ≥5%
cookied while the flag is off — the personalized-SSR leak shape.

> **The in-flight half is unconditional** (since v0.5.26, ADR-0052/0054): on
> **every** route, flag or not, a request carrying `Authorization` or `Cookie`
> never joins a request-collapsed origin fetch — it always performs its own
> fetch. Cookied requests still *use* the cache (a stored response is served to
> them per RFC 9111); they just never *share a live fetch*. Concurrent cookied
> misses on one URL now cost one origin fetch per caller, bounded by the fetch
> semaphore and shed machinery. Anonymous requests keep collapsing bit-for-bit.
> Use origin `Cache-Control: public, s-maxage=...` on routes that genuinely
> share responses — storage converges authorized/cookied bursts to HITs.

## Cookie-name bypass (since v0.5.27)

`bypass_on_cookie` triggers on Cookie-header **presence** — an A/B or
analytics cookie bypasses as much as a session cookie, which on
cookie-personalized SSR routes turns into "cache off". Scope the same
bypass contract to specific cookie names instead:

```yaml
routes:
  - match: { path_prefix: /account/ }
    pool: ssr
    cache:
      ttl_default: 60s
      bypass_on_cookie_names: [session_id, debug]
```

A request carrying **any listed cookie name** bypasses the cache entirely
— no lookup, no storage, no in-flight sharing, `X-Cache: BYPASS` — while
requests carrying only unlisted cookies participate in the cache per
RFC 9111.

- **Matching is on the name token only** (case-insensitive, never a value
  or a substring), after RFC 6265 OWS trimming. A listed cookie matches in
  every `; `-separated position — real browsers put the session cookie last
  in the joined line — and on **every repeated `Cookie` field line**.
- Capped at 16 names; empty entries and case-insensitive duplicates are
  rejected, as is combining it with `bypass_on_cookie` (the presence
  trigger is a strict superset — listing names under it is dead config).
- Mutually exclusive with `key.cookie_presence`: a bypassed request never
  reaches the cache, so keying it is dead config.

## User-Agent bypass (since v0.5.27)

`bypass_on_user_agent` routes requests whose `User-Agent` matches one of
the configured `*`-glob patterns entirely around the cache — the
`bypass_on_cookie` contract, triggered by the UA instead of a cookie.
It exists for **layered deployments** (client → edge → bouine) where the
edge already bypasses its own cache for a verified crawler (e.g. a
shopping-feed bot that must see current product data): without mirroring
the rule, bouine would serve its own stored copy and silently defeat the
edge rule's freshness intent.

```yaml
route_defaults:
  cache:
    bypass_on_user_agent: ["*ShoppingFeedBot*"]   # declared once for every route
```

- Patterns match the **full UA string, case-insensitively**; `*` is the
  only wildcard and matches any run of bytes including `/`; an exact
  pattern matches the whole string — `*Bot*` for substring semantics.
  Spaces cannot appear in a pattern (real UA strings contain them); use
  the substring form.
- Validation caps the list at 16 entries / 256 bytes each and rejects
  lone `*`, `**`, `?`/`[`/`]`/`\`, bytes outside graphic ASCII, and
  duplicates.
- A route's own list **replaces** an inherited `route_defaults` list
  (never a union); an explicit empty list (`[]`) opts the route out;
  static routes inherit nothing.
- The UA is spoofable client input: a spoofed UA merely costs an origin
  fetch (same as a `no-cache` request) — bypass never invalidates, evicts,
  or stores anything. Default off; RFC 9111 semantics and the cache-tests
  score are untouched, and invalidating methods (POST/PUT/DELETE) keep
  invalidating the shared key.

## Cookie presence keying (since v0.5.27)

For origins that render different content depending on whether a
consent/analytics cookie **exists** (regardless of its value),
`cache.key.cookie_presence` adds one keying bit per listed cookie name —
the CDN `check_presence` equivalent:

```yaml
cache:
  key:
    cookie_presence: [consent, analytics_opt_out]
```

Each listed name contributes a present/absent bit to the Vary variant key
(never the value). Presence rides a **synthetic Vary field** unioned into
the stored Vary value, so store/lookup pairing, peer-gate assertions,
304 revalidation, and the background-refresh replay hash the same bits
everywhere. Every request representation canonicalizes repeated
`Cookie` field lines to the RFC 6265 §4.2 form before the bits are
computed, so a presence bit never depends on which line a cookie landed
on; the refresh registry saves the `Cookie` header on presence-keyed
routes so the background replay cannot skew the variant pair.

N names multiply the stored variant count by up to 2^N — cap the list
(16, same as `include_headers`) and prefer listing only cookies the
origin actually reads; `max_variants` bounds the total. Mutually
exclusive with both `bypass_on_cookie` and `bypass_on_cookie_names`:
a bypassed request never reaches the cache, so keying it is dead config.
Like `include_headers`, the list must be identical on every cluster node
serving the route (peer gates fail safe — miss, never a wrong body).

## Object size limit

Skip caching responses whose body exceeds a size limit. The response is still
proxied to the client — only storage is skipped, so large downloads don't evict
useful entries:

```yaml
cache:
  max_object_size: 1MiB     # don't cache bodies larger than 1 MiB
```

`0` (default) means no limit.

## Write-method invalidation (POST/PUT/DELETE)

Per RFC 9111 section 4.4, bouine invalidates the cache entry for the
request URI when a non-safe method (POST, PUT, DELETE, PATCH) receives a
2xx or 3xx response from the origin. The invalidation targets the
GET-equivalent key, evicts all Vary variants, and removes the object from
the refresh registry. If the response carries a `Content-Location` or
`Location` header, those URLs are also invalidated (section 4.4).

Additionally, successful POST responses with explicit freshness
(`Cache-Control: max-age` or `s-maxage`) and a matching `Content-Location`
are stored under the GET key per RFC 9111 section 4.3.1. This is the only
case where a non-GET response is cached.

In a cluster, the invalidation **fans out to peers** (since v0.5.26): the
purge for each invalidated key (including `Location`/`Content-Location`
derived keys) is broadcast through the same batching pipeline as the admin
purge API, in every cluster mode — a `POST` landing on a non-owner node no
longer leaves the owner serving stale content until TTL. See
[Cache invalidation](/docs/operations/cache-invalidation/) for the delivery
mechanisms per cluster mode.

## Refresh before expiry

Refresh-before-expiry fires a **background conditional revalidation**
before an object's TTL expires, keeping the cache perpetually warm.
Clients always see cache hits; origin traffic drops to lightweight 304
responses with no body transfer.

This is distinct from `stale_while_revalidate` (SWR): SWR fires
*reactively* when a client request arrives after expiry and serves stale
while revalidating. Refresh-before-expiry fires *proactively* before
expiry — the object never enters the stale window, and no client request
is needed to trigger the refresh.

```yaml
cache:
  ttl_override: 30s
  refresh_before_expiry: true
  refresh_margin_percent: 20      # fire at 80% of TTL (24s into 30s)
  refresh_timeout: 5s             # max duration for a single refresh fetch
  refresh_concurrency: 16         # max concurrent background refreshes
  refresh_min_hits: 3             # only re-schedule objects hit >= 3 times
  refresh_persist_cycles: 2       # keep refreshing 2 cycles after popularity drops
  refresh_min_score: 1048576      # 1 MiB-hit score gate (staleHits × bodySize)
  refresh_max_rps: 100            # cap at 100 refresh fetches/s per route
  refresh_reactive_first: true    # SWR-first, promote popular objects to proactive
```

### How it works

1. When a cacheable object is stored, bouine schedules a background
   refresh at `StoredAt + TTL - margin` (unless `refresh_reactive_first`
   is enabled — see [Reactive-first mode](#reactive-first-mode) below).
2. At the scheduled time, a single drainer goroutine fires a conditional
   request (`If-None-Match` / `If-Modified-Since`) to the origin.
3. On `304 Not Modified`, the object's TTL is refreshed in place — the
   object never expires.
4. On `200 OK`, the object is replaced with the fresh response.
5. On error, the refresh is rescheduled with backoff (the object remains
   fresh until its original TTL expires, at which point SWR/miss path
   takes over).

After each refresh completes, bouine evaluates the object's popularity
using the [popularity gates](#popularity-gates) below. Objects that fall
below the configured thresholds are not re-scheduled and expire
naturally, reducing origin traffic for long-tail content.

### Configuration fields

| Field | Default | Description |
|---|---|---|
| `refresh_before_expiry` | `false` | Enable proactive background refresh |
| `refresh_margin_percent` | `10` | Percentage of TTL before expiry to fire (1–50). E.g. `20` fires at 80% of TTL. |
| `refresh_timeout` | `10s` | Maximum duration for a single background refresh fetch (5s–120s) |
| `refresh_concurrency` | `8` | Maximum concurrent background refresh fetches per route (1–64) |
| `refresh_min_hits` | `0` | Minimum cache hits during a TTL window for an object to qualify for re-scheduling after a refresh. `0` disables the gate (every object is refreshed). `>0` means only objects hit at least N times are re-scheduled; unpopular long-tail objects expire naturally. |
| `refresh_persist_cycles` | `0` | Number of additional TTL cycles to keep refreshing after the popularity gate (`refresh_min_hits`) would block. Each refresh with hits below the threshold decrements the counter; a popular refresh resets it. `0` disables persistence — the gate kills re-scheduling immediately. Requires `refresh_min_hits > 0`. |
| `refresh_min_score` | `0` | Minimum refresh priority score (staleHits × object body size in bytes) for re-scheduling. Weights the decision by object size: a 4 MB object with 1 hit outranks a 512 B object with 100 hits. `0` disables the score gate. Requires `refresh_before_expiry` and `refresh_min_hits > 0`. |
| `refresh_max_rps` | `0` | Caps background refresh fetches per second per route. When the cap is reached, pending refreshes are deferred with jittered backoff rather than dropped. `0` means no limit. Range 0 or 1–10000. |
| `refresh_reactive_first` | `false` | Changes the initial refresh strategy from proactive to reactive. New objects are not scheduled for proactive refresh; instead they rely on SWR — if accessed while stale, a background revalidation refreshes the object, and the popularity gate decides whether to promote it to proactive refresh for subsequent windows. Requires `stale_while_revalidate > 0` and `refresh_min_hits > 0`. |

### Popularity gates

When `refresh_min_hits` or `refresh_min_score` is set, bouine evaluates
popularity **after each background refresh completes** (not on the
initial store). The object's per-window hit count (`staleHits`) and body
size are checked against the configured thresholds:

- **`refresh_min_hits`**: the hit count during the previous TTL window
  must be >= N. This filters out long-tail objects that were cached once
  but rarely accessed again.
- **`refresh_min_score`**: the score (`staleHits × obj.BodySize`) must
  be >= N. This adds a size-weighted dimension — a large object with few
  hits may be more valuable to keep warm than a small object with many
  hits.

When both gates are set, **both must pass** for the object to be
re-scheduled. If either fails, the object is not re-scheduled and will
expire naturally at the end of its current TTL.

> The first TTL window always gets one refresh cycle — the popularity
> gate only applies on **re-scheduling after a refresh completes**.

### Persist cycles

When `refresh_persist_cycles > 0` and the popularity gate would block
re-scheduling, the object gets a grace period: it continues to be
refreshed for N additional TTL cycles. Each cycle where hits remain
below `refresh_min_hits` decrements the persist counter. If a popular
refresh occurs (hits >= `refresh_min_hits`), the counter is reset to the
configured value.

This prevents objects from falling off the refresh schedule due to a
temporary traffic dip. Set `refresh_persist_cycles` to 2–3 for routes
with bursty traffic patterns where popularity fluctuates.

### Rate limiting

`refresh_max_rps` caps the number of background refresh fetches per
second per route. When the cap is reached, the refresh is not dropped —
it is re-scheduled with a jittered backoff (100–500 ms). This prevents
refresh bursts from overwhelming the origin, which is especially useful
when:

- Many objects share the same TTL and would refresh simultaneously
- The origin has rate limits or costs per request
- You want to bound the maximum origin load from refresh traffic

### Reactive-first mode

When `refresh_reactive_first: true`, new objects are **not** scheduled
for proactive background refresh. Instead, they rely on
`stale_while_revalidate`:

1. The object is cached normally and served fresh until its TTL expires.
2. If a client requests it while stale, SWR serves the stale copy and
   triggers a background revalidation.
3. After the revalidation completes, the popularity gate evaluates
   whether to promote the object to **proactive** refresh for subsequent
   TTL windows.

This mode is ideal for routes with high key cardinality where most
objects are accessed only once or twice — proactive refresh would waste
origin requests on objects that will never be accessed again. Only
objects that prove their popularity (by being accessed while stale and
passing the `refresh_min_hits` gate) graduate to proactive refresh.

### Sizing guidance

- **Memory cost**: ~232–482 B per scheduled object (heap entry +
  Vary-only request header registry). At 1M objects, this is ~465 MB.
- **Goroutines**: one drainer + up to `refresh_concurrency` refresh
  goroutines per route with refresh enabled.
- **Origin traffic**: refresh fetches are conditional (304-capable), so
  body transfer is typically zero. The origin only needs to support
  `ETag` or `Last-Modified` for conditional requests.
- **Rate-limited traffic**: when `refresh_max_rps` is set, the maximum
  origin load from refreshes is bounded at N requests/s per route.
- **Minimum TTL**: objects with TTL < 5s are not scheduled — the refresh
  window is too tight for a network round-trip.
- **Negative-cached objects** (404/405/410/501) are never refreshed.

### Interaction with other features

- **SWR**: refresh-before-expiry and SWR are complementary. If a refresh
  fails and the object goes stale, SWR serves stale content to clients
  while a revalidation is attempted. In reactive-first mode, SWR is the
  primary trigger for the initial refresh cycle.
- **Cluster strong mode**: only the key owner schedules background
  refresh. Non-owner nodes that cache a peer-fetched object do not
  schedule redundant refreshes.
- **Invalidation**: `purge`, `ban`, and invalidating methods (POST/PUT/
  DELETE) remove the object from the refresh registry. No stale
  refreshes fire for invalidated keys.
- **Shutdown**: refresh-enabled handlers are drained before the store
  closes during shutdown, preventing use-after-close panics.

### When to use it

Use refresh-before-expiry for high-traffic routes where periodic origin
fetches at TTL expiry create noticeable latency spikes. It is most
effective for routes with:

- Short to medium TTLs (5s–5m)
- High request rates (so every expiry event affects many clients)
- Origins that support conditional requests (ETag / Last-Modified)
- Large key cardinality (1M+ keys benefit most from zero-miss caching)

Do **not** use it for routes with very long TTLs (1h+) and low traffic —
the background refresh goroutines add overhead with little benefit over
letting SWR handle the occasional revalidation.

For routes with high key cardinality and a long tail of rarely-accessed
objects, combine `refresh_min_hits` with `refresh_reactive_first` to
ensure only popular objects consume refresh bandwidth.


## Jittered TTLs

```yaml
cache:
  jitter_percent: 10
```

Applies random ±10% TTL jitter to prevent all objects expiring at the same time.

## Cache key headers

```yaml
cache:
  key:
    include_headers:
      - Accept-Language
      - BM-Market
```

Use this when the origin varies by request header. Keep the list short — every extra header increases variant cardinality. Since v0.5.21 the list is unioned with the origin's `Vary` at object-build time (never a replacement), and validation rejects `*`, whitespace-only, non-token, case-insensitive duplicate entries, entries also present in `exclude_headers`, and lists longer than 16 entries. A listed header absent from the request hashes as an empty value — one variant — matching RFC 9111 `Vary` semantics. The list must be identical on every cluster node serving the route, or ownership of the merged keyspace splits across the ring.

> **Avoid unbounded variants**
>
> Never key on raw `User-Agent`, unbounded cookies, or high-cardinality request IDs. This creates cache fragmentation and can be a cache-poisoning vector.

## Variant caps and content-negotiation bucketing

### Variant cap (`max_variants`, since v0.5.25)

The number of distinct `Vary` variants stored per primary cache key is capped (default 1024), guarding against `Vary` blow-up per RFC 9110 §12.5.5. The cap is configurable per route; `0` applies the built-in default and negative values are rejected at config validation — the cap itself cannot be disabled. When the cap is hit, further variant storage is skipped and `bouine_vary_cap_hits_total` increments; requests keep being proxied, only caching is affected.

```yaml
cache:
  max_variants: 256
```

### Request collapsing and Vary (since v0.5.27)

Concurrent misses on one key collapse onto a single origin fetch
(singleflight). Since v0.5.27 the collapsing flight is keyed on the
response's **declared variation dimensions** — the Vary surface plus
`cache.key.include_headers` — instead of the primary cache key alone:
on a cold miss, two requests differing only in a selector header can no
longer collapse onto one leader whose variant body every follower would
receive. Warm flights keep the lookup key; cold flights on a declared
route extend the key with the declared headers; cold flights on an
include-free route are refused (one extra origin fetch per concurrent
caller, first fill only).

### Vary drift detection (since v0.5.27)

An origin that changes its `Vary` header under a live cache previously
left variant keys computed under the abandoned surface until TTL —
serving wrong-variant HITs. Every revalidation now compares the stored
declaration against the fresh response's as **field sets** (reordered or
re-cased fields are the same surface; only a field appearing or
disappearing is a change) and, on a change, purges the primary key —
resolver and variants. Only 304 and cacheable 2xx responses are
declaration sources, so an origin in duress can never trigger the purge.
`bouine_vary_drift_total` is the operator signal; expect a one-cycle
hit-ratio dip per drifted key.

### Accept-Encoding bucketing (since v0.5.22)

When the origin declares `Vary: Accept-Encoding`, the header value is reduced to the coding bouine actually negotiates (`br | zstd | gzip`; highest q-value wins with ties preferring br — the sharing-maximizing order — `q=0` excludes; absent or no acceptable coding → `identity`), and origin-bound requests carry the canonical bucket token instead of the client's raw dialect. A resource's variant count becomes the number of distinct negotiated codings (at most four) instead of the number of header spellings — every br-capable browser shares one stored variant. Expect a one-TTL miss-rate step on `Vary: Accept-Encoding` routes after upgrading (old variant keys become unreachable); mixed-version clusters cannot share AE variants until the rollout completes (peer gates fail safe — miss, never a wrong body). Origins that genuinely vary bodies by the full AE string can restore the pre-bucketing behavior with `cache.key.verbatim_encoding: true` — it re-fragments the variant space.

### Accept-Language bucketing (since v0.5.22)

`Vary: Accept-Language` variants key by the **negotiated language**: the highest-weight tag — subtag preserved, ties resolved lexicographically — replaces the raw chain in the variant key, and origin-bound requests carry the winner tag. q-cascade spellings that select the same language share one stored variant instead of fragmenting one per spelling. Subtags (`en-US` vs `en-GB`) deliberately do not collapse; unbucketable chains (absent, `*`, malformed, all `q=0`) keep the legacy keying. This is the behavior the upstream `http-tests/cache-tests` suite specifies in `vary-normalise-lang-select` (kind: optimal).

### Dropping the host from the key (`include_host: false`, since v0.5.22)

An explicitly-false `cache.key.include_host` drops the host segment from the primary cache key, so the same URL+query resolves to one entry regardless of the request `Host`:

```yaml
cache:
  key:
    include_host: false
```

Motivated by routes fronted by a router that forwards an internal service host and public site hosts to the same cache (same bytes, two entries, each fed by only part of the URL's traffic). Absent and `true` keep today's `scheme|host|path|query|method` key byte-for-byte — the default cannot silently re-key existing deployments. Requests are still forwarded with the client's original Host; only key computation changes. Validation rejects `include_host: false` on a route that sets `match.host`. Like `include_headers`/`exclude_headers`, the flag must be identical on every cluster node serving the route. The admin URL-key surfaces (`/v1/purge`, `/v1/purge/batch`, `/v1/refresh`, `/v1/cachecheck`) resolve the matching route's key policy before rebuilding keys, and stored `X-Bouine-Host` metadata keeps the filling request's host — prefer path-regex or surrogate-key bans on such routes.

## Stripping query parameters from the key

Tracking and analytics parameters (`utm_source`, `fbclid`, `gclid`, `_ga`, …)
make otherwise-identical URLs into distinct cache entries, fragmenting the
cache. Strip them from the **key** while still forwarding them to the origin:

```yaml
cache:
  key:
    strip_query_params: [utm_source, utm_medium, utm_campaign, fbclid, gclid, _ga]
```

With this config, `/page?id=1&utm_source=email` and `/page?id=1&utm_source=twitter`
resolve to the **same** cache entry. The origin still receives the full query
string (including the tracking params) on a MISS.

> **Purge note**: `POST /v1/purge` computes the key from the URL you send, without
> route context. When using `strip_query_params`, send purge URLs **without** the
> stripped parameters so they match the stored key (same behaviour as Varnish).

## Excluding headers from the cache key

Origins sometimes include per-request headers in `Vary` that should not
fragment the cache — tracing IDs (`X-Request-Id`, `X-Trace-Id`),
forwarding headers (`X-Forwarded-For`), or A/B testing cookies. Each
unique value creates a separate cache entry, wasting storage and reducing
hit rate.

`exclude_headers` strips the listed request header names from the
Vary-based variant key. The origin's `Vary` response header is left
intact and forwarded to the client — only the key computation skips
the excluded headers:

```yaml
cache:
  key:
    exclude_headers:
      - x-request-id
      - x-trace-id
      - x-forwarded-for
```

With this config, two requests that differ only in `X-Request-Id` share
the same cache entry and produce a `HIT`:

```
Request A  X-Request-Id: abc   →  MISS (stored)
Request B  X-Request-Id: xyz   →  HIT  (same entry)
```

### Collapse to primary key

When exclusion removes **all** fields from the Vary list, the variant key
collapses to the primary key. This means every request with the same
scheme, host, path, query, and method shares a single cache entry —
regardless of the excluded header's value.

For example, if the origin sends `Vary: X-Request-Id` and `x-request-id`
is in `exclude_headers`, the variant key equals the primary key. All
requests to the same URL get a HIT after the first fetch.

### Case insensitivity

Header names in `exclude_headers` are matched case-insensitively. Both
`x-request-id` and `X-Request-ID` in the config will match `X-Request-Id`
in the origin's `Vary` header.

### When NOT to use `exclude_headers`

Do not exclude headers that genuinely affect the response body — such as
`Accept-Encoding`, `Accept-Language`, or `Accept`. Excluding a
content-negotiation header causes bouine to serve the wrong variant to
clients (cache poisoning). Only exclude headers you are certain do not
change the response content.

## Advanced URL normalization

Beyond `strip_query_params`, bouine supports several additional cache key
normalisation features to maximise hit ratio when origins or clients
produce URL variants that should resolve to the same cached object.

### Keep only specific query parameters

`keep_query_params` is the inverse of `strip_query_params` — only the
listed parameter names are included in the cache key; all others are
excluded. This is useful when the origin has a small set of meaningful
parameters and everything else is noise:

```yaml
cache:
  key:
    keep_query_params: [id, page, sort]
```

Mutually exclusive with `strip_query_params` and `strip_query_prefix`.
Equivalent to Varnish `qs.keep()`.

### Strip by prefix

`strip_query_prefix` removes all query parameters whose names start with
any of the listed prefixes. This covers wildcard stripping without
enumerating every variant:

```yaml
cache:
  key:
    strip_query_prefix: [utm_, fb_, _ga]
```

Capped at 16 entries in validation.

### Remove empty-value parameters

`strip_empty_params` removes query parameters with empty values
(`?foo=&bar=1` → `?bar=1`). Does not apply to params in `keep_query_params`
— allowlisted params are always kept, even with empty values.

```yaml
cache:
  key:
    strip_empty_params: true
```

### Deduplicate repeated parameters

`dedup_query_params` keeps only the first value for duplicate query
parameters (`?a=2&a=1` → `?a=2`). "First" is first in request order,
matching Varnish `qs.unique()`. Values are not sorted when dedup is
enabled.

```yaml
cache:
  key:
    dedup_query_params: true
```

### Canonicalise path

> **Removed in v0.5.19.** `cache.key.canonicalize_path` was parsed,
> validated, and documented, but its listener-level wiring never landed, so
> it had no effect on the cache key. Configs setting the knob now fail at
> load time with the strict loader instead of being silently ignored —
> remove the key when upgrading to v0.5.19 or later.

---
title: "Downstream freshness sync"
weight: 9
description: "Cap how long a downstream CDN trusts bouine's answers by synthesizing CDN-Cache-Control (RFC 9213) — without ever touching Cache-Control."
---

> **Status:** `downstream_freshness` is **planned, not yet released** — the
> design is accepted ([bouine PR #799](https://github.com/bouine-cache/bouine/pull/799),
> [ADR-0063](https://github.com/bouine-cache/bouine/blob/main/docs/decisions/0063-downstream-freshness-sync.md))
> and will land behind a default-off knob. This page documents the approved
> behaviour so you can plan rollouts in advance.

## Overview

When bouine sits behind a CDN, the chain can *amplify* freshness: a stale
answer served by bouine is re-admitted downstream as brand new, and the
end user's ceiling becomes **bouine TTL + SWR + downstream TTL** instead of
bouine's own clock.

The classic case is Cloudflare: CF discards the upstream `Age` header on
every admit, so bouine's RFC 9111-correct age accounting is thrown away.
On a route with bouine TTL 1h and `stale_while_revalidate` 10m, a CF fetch
at t=59m59s re-ages a full CF TTL — end users can see content ~2h10 old.

**Downstream freshness sync** fixes the chain at the protocol level: on
opt-in routes, bouine synthesizes a [`CDN-Cache-Control`](https://datatracker.ietf.org/doc/html/rfc9213)
header (RFC 9213) that tells the downstream CDN exactly how long *it* may
trust the answer. The end-user ceiling drops to **bouine TTL + SWR + one
revalidation cycle** (~1h10 in the example above), with zero added visitor
latency during the stale window (CF serves `UPDATING` from its own cache).

`Cache-Control` itself is **never mutated** — browsers and the existing
[`ttl_override` decoupling pattern](/docs/operations/cloudflare/#decoupling-bouine-and-cloudflare-cache-lifetimes)
keep their contract untouched.

## What `sync` synthesizes

| Serve | Synthesized `CDN-Cache-Control` |
|---|---|
| Fresh (HIT / REVALIDATED) | `public, max-age=<TTL − Age>` (floor 0) |
| Fresh, stored `no-cache` object | `public, no-cache` — never a numeric clock |
| Stale, inside the SWR window (natural aging, soft purge, heuristic) | `public, max-age=0, stale-while-revalidate=<window remaining>` |
| Stale, inside the SIE window | `public, max-age=0, stale-while-revalidate=<SIE window remaining>` |
| Stale via `stayin_alive` grace or request `max-stale` beyond the object window | strict `public, max-age=0` — no `swr` |
| Fill / MISS | `public, max-age=min(origin effective max-age, bouine final TTL)` + origin qualitative directives |
| Fill of a storable `no-cache` response | `public, no-cache` — never a numeric clock |
| Uncacheable-to-shared (`private`, `no-store`, `Vary: *`, …) | nothing — never stored, and a `public` line must never override an origin privacy marker |
| Downstream 304 | same cap as the corresponding 200 serve (+ `Warning: 110` when stale-sourced) |

Design invariants worth knowing as an operator:

- `Cache-Control` is forwarded byte-for-byte; only the RFC 9213
  CDN-targeted header is synthesized.
- Origin `CDN-Cache-Control` / `Surrogate-Control` lines are **replaced** on
  `sync` routes (synthesis is authoritative) and forwarded untouched on
  `passthrough` routes.
- The synthesized header never flows peer-ward inside a bouine cluster.
- 304 answers carry the same cap, and a downstream revalidation of a stale
  object triggers bouine's background revalidation (RFC 9111 §4.3.4 — an
  uncapped 304 would let the downstream re-freshen unboundedly).

## Configuration

`downstream_freshness` is a per-route cache knob; default `passthrough`
(today's behaviour, zero change).

```yaml
routes:
  - name: api
    match: { path_prefix: /api/ }
    pool: backend
    cache:
      downstream_freshness: sync   # passthrough (default) | sync
      ttl_override: 1h             # bouine's own clock
      stale_while_revalidate: 10m
      stale_if_error: 24h
```

## Verifying the cap

Walk the timeline with `curl` against origin, bouine, and the CDN edge:

```bash
# 1. Bouine synthesizes the cap (fresh serve, TTL 1h):
curl -sD - -o /dev/null https://bouine.internal/api/stats
#   CDN-Cache-Control: public, max-age=3600        (at t=0)
#   CDN-Cache-Control: public, max-age=60          (at t=59m)
#   Cache-Control: max-age=3600                    (untouched, always)

# 2. During the SWR window bouine serves stale and mirrors:
#   CDN-Cache-Control: public, max-age=0, stale-while-revalidate=480

# 3. At the CDN edge, expect cf-cache-status:
#   HIT       — fresh entry
#   UPDATING  — during bouine's SWR window (stale served instantly,
#               CF revalidates asynchronously against bouine)
```

Full behaviour matrix, invariants and ceiling math:
[ADR-0063](https://github.com/bouine-cache/bouine/blob/main/docs/decisions/0063-downstream-freshness-sync.md).

## Cloudflare caveats

Zone settings can override the synthesized header — check these before
rolling out:

- **Edge Cache TTL / `set_cache_control` Cache Rules** override
  `CDN-Cache-Control` — the cap is voided on matched paths.
- **Always Online** ignores `stale-while-revalidate` / `stale-if-error` —
  the mirror degrades to strict `max-age=0` (safe, but every request
  revalidates).
- **Browser Cache TTL** rules govern the eyeball TTL independently of this
  feature.
- With `Authorization` present, bouine always emits `public` (its absence
  would make CF BYPASS the entry).

## Other CDNs: Fastly and bunny.net

RFC 9213 is the portable contract, but support differs per vendor
(verified against published docs, 2026-10):

| | Cloudflare | Fastly | bunny.net |
|---|---|---|---|
| TTL input | `CDN-Cache-Control` (highest) | `Surrogate-Control` > `s-maxage` > `max-age`; CDC-family not in the documented precedence | `Cache-Control` / `Expires` + zone settings |
| Upstream `Age` | discarded | subtracted from `max-age` | not accounted for |
| `stale-while-revalidate` | async `UPDATING` | async bg revalidation | not supported — blocking re-fetch |
| `stale-if-error` | honoured | honoured | not supported |
| What `sync` achieves | full cap | cap at the **origin's** clock via native `Age` subtraction; overshoots when `ttl_override` < origin `max-age` | inert — the amplifier persists when bouine TTL < origin `max-age` |

Mitigations:

- **Fastly:** bouine's synthesized CDC is inert (Fastly's targeted header is
  `Surrogate-Control`, which `sync` replaces). The native `Age` subtraction
  already caps Fastly's entry at the origin's `max-age`; when
  `ttl_override` makes bouine tighter than the origin, Fastly overshoots by
  the difference — tighten the origin's `max-age` or accept the documented
  residual.
- **bunny.net:** CDC-family headers are not part of bunny's documented
  behaviour, so `sync` is inert. Capping requires either `Cache-Control`
  mutation (bouine will not do this) or bunny **"Override Cache Time"**
  Edge Rules on your zone.

In every configuration `sync` degrades to *inert*, never unsafe: the
header is additive and ignored where unsupported.

## See also

- [Cloudflare CDN propagation](/docs/operations/cloudflare/) — forwarding
  purge/ban/refresh to the CF edge, and the `ttl_override` decoupling
  pattern (the complement of this feature).
- [Cache policy](/docs/configuration/cache-policy/) — `ttl_override`,
  `stale_while_revalidate`, `stale_if_error` reference.
- [ADR-0063](https://github.com/bouine-cache/bouine/blob/main/docs/decisions/0063-downstream-freshness-sync.md)
  — full decision record, behaviour matrix and rejected alternatives.
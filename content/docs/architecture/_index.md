---
title: "Architecture"
weight: 4
description: "How bouine is structured internally: listeners, pipeline, storage, cache engine, origin pools, clustering, and observability."
---


## Layered design

bouine is structured in 9 layers, each testable in isolation.

<div style="position:relative;margin:1.5rem 0;">
  <button id="arch-replay" onclick="archReplay()" style="position:absolute;top:8px;right:8px;z-index:10;cursor:pointer;padding:.2rem .6rem;border:1px solid rgba(139,92,246,.5);border-radius:4px;background:rgba(13,13,26,.8);color:#c4b5fd;font-size:.7rem;font-family:monospace;">↺ replay</button>
  <svg id="arch-svg" viewBox="0 0 600 380" style="width:100%;border-radius:8px;background:#0d0d1a;display:block;" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="ag-lg" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stop-color="#4c1d95"/>
        <stop offset="100%" stop-color="#2e1065"/>
      </linearGradient>
    </defs>

    <!-- Phase 1: Stack overview -->
    <g id="arch-overview">
      <rect id="ao-client"     x="20"  y="155" width="90"  height="70" rx="8" fill="none" stroke="#475569" stroke-width="1.5" opacity="0"/>
      <text                    x="65"  y="185" text-anchor="middle" fill="#94a3b8" font-size="11" opacity="0" id="ao-ct1">Client</text>
      <text                    x="65"  y="200" text-anchor="middle" fill="#64748b" font-size="9"  opacity="0" id="ao-ct2">browser / app</text>
      <line id="ao-arr1" x1="112" y1="190" x2="148" y2="190" stroke="#475569" stroke-width="1.5" stroke-dasharray="4,3" opacity="0"/>
      <rect id="ao-box"        x="150" y="115" width="300" height="150" rx="10" fill="rgba(109,40,217,.12)" stroke="#8b5cf6" stroke-width="2" opacity="0"/>
      <text id="ao-boxt"       x="300" y="178" text-anchor="middle" fill="#a78bfa" font-size="18" font-weight="bold" opacity="0">bouine</text>
      <text id="ao-boxsub"     x="300" y="200" text-anchor="middle" fill="#7c3aed" font-size="10" opacity="0">HTTP/1+2+3 · RFC 9111 · gossip cluster</text>
      <line id="ao-arr2" x1="452" y1="190" x2="488" y2="190" stroke="#475569" stroke-width="1.5" stroke-dasharray="4,3" opacity="0"/>
      <rect id="ao-origin"     x="490" y="155" width="90"  height="70" rx="8" fill="none" stroke="#475569" stroke-width="1.5" opacity="0"/>
      <text                    x="535" y="185" text-anchor="middle" fill="#94a3b8" font-size="11" opacity="0" id="ao-ot1">Origin</text>
      <text                    x="535" y="200" text-anchor="middle" fill="#64748b" font-size="9"  opacity="0" id="ao-ot2">upstream</text>
    </g>

    <!-- Phase 2: Layers (revealed after zoom) -->
    <g id="arch-layers" opacity="0" transform="translate(50,20)">
      <rect class="al" x="0" y="0"   width="500" height="38" rx="5" fill="rgba(109,40,217,.18)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="24" fill="#c4b5fd" font-size="11" font-weight="700">L8</text>
      <text x="44" y="24" fill="#a78bfa" font-size="11">Observability</text>
      <text x="210" y="24" fill="#5b21b6" font-size="9">Prometheus · OpenTelemetry · slog · pprof</text>

      <rect class="al" x="0" y="42"  width="500" height="38" rx="5" fill="rgba(109,40,217,.16)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="66" fill="#c4b5fd" font-size="11" font-weight="700">L7</text>
      <text x="44" y="66" fill="#a78bfa" font-size="11">Control Plane</text>
      <text x="210" y="66" fill="#5b21b6" font-size="9">admin API · purge · ban · config · reload</text>

      <rect class="al" x="0" y="84"  width="500" height="38" rx="5" fill="rgba(109,40,217,.14)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="108" fill="#c4b5fd" font-size="11" font-weight="700">L6</text>
      <text x="44" y="108" fill="#a78bfa" font-size="11">Cluster</text>
      <text x="210" y="108" fill="#5b21b6" font-size="9">gossip · hashring · peer fetch · digests</text>

      <rect class="al" x="0" y="126" width="500" height="38" rx="5" fill="rgba(109,40,217,.12)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="150" fill="#c4b5fd" font-size="11" font-weight="700">L5</text>
      <text x="44" y="150" fill="#a78bfa" font-size="11">Origin / Upstream</text>
      <text x="210" y="150" fill="#5b21b6" font-size="9">pool · health · hedge · circuit breaker</text>

      <rect class="al" x="0" y="168" width="500" height="38" rx="5" fill="rgba(88,28,135,.35)" stroke="#7c3aed" stroke-width="2"/>
      <text x="12" y="192" fill="#e9d5ff" font-size="11" font-weight="700">L4</text>
      <text x="44" y="192" fill="#e9d5ff" font-size="11" font-weight="700">Cache Engine</text>
      <text x="210" y="192" fill="#6d28d9" font-size="9">RFC 9111 · Vary · SWR · SIE · revalidation</text>

      <rect class="al" x="0" y="210" width="500" height="38" rx="5" fill="rgba(109,40,217,.12)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="234" fill="#c4b5fd" font-size="11" font-weight="700">L3</text>
      <text x="44" y="234" fill="#a78bfa" font-size="11">Storage</text>
      <text x="210" y="234" fill="#5b21b6" font-size="9">hot (RAM) · warm (mmap) · SIEVE · WAL</text>

      <rect class="al" x="0" y="252" width="500" height="38" rx="5" fill="rgba(109,40,217,.10)" stroke="#5b21b6" stroke-width="1"/>
      <text x="12" y="276" fill="#c4b5fd" font-size="11" font-weight="700">L2</text>
      <text x="44" y="276" fill="#a78bfa" font-size="11">Request Pipeline</text>
      <text x="210" y="276" fill="#5b21b6" font-size="9">normalize · route · ACL · collapse</text>

      <rect class="al" x="0" y="294" width="500" height="38" rx="5" fill="rgba(109,40,217,.08)" stroke="#4c1d95" stroke-width="1"/>
      <text x="12" y="318" fill="#c4b5fd" font-size="11" font-weight="700">L1</text>
      <text x="44" y="318" fill="#a78bfa" font-size="11">Listeners</text>
      <text x="210" y="318" fill="#4c1d95" font-size="9">HTTP/1.1 · HTTP/2 · HTTP/3 · TLS · PROXY proto</text>
    </g>
  </svg>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/animejs/3.2.2/anime.min.js"></script>
<script>
var archTl;
function archPlay() {
  archTl = anime.timeline({ autoplay: true, loop: false });
  archTl
    .add({ targets: '#ao-client,#ao-ct1,#ao-ct2,#ao-arr1,#ao-box,#ao-boxt,#ao-boxsub,#ao-arr2,#ao-origin,#ao-ot1,#ao-ot2',
           opacity: [0,1], duration: 700, easing: 'easeOutQuad', delay: anime.stagger(70) })
    .add({ targets: '#ao-box', stroke: ['#8b5cf6','#c4b5fd','#8b5cf6'], duration: 700, easing: 'easeInOutSine' }, '+=400')
    .add({ targets: '#arch-overview', opacity: 0, duration: 450, easing: 'easeInQuad' }, '+=350')
    .add({ targets: '#arch-layers', opacity: 1, duration: 350, easing: 'easeOutQuad' }, '-=200')
    .add({ targets: '#arch-layers .al', translateX: [-28,0], opacity: [0,1], duration: 380,
           easing: 'easeOutBack', delay: anime.stagger(55) }, '-=150');
}
function archReplay() { archPlay(); }
archPlay();
</script>

## HTTP stacks

Two HTTP implementations only:

<div class="text-start">

- **`net/http`** — HTTP/1.1 + HTTP/2 (data plane + admin)
- **`quic-go/http3`** — HTTP/3 (data plane only)

</div>

Both share `http.Handler`. The admin API uses `net/http.ServeMux`.

## Cache engine

The RFC 9111 state machine is deterministic: inputs are `*http.Request`, stored `*Object`, and `now`. Outputs are `HIT`, `MISS`, `REVALIDATE`, `STALE_HIT`, or `BYPASS`.

### Cache key

Primary key: `xxhash64(scheme | host | path | sorted_query | method)`

Secondary key (Vary): derived from the request headers listed in the response's `Vary` header, or from `cache.key.include_headers`.

### Eviction

<div class="text-start">

- **SIEVE** (default) — simple, near-LRU-K performance, O(1) per operation
- **W-TinyLFU** (optional) — better hit ratio under skew

</div>

### Negative caching

404, 405, 410, 501 responses can be cached for a configurable duration (`negative_ttl`).

### Jittered TTLs

Random ±N% applied to every TTL to prevent synchronized expiry stampedes across cached entries.

## Clustering

### Membership

`hashicorp/memberlist` for gossip. Nodes bootstrap via StatefulSet DNS.

### Sharding

Consistent hash with 256 virtual nodes per real node. On a miss, the requesting node checks the owner node before going to origin.

### Peer fetch flow

```
Client → bouine-1 (miss) → bouine-0 (owner, hit) → response
Client → bouine-1 (miss) → bouine-0 (miss) → origin → response
```

Added latency for a peer hit: ~0.3ms (one in-cluster HTTP/2 hop).

### Invalidation propagation

<div class="text-start">

- **Purge**: forwarded to the key's owner node
- **Ban**: broadcast to all peers
- **Refresh**: forwarded to the key's owner node

</div>

### Join protocol

Pods retry joining every 2 seconds for up to 60 seconds. Success requires `Members() > 1` (at least one real peer, not self-join). The headless Service **must** have `publishNotReadyAddresses: true`.

## Performance

| Benchmark | Result |
|---|---|
| `Evaluate_Hit` | 100 ns/op, 0 allocs |
| `HotStore_Get_Hit` | 5.4 ns/op, 0 allocs |
| `Handler_CacheHit` | 626 ns/op, 9 allocs |
| `SIEVE_Access` | 5.4 ns/op, 0 allocs |

All gates enforced in CI — regressions block merge.

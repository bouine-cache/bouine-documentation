---
title: "对比 bouine"
description: "Side-by-side comparison of bouine against Envoy, NGINX, HAProxy, Varnish, and Caddy — across DevOps, SRE, and Software Engineer criteria."
---

<!-- Comparison data — consumed by the compare layout's JavaScript renderer -->
<script type="application/json" id="compareData">
{
  "envoy": { "name": "Envoy", "type": "Service Mesh Proxy", "lang": "C++", "verdict": "Choose bouine if you want a purpose-built cache without Envoy's control-plane complexity (xDS, Istio). Envoy is a full service-mesh proxy; bouine is a cache that happens to cluster.",
    "cats": [
      { "name": "DevOps", "rows": [
        ["Kubernetes-native deploy","yes","yes",""],
        ["Helm chart","yes","yes",""],
        ["YAML config","yes","yes",""],
        ["Hot config reload","no","yes",""],
        ["Single static binary","yes","yes",""]
      ]},
      { "name": "SRE", "rows": [
        ["Prometheus metrics","yes","yes",""],
        ["OpenTelemetry tracing","yes","yes",""],
        ["Distributed clustering","yes","yes","Gossip, 3 modes"],
        ["Sub-second invalidation","yes","partial",""],
        ["Stale-if-error","yes","partial",""],
        ["Stayin-Alive","yes","no",""],
        ["Built-in dashboard","yes","partial","Admin UI"],
        ["mTLS for peers","yes","yes",""]
      ]},
      { "name": "Software Engineers", "rows": [
        ["RFC 9111 conformance","yes","partial","94% cache-tests"],
        ["Vary header support","yes","yes",""],
        ["Surrogate keys","yes","no",""],
        ["Request coalescing","yes","yes",""],
        ["Negative caching","yes","partial",""],
        ["Programmable logic","no","yes","YAML / Lua, WASM"],
        ["Implementation language","Go","C++",""]
      ]},
      { "name": "bouine-specific", "rows": [
        ["No external KV store","yes","no","Needs control plane"],
        ["SIEVE eviction (O(1))","yes","no","LRU"],
        ["Consistent-hash + peer-fetch","yes","yes",""],
        ["Jittered TTLs","yes","no",""],
        ["Background SWR","yes","partial",""],
        ["Hedged fetch","yes","yes",""],
        ["Zero-alloc hit path","yes","no","40 ns/op"]
      ]}
    ]
  },
  "nginx": { "name": "NGINX", "type": "Web Server / Proxy", "lang": "C", "verdict": "Choose bouine for RFC 9111-native caching with built-in clustering and Prometheus metrics — without Lua modules or a paid Plus license.",
    "cats": [
      { "name": "DevOps", "rows": [
        ["Kubernetes-native deploy","yes","partial",""],
        ["Helm chart","yes","partial",""],
        ["YAML config","yes","no","Custom DSL"],
        ["Hot config reload","no","yes",""],
        ["Single static binary","yes","no","Dynamic modules"]
      ]},
      { "name": "SRE", "rows": [
        ["Prometheus metrics","yes","partial","Via module"],
        ["OpenTelemetry tracing","yes","no",""],
        ["Distributed clustering","yes","no","3rd-party only"],
        ["Sub-second invalidation","yes","no","Full purge only"],
        ["Stale-if-error","yes","yes",""],
        ["Stayin-Alive","yes","no",""],
        ["Built-in dashboard","yes","no",""],
        ["mTLS for peers","yes","yes",""]
      ]},
      { "name": "Software Engineers", "rows": [
        ["RFC 9111 conformance","yes","partial","94% cache-tests"],
        ["Vary header support","yes","yes",""],
        ["Surrogate keys","yes","no",""],
        ["Request coalescing","yes","yes","proxy_cache_lock"],
        ["Negative caching","yes","yes",""],
        ["Programmable logic","no","yes","YAML / Lua, njs"],
        ["Implementation language","Go","C",""]
      ]},
      { "name": "bouine-specific", "rows": [
        ["No external KV store","yes","yes",""],
        ["SIEVE eviction (O(1))","yes","no","LRU"],
        ["Consistent-hash + peer-fetch","yes","no",""],
        ["Jittered TTLs","yes","no",""],
        ["Background SWR","yes","yes","proxy_cache_bg_update"],
        ["Hedged fetch","yes","no",""],
        ["Zero-alloc hit path","yes","no","40 ns/op"]
      ]}
    ]
  },
  "haproxy": { "name": "HAProxy", "type": "Load Balancer", "lang": "C", "verdict": "Choose bouine when you need HTTP caching. HAProxy is a load balancer, not a cache. Pair HAProxy with bouine for caching.",
    "cats": [
      { "name": "DevOps", "rows": [
        ["Kubernetes-native deploy","yes","partial",""],
        ["Helm chart","yes","partial",""],
        ["YAML config","yes","no","Custom DSL"],
        ["Hot config reload","no","yes",""],
        ["Single static binary","yes","yes",""]
      ]},
      { "name": "SRE", "rows": [
        ["Prometheus metrics","yes","partial","Via exporter"],
        ["OpenTelemetry tracing","yes","partial",""],
        ["Distributed clustering","yes","partial","Peer sync"],
        ["Sub-second invalidation","yes","partial",""],
        ["Stale-if-error","yes","no",""],
        ["Stayin-Alive","yes","no",""],
        ["Built-in dashboard","yes","no",""],
        ["mTLS for peers","yes","yes",""]
      ]},
      { "name": "Software Engineers", "rows": [
        ["RFC 9111 conformance","yes","no",""],
        ["Vary header support","yes","no",""],
        ["Surrogate keys","yes","no",""],
        ["Request coalescing","yes","no",""],
        ["Negative caching","yes","no",""],
        ["Programmable logic","no","yes","YAML / Lua"],
        ["Implementation language","Go","C",""]
      ]},
      { "name": "bouine-specific", "rows": [
        ["No external KV store","yes","yes",""],
        ["SIEVE eviction (O(1))","yes","no","LRU"],
        ["Consistent-hash + peer-fetch","yes","partial","Hash LB"],
        ["Jittered TTLs","yes","no",""],
        ["Background SWR","yes","no",""],
        ["Hedged fetch","yes","no",""],
        ["Zero-alloc hit path","yes","no","40 ns/op"]
      ]}
    ]
  },
  "varnish": { "name": "Varnish", "type": "HTTP Cache", "lang": "C", "verdict": "Choose bouine if you want K8s-native clustering, YAML config, and no VCL. Varnish has VCL and mature caching; bouine matches its semantics with simpler operations.",
    "cats": [
      { "name": "DevOps", "rows": [
        ["Kubernetes-native deploy","yes","no",""],
        ["Helm chart","yes","no",""],
        ["YAML config","yes","no","VCL"],
        ["Hot config reload","no","yes",""],
        ["Single static binary","yes","yes",""]
      ]},
      { "name": "SRE", "rows": [
        ["Prometheus metrics","yes","partial","Via exporter"],
        ["OpenTelemetry tracing","yes","no",""],
        ["Distributed clustering","yes","yes",""],
        ["Sub-second invalidation","yes","yes","Bans"],
        ["Stale-if-error","yes","yes","grace mode"],
        ["Stayin-Alive","yes","partial","beresp.grace"],
        ["Built-in dashboard","yes","no",""],
        ["mTLS for peers","yes","no",""]
      ]},
      { "name": "Software Engineers", "rows": [
        ["RFC 9111 conformance","yes","yes","94% cache-tests"],
        ["Vary header support","yes","yes",""],
        ["Surrogate keys","yes","partial","Via VCL"],
        ["Request coalescing","yes","yes","Built-in"],
        ["Negative caching","yes","yes",""],
        ["Programmable logic","no","yes","YAML / VCL"],
        ["Implementation language","Go","C",""]
      ]},
      { "name": "bouine-specific", "rows": [
        ["No external KV store","yes","yes",""],
        ["SIEVE eviction (O(1))","yes","no","LRU"],
        ["Consistent-hash + peer-fetch","yes","no",""],
        ["Jittered TTLs","yes","no",""],
        ["Background SWR","yes","yes",""],
        ["Hedged fetch","yes","no",""],
        ["Zero-alloc hit path","yes","no","40 ns/op"]
      ]}
    ]
  },
  "caddy": { "name": "Caddy", "type": "Reverse Proxy", "lang": "Go", "verdict": "Choose bouine for production-grade caching at scale. Caddy is an excellent automatic-HTTPS reverse proxy; bouine adds distributed clustering, RFC 9111 caching, and SRE observability.",
    "cats": [
      { "name": "DevOps", "rows": [
        ["Kubernetes-native deploy","yes","partial",""],
        ["Helm chart","yes","partial",""],
        ["YAML config","yes","yes","Caddyfile or JSON"],
        ["Hot config reload","no","yes",""],
        ["Single static binary","yes","yes",""]
      ]},
      { "name": "SRE", "rows": [
        ["Prometheus metrics","yes","no",""],
        ["OpenTelemetry tracing","yes","partial",""],
        ["Distributed clustering","yes","no",""],
        ["Sub-second invalidation","yes","no",""],
        ["Stale-if-error","yes","no",""],
        ["Stayin-Alive","yes","no",""],
        ["Built-in dashboard","yes","yes",""],
        ["mTLS for peers","yes","yes",""]
      ]},
      { "name": "Software Engineers", "rows": [
        ["RFC 9111 conformance","yes","partial","94% cache-tests"],
        ["Vary header support","yes","no",""],
        ["Surrogate keys","yes","no",""],
        ["Request coalescing","yes","no",""],
        ["Negative caching","yes","no",""],
        ["Programmable logic","no","partial","YAML / plugins"],
        ["Implementation language","Go","Go",""]
      ]},
      { "name": "bouine-specific", "rows": [
        ["No external KV store","yes","yes",""],
        ["SIEVE eviction (O(1))","yes","no","LRU"],
        ["Consistent-hash + peer-fetch","yes","no",""],
        ["Jittered TTLs","yes","no",""],
        ["Background SWR","yes","no",""],
        ["Hedged fetch","yes","no",""],
        ["Zero-alloc hit path","yes","no","40 ns/op"]
      ]}
    ]
  }
}
</script>

<!-- Noscript fallback: semantic HTML tables for crawlers and agents that don't execute JS -->
<noscript>

## bouine vs Envoy

| Criterion | bouine | Envoy |
|---|---|---|
| **DevOps** | | |
| Kubernetes-native deploy | ✓ | ✓ |
| Helm chart | ✓ | ✓ |
| YAML config | ✓ | ✓ |
| Hot config reload | ✗ | ✓ |
| Single static binary | ✓ | ✓ |
| **SRE** | | |
| Prometheus metrics | ✓ | ✓ |
| OpenTelemetry tracing | ✓ | ✓ |
| Distributed clustering | ✓ (Gossip, 3 modes) | ✓ |
| Sub-second invalidation | ✓ | ◐ |
| Stale-if-error | ✓ | ◐ |
| Stayin-Alive | ✓ | ✕ |
| Built-in dashboard | ✓ | ◐ (Admin UI) |
| mTLS for peers | ✓ | ✓ |
| **Software Engineers** | | |
| RFC 9111 conformance | ✓ (94% cache-tests) | ◐ |
| Vary header support | ✓ | ✓ |
| Surrogate keys | ✓ | ✕ |
| Request coalescing | ✓ | ✓ |
| Negative caching | ✓ | ◐ |
| Programmable logic | ✕ (YAML) | ✓ (Lua, WASM) |
| Implementation language | Go | C++ |
| **bouine-specific** | | |
| No external KV store | ✓ | ✕ (needs control plane) |
| SIEVE eviction (O(1)) | ✓ | ✕ (LRU) |
| Consistent-hash + peer-fetch | ✓ | ✓ |
| Jittered TTLs | ✓ | ✕ |
| Background SWR | ✓ | ◐ |
| Hedged fetch | ✓ | ✓ |
| Zero-alloc hit path | ✓ (40 ns/op) | ✕ |

**When to choose bouine:** Choose bouine if you want a purpose-built cache without Envoy's control-plane complexity (xDS, Istio). Envoy is a full service-mesh proxy; bouine is a cache that happens to cluster.

## bouine vs NGINX

| Criterion | bouine | NGINX |
|---|---|---|
| **DevOps** | | |
| Kubernetes-native deploy | ✓ | ◐ |
| Helm chart | ✓ | ◐ |
| YAML config | ✓ | ✕ (custom DSL) |
| Hot config reload | ✗ | ✓ |
| Single static binary | ✓ | ✕ (dynamic modules) |
| **SRE** | | |
| Prometheus metrics | ✓ | ◐ (via module) |
| OpenTelemetry tracing | ✓ | ✕ |
| Distributed clustering | ✓ | ✕ (3rd-party only) |
| Sub-second invalidation | ✓ | ✕ (full purge only) |
| Stale-if-error | ✓ | ✓ |
| Stayin-Alive | ✓ | ✕ |
| Built-in dashboard | ✓ | ✕ |
| mTLS for peers | ✓ | ✓ |
| **Software Engineers** | | |
| RFC 9111 conformance | ✓ (94% cache-tests) | ◐ |
| Vary header support | ✓ | ✓ |
| Surrogate keys | ✓ | ✕ |
| Request coalescing | ✓ | ✓ (proxy_cache_lock) |
| Negative caching | ✓ | ✓ |
| Programmable logic | ✕ (YAML) | ✓ (Lua, njs) |
| Implementation language | Go | C |
| **bouine-specific** | | |
| No external KV store | ✓ | ✓ |
| SIEVE eviction (O(1)) | ✓ | ✕ (LRU) |
| Consistent-hash + peer-fetch | ✓ | ✕ |
| Jittered TTLs | ✓ | ✕ |
| Background SWR | ✓ | ✓ (proxy_cache_bg_update) |
| Hedged fetch | ✓ | ✕ |
| Zero-alloc hit path | ✓ (40 ns/op) | ✕ |

**When to choose bouine:** Choose bouine for RFC 9111-native caching with built-in clustering and Prometheus metrics — without Lua modules or a paid Plus license.

## bouine vs HAProxy

| Criterion | bouine | HAProxy |
|---|---|---|
| **DevOps** | | |
| Kubernetes-native deploy | ✓ | ◐ |
| Helm chart | ✓ | ◐ |
| YAML config | ✓ | ✕ (custom DSL) |
| Hot config reload | ✗ | ✓ |
| Single static binary | ✓ | ✓ |
| **SRE** | | |
| Prometheus metrics | ✓ | ◐ (via exporter) |
| OpenTelemetry tracing | ✓ | ◐ |
| Distributed clustering | ✓ | ◐ (peer sync) |
| Sub-second invalidation | ✓ | ◐ |
| Stale-if-error | ✓ | ✕ |
| Stayin-Alive | ✓ | ✕ |
| Built-in dashboard | ✓ | ✕ |
| mTLS for peers | ✓ | ✓ |
| **Software Engineers** | | |
| RFC 9111 conformance | ✓ | ✕ |
| Vary header support | ✓ | ✕ |
| Surrogate keys | ✓ | ✕ |
| Request coalescing | ✓ | ✕ |
| Negative caching | ✓ | ✕ |
| Programmable logic | ✕ (YAML) | ✓ (Lua) |
| Implementation language | Go | C |
| **bouine-specific** | | |
| No external KV store | ✓ | ✓ |
| SIEVE eviction (O(1)) | ✓ | ✕ (LRU) |
| Consistent-hash + peer-fetch | ✓ | ◐ (hash LB) |
| Jittered TTLs | ✓ | ✕ |
| Background SWR | ✓ | ✕ |
| Hedged fetch | ✓ | ✕ |
| Zero-alloc hit path | ✓ (40 ns/op) | ✕ |

**When to choose bouine:** Choose bouine when you need HTTP caching. HAProxy is a load balancer, not a cache. Pair HAProxy with bouine for caching.

## bouine vs Varnish

| Criterion | bouine | Varnish |
|---|---|---|
| **DevOps** | | |
| Kubernetes-native deploy | ✓ | ✕ |
| Helm chart | ✓ | ✕ |
| YAML config | ✓ | ✕ (VCL) |
| Hot config reload | ✗ | ✓ |
| Single static binary | ✓ | ✓ |
| **SRE** | | |
| Prometheus metrics | ✓ | ◐ (via exporter) |
| OpenTelemetry tracing | ✓ | ✕ |
| Distributed clustering | ✓ | ✓ |
| Sub-second invalidation | ✓ | ✓ (bans) |
| Stale-if-error | ✓ | ✓ (grace mode) |
| Stayin-Alive | ✓ | ◐ (beresp.grace) |
| Built-in dashboard | ✓ | ✕ |
| mTLS for peers | ✓ | ✕ |
| **Software Engineers** | | |
| RFC 9111 conformance | ✓ (94% cache-tests) | ✓ |
| Vary header support | ✓ | ✓ |
| Surrogate keys | ✓ | ◐ (via VCL) |
| Request coalescing | ✓ | ✓ (built-in) |
| Negative caching | ✓ | ✓ |
| Programmable logic | ✕ (YAML) | ✓ (VCL) |
| Implementation language | Go | C |
| **bouine-specific** | | |
| No external KV store | ✓ | ✓ |
| SIEVE eviction (O(1)) | ✓ | ✕ (LRU) |
| Consistent-hash + peer-fetch | ✓ | ✕ |
| Jittered TTLs | ✓ | ✕ |
| Background SWR | ✓ | ✓ |
| Hedged fetch | ✓ | ✕ |
| Zero-alloc hit path | ✓ (40 ns/op) | ✕ |

**When to choose bouine:** Choose bouine if you want K8s-native clustering, YAML config, and no VCL. Varnish has VCL and mature caching; bouine matches its semantics with simpler operations.

## bouine vs Caddy

| Criterion | bouine | Caddy |
|---|---|---|
| **DevOps** | | |
| Kubernetes-native deploy | ✓ | ◐ |
| Helm chart | ✓ | ◐ |
| YAML config | ✓ | ✓ (Caddyfile or JSON) |
| Hot config reload | ✗ | ✓ |
| Single static binary | ✓ | ✓ |
| **SRE** | | |
| Prometheus metrics | ✓ | ✕ |
| OpenTelemetry tracing | ✓ | ◐ |
| Distributed clustering | ✓ | ✕ |
| Sub-second invalidation | ✓ | ✕ |
| Stale-if-error | ✓ | ✕ |
| Stayin-Alive | ✓ | ✕ |
| Built-in dashboard | ✓ | ✓ |
| mTLS for peers | ✓ | ✓ |
| **Software Engineers** | | |
| RFC 9111 conformance | ✓ (94% cache-tests) | ◐ |
| Vary header support | ✓ | ✕ |
| Surrogate keys | ✓ | ✕ |
| Request coalescing | ✓ | ✕ |
| Negative caching | ✓ | ✕ |
| Programmable logic | ✕ (YAML) | ◐ (plugins) |
| Implementation language | Go | Go |
| **bouine-specific** | | |
| No external KV store | ✓ | ✓ |
| SIEVE eviction (O(1)) | ✓ | ✕ (LRU) |
| Consistent-hash + peer-fetch | ✓ | ✕ |
| Jittered TTLs | ✓ | ✕ |
| Background SWR | ✓ | ✕ |
| Hedged fetch | ✓ | ✕ |
| Zero-alloc hit path | ✓ (40 ns/op) | ✕ |

**When to choose bouine:** Choose bouine for production-grade caching at scale. Caddy is an excellent automatic-HTTPS reverse proxy; bouine adds distributed clustering, RFC 9111 caching, and SRE observability.

</noscript>
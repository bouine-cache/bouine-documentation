---
title: "Example configurations"
weight: 5
description: "Ready-to-adapt bouine YAML examples for static sites, API gateways, and e-commerce routes with private areas and safety notes."
---

# Example configurations

## Static site / blog

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 64Mo
  eviction: sieve

upstream_pools:
  - name: site
    targets: ["site.default.svc.cluster.local:80"]

routes:
  - match: { path_prefix: /assets/ }
    pool: site
    cache:
      ttl_default: 86400s
      stale_if_error: 604800s
      jitter_percent: 10

  - match: { path_prefix: / }
    pool: site
    cache:
      ttl_default: 300s
      stale_while_revalidate: 60s
      stale_if_error: 86400s
      jitter_percent: 15
```

## API gateway

```yaml
upstream_pools:
  - name: api
    targets: ["api.default.svc.cluster.local:8080"]
    health:
      active:
        path: /healthz
        interval: 5s
        timeout: 1s
        unhealthy_threshold: 3

routes:
  - match: { path_prefix: /v1/ }
    pool: api
    cache:
      ttl_default: 30s
      stale_while_revalidate: 10s
      stale_if_error: 300s
      negative_ttl: 5s
      key:
        include_headers: [Accept-Language]
```

## E-commerce

```yaml
routes:
  - match: { path_prefix: /static/ }
    pool: storefront
    cache:
      ttl_default: 604800s
      stale_if_error: 3600s

  - match: { path_prefix: /products/ }
    pool: storefront
    cache:
      ttl_default: 60s
      stale_while_revalidate: 30s
      stale_if_error: 300s

  - match: { path_prefix: /cart/ }
    pool: cart-api
    cache:
      enabled: false

  - match: { path_prefix: /checkout/ }
    pool: cart-api
    cache:
      enabled: false
```

Private routes should bypass cache entirely. Do not cache cart, checkout, account, or authenticated responses unless the origin explicitly marks them public.

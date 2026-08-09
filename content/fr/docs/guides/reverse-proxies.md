---
title: "Exemples de reverse proxy"
weight: 2
description: "Deploy bouine in front of Caddy, Traefik, HAProxy, and nginx with ready-to-adapt configuration examples."
---

## bouine in front of Caddy

Caddy typically serves static files or acts as a reverse proxy itself. Deploy bouine in front of Caddy to add caching without modifying Caddy's config.

```
Internet → bouine :8080 → Caddy :2015
```

```yaml
upstream_pools:
  - name: caddy
    targets: ["127.0.0.1:2015"]
    health:
      active:
        path: /
        interval: 10s

routes:
  - match: { path_prefix: / }
    pool: caddy
    cache:
      ttl_default: 300s
      stale_while_revalidate: 30s
      stale_if_error: 3600s
```

Caddy still handles TLS termination and certificate renewal (ACME). bouine caches the upstream responses so Caddy's backend is hit far less frequently.

## bouine in front of Traefik

In Kubernetes, Traefik acts as the ingress controller. Insert bouine between Traefik and your upstream Services.

```
Traefik IngressRoute → bouine Service → upstream Service
```

Point your `IngressRoute` at the bouine Service instead of the origin:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`example.com`)
      services:
        - name: bouine          # was: my-app-service
          port: 80
  tls:
    certResolver: letsencrypt
```

bouine config pointing at the real upstream:

```yaml
upstream_pools:
  - name: app
    targets: ["my-app-service.default.svc.cluster.local:80"]
    health:
      passive:
        consecutive_5xx: 5

routes:
  - match: { path_prefix: / }
    pool: app
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

## bouine in front of HAProxy

HAProxy handles load balancing and SSL. bouine adds caching without touching the HAProxy config — point HAProxy's backend at bouine.

```
Client → HAProxy (SSL, LB) → bouine :8080 → origin servers
```

HAProxy backend stanza:

```
backend my_app_cached
    mode http
    server bouine 127.0.0.1:8080 check
```

bouine config with multiple origin servers:

```yaml
upstream_pools:
  - name: origin
    targets:
      - "app-1.internal:8080"
      - "app-2.internal:8080"
      - "app-3.internal:8080"
    health:
      active:
        path: /healthz
        interval: 5s
        unhealthy_threshold: 3
      passive:
        consecutive_5xx: 3

routes:
  - match: { path_prefix: /api/ }
    pool: origin
    cache:
      ttl_default: 30s
      stale_if_error: 120s
      negative_ttl: 5s
      key:
        include_headers: [Accept-Language, X-Market]

  - match: { path_prefix: / }
    pool: origin
    cache:
      ttl_default: 120s
      stale_while_revalidate: 30s
      stale_if_error: 3600s
```

bouine's own round-robin and passive health checking mean HAProxy only needs to manage one upstream address. You can still keep HAProxy for SSL offload, ACLs, and rate limiting.

## bouine in front of nginx

Replace nginx `proxy_cache` with bouine while keeping nginx for routing, auth, and CORS. See the full [migration guide](../nginx-migration/) for a directive mapping.

```
Client → nginx :80 → bouine :8090 (loopback) → upstream
```

Replace `proxy_cache` directives in nginx with `proxy_pass http://127.0.0.1:8090`:

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8090;  # was: proxy_cache cache;
}
```

bouine config:

```yaml
listen:
  http: ":8090"
  admin: ":9000"

upstream_pools:
  - name: backend
    targets: ["backend.default.svc.cluster.local:8080"]

routes:
  - match: { path_prefix: /api/ }
    pool: backend
    cache:
      ttl_default: 30s
      stale_while_revalidate: 5s
      stale_if_error: 300s
```

---
title: "快速开始"
weight: 2
description: "Start a small origin server, put bouine in front of it, and verify MISS then HIT behavior through headers and metrics."
---


Start a tiny origin server:

```bash
mkdir -p /tmp/bouine-origin
printf 'hello from origin\n' > /tmp/bouine-origin/index.html
python3 -m http.server 3000 --directory /tmp/bouine-origin
```

Create `config.yaml`:

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 256Mo

upstream_pools:
  - name: origin
    targets: ["127.0.0.1:3000"]

routes:
  - match: { path_prefix: / }
    pool: origin
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

Run bouine:

```bash
bouine serve --config config.yaml --log-format json
```

Verify caching:

```bash
curl -sI http://127.0.0.1:8080/ | grep X-Cache
# X-Cache: MISS

curl -sI http://127.0.0.1:8080/ | grep X-Cache
# X-Cache: HIT
```

Check health and metrics:

```bash
curl -s http://127.0.0.1:9000/healthz
curl -s http://127.0.0.1:9000/readyz
curl -s http://127.0.0.1:9000/metrics | grep bouine_requests_total
```

## What happened?

1. First request had no cache object → bouine fetched from origin and stored the response.
2. Second request found a fresh object in the hot tier → bouine served it immediately.
3. The response had `X-Cache: HIT`, and the access log included `cache_status=HIT`.

## Alternative: serve files without an origin server

bouine can serve files directly from a local directory — no need to run
a separate HTTP server. See [Static file serving](/docs/configuration/static-files/)
for the full reference.

```bash
mkdir -p /tmp/bouine-static
printf 'hello from disk\n' > /tmp/bouine-static/index.html
```

Create `config.yaml`:

```yaml
listen:
  http: ":8080"
  admin: ":9000"

routes:
  - match: { path_prefix: / }
    static:
      root: /tmp/bouine-static
      index: [index.html]
```

Run bouine:

```bash
bouine serve --config config.yaml --log-format json
```

```bash
curl -sI http://127.0.0.1:8080/ | grep Content-Type
# Content-Type: text/html; charset=utf-8
```

Static routes serve from disk on every request. The OS page cache handles
hot caching in RAM. To enable bouine's cache layer (for cluster replication
or TTL-based eviction), set `cache.enabled: true` on the route.

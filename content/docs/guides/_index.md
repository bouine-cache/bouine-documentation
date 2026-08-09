---
title: "Guides"
weight: 5
description: "Step-by-step guides for migrating from Varnish or NGINX, integration patterns, and capacity planning."
---


- [Migration from Varnish](varnish-migration/) — side-by-side VCL vs YAML, purge/ban parity, observability mapping, behavioral differences, and FAQ.
- [Migration from NGINX](nginx-migration/) — map NGINX `proxy_cache` directives to bouine configuration.
- [Reverse proxy examples](reverse-proxies/) — deploy bouine in front of Caddy, Traefik, HAProxy, and nginx.
- [Capacity planning](capacity-planning/) — size hot and warm tiers, choose cluster mode and replicas, validate under load.
- [Production readiness checklist](production-checklist/) — verify TLS, resources, cluster, caching, observability, and K8s settings before going live.
- [Benchmarks](benchmarks/) — methodology and results comparing bouine vs Varnish, NGINX, and Envoy across cache hit, miss, and mixed workloads.

---
title: "Migration guides"
weight: 6
description: "Migrate to bouine from Varnish, NGINX, or between cluster consistency modes."
---

- [Varnish to bouine](varnish/) — Side-by-side VCL vs YAML, purge/ban parity, observability mapping, 7 behavioral differences, unsupported constructs, FAQ.
- [NGINX to bouine](nginx/) — Directive mapping (`proxy_cache_path`, `proxy_cache_valid`, etc.), key differences, example API gateway.
- [Cluster mode migration](cluster-mode/) — Switching between `strong`, `eventual`, and `full` consistency modes.

---
title: "Security"
weight: 3
description: "Security reporting, supported scope, high-impact vulnerability classes, and operational hardening checklist for bouine."
---


Report security issues via GitHub's
[Private vulnerability reporting](https://github.com/thylong/bouine/security/advisories/new)
— it creates a tracked, embargoed advisory. No security email alias is
published.

## Scope

- bouine binary
- Helm chart
- Container image
- Go SDK

## Examples of high-impact issues

- Cache poisoning that leaks one user's response to another
- HTTP request smuggling through the data plane
- Admin API authentication bypass
- Peer impersonation in cluster mode
- Path traversal in warm-tier storage

## Hardening checklist

- Keep admin port private; expose only through internal network or mTLS.
- Use TLS verification for upstreams.
- Run containers as non-root.
- Use NetworkPolicy for cluster and admin ports.
- Monitor purge/ban rates for misuse.
- Do not log request/response bodies or credentials.

---
title: "Security"
weight: 3
description: "Security reporting, supported scope, high-impact vulnerability classes, and operational hardening checklist for bouine."
---

# Security

Report vulnerabilities via GitHub private advisory or `security@bouine.dev`.

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

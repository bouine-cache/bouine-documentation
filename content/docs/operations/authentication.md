---
title: "Authentication"
weight: 2
description: "Configure and retrieve the admin bearer token protecting all write endpoints."
---

All write endpoints require `Authorization: Bearer <token>`. Set the token in config:

```yaml
admin:
  token: your-secret-token
```

If not set, bouine auto-generates one at startup — check the `WARN` log line or run:

```bash
make admin-token CONFIG=config.yaml
```

On Kubernetes:

```bash
kubectl logs statefulset/bouine -n <namespace> | grep "admin token"
```

Use it in CLI commands:

```bash
bouine purge https://example.com/page --token your-secret-token
```

Read-only endpoints (`/healthz`, `/readyz`, `/metrics`, `/version`, `/v1/cluster/peers`) never require authentication.

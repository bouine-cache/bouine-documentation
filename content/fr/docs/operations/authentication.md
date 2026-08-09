---
title: "Authentification"
weight: 2
description: "Configure and retrieve the admin bearer token protecting all write endpoints."
---

All write endpoints require `Authorization: Bearer <token>`. The token is resolved in priority order:

1. **`BOUINE_ADMIN_TOKEN` environment variable** (recommended for Kubernetes / Vault injection)
2. **`admin.token` in the config file**
3. **Auto-generated** random token (logged as `WARN` at startup)

### Environment variable

Set `BOUINE_ADMIN_TOKEN` to inject the token without baking it into the config ConfigMap:

```bash
export BOUINE_ADMIN_TOKEN=your-secret-token
bouine serve --config /etc/bouine/config.yaml
```

On Kubernetes with a chassis `AppSecretSet`, the env var is populated automatically from Vault — no `extraEnv` or Helm `--set` needed:

```yaml
# deploy/common/values.yaml
chassis:
  secrets:
    enabled: true
    env:
      app:
        preprod-eu:
          BOUINE_ADMIN_TOKEN:
            continent: shared
            name: dashboard
            field: admin_token
            version: "1"
```

### Config file

```yaml
admin:
  token: your-secret-token
```

### Auto-generated fallback

If neither the env var nor the config value is set, bouine auto-generates a random token at startup — check the `WARN` log line or run:

```bash
make admin-token CONFIG=config.yaml
```

On Kubernetes:

```bash
kubectl logs statefulset/bouine -n <namespace> | grep "admin token"
```

### Using the token

```bash
bouine purge https://example.com/page --token your-secret-token
```

Read-only endpoints (`/healthz`, `/readyz`, `/metrics`, `/version`, `/v1/cluster/peers`) never require authentication.

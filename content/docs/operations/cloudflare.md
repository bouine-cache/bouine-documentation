---
title: "Cloudflare CDN propagation"
weight: 8
description: "Forward bouine cache invalidation operations to Cloudflare's edge so both caches stay in sync."
---

## Overview

When bouine sits behind Cloudflare (or any scenario where Cloudflare caches
responses delivered through bouine), invalidating a URL in bouine is not
enough — the entry may also be cached at the Cloudflare edge.

The **Cloudflare CDN propagation** feature forwards bouine purge, ban, and
refresh operations to the [Cloudflare Cache API](https://developers.cloudflare.com/api/resources/cache/methods/purge/)
so both caches are invalidated atomically from the operator's point of view.

### Mapping strategy

| bouine operation | Cloudflare API call |
|---|---|
| `POST /v1/purge` (URL) | `PurgeSingleFile` (exact URL list) |
| `POST /v1/ban` with `surrogate_key` | `PurgeByTags` |
| `POST /v1/ban` with literal `path_regex` (no metacharacters) | `PurgeByPrefixes` |
| `POST /v1/ban` with literal `host_regex` | `PurgeByHostnames` |
| `POST /v1/refresh` (URL) | `PurgeSingleFile` |
| `POST /v1/ban` with complex regex | skipped — `bouine_cloudflare_purge_skipped_total` incremented |

Regex-based bans that contain metacharacters (e.g. `.*`, `[0-9]+`, `|`) cannot
be expressed as Cloudflare prefix or hostname purges and are therefore skipped.
The `bouine_cloudflare_purge_skipped_total{reason="..."}` counter records each
skipped invalidation so you can alert on them.

---

## Async mode (default)

By default `async: true`. The admin API returns `200 OK` immediately; the
Cloudflare API call runs in a background goroutine. This keeps invalidation
latency visible to operators at bouine's speed (~1 ms) rather than Cloudflare's
(~50–300 ms round-trip).

Set `async: false` only when you need synchronous confirmation that the CF edge
has acknowledged the purge — for example, during a scripted deployment where the
next step must not run until both caches are empty.

---

## Configuration

```yaml
cloudflare:
  # zone_id is the Cloudflare zone identifier, visible in the CF dashboard URL.
  # Non-secret; safe to commit.
  zone_id: "your-zone-id"

  # api_token must have the "Cache Purge" permission for this zone.
  # Leave empty and inject via the CF_API_TOKEN environment variable instead
  # (see Kubernetes section below).
  api_token: ""   # prefer env var

  # async: true (default) — admin responses return immediately; CF call runs
  # in a background goroutine.
  # async: false — blocks the admin response until CF confirms the purge.
  async: true

  # Timeout for individual Cloudflare API calls. 0 = default (10s).
  timeout: 10s

  # Selects which bouine operations are forwarded to Cloudflare.
  propagate:
    purge: true     # POST /v1/purge
    ban: true       # POST /v1/ban
    refresh: true   # POST /v1/refresh
```

### Disabling propagation selectively

Set any `propagate.*` flag to `false` to suppress forwarding for that operation.
For example, to forward only tag-based bans and not URL purges:

```yaml
cloudflare:
  zone_id: "your-zone-id"
  propagate:
    purge: false
    ban: true
    refresh: false
```

---

## Kubernetes deployment

### 1. Create the token Secret

```bash
kubectl create secret generic bouine-cf-token \
  --from-literal=CF_API_TOKEN="<your-Cache-Purge-API-token>" \
  -n bouine
```

### 2. Reference the Secret in your values file

The Helm chart has a dedicated `cloudflare` stanza for the Secret reference.
The zone ID and propagation settings live inside the `config` block (they are
rendered into the bouine config file, not set as env vars).

```yaml
# values.yaml

# Helm-level Cloudflare settings — controls secret injection only.
cloudflare:
  apiTokenSecretName: bouine-cf-token   # name of the Secret
  apiTokenSecretKey: CF_API_TOKEN        # key inside the Secret (default shown)

# bouine config block — rendered into /etc/bouine/config.yaml.
config:
  cloudflare:
    zone_id: "your-zone-id"
    # api_token is not set here; the chart injects CF_API_TOKEN as an env var.
    async: true          # default; omit for same behaviour
    timeout: 10s
    propagate:
      purge: true
      ban: true
      refresh: true
```

The Helm chart injects `CF_API_TOKEN` from the named Secret as an environment
variable. bouine reads it at startup when `cloudflare.api_token` is empty in
the config file.

### Alternative: use `extraEnv`

If you manage secrets outside the Helm chart (e.g. via External Secrets
Operator), you can inject the token through `extraEnv` and leave the
`cloudflare.apiTokenSecretName` field empty:

```yaml
extraEnv:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: bouine-cf-token
        key: token

config:
  cloudflare:
    zone_id: "your-zone-id"
    async: true
    propagate:
      purge: true
      ban: true
      refresh: true
```

---

## Monitoring

| Metric | Labels | Description |
|---|---|---|
| `bouine_cloudflare_purge_total` | `operation`, `status` | Total CF API calls by operation (`purge`, `ban`, `refresh`) and outcome (`ok`, `error`) |
| `bouine_cloudflare_purge_duration_seconds` | `operation` | Latency histogram of CF API calls |
| `bouine_cloudflare_purge_skipped_total` | `reason` | Invalidations not forwarded (CF disabled or incompatible regex) |

### Useful PromQL

```promql
# Error rate over the last 5 minutes
rate(bouine_cloudflare_purge_total{status="error"}[5m])

# p99 CF API call latency
histogram_quantile(0.99, rate(bouine_cloudflare_purge_duration_seconds_bucket[5m]))

# How many bans were skipped due to regex incompatibility
increase(bouine_cloudflare_purge_skipped_total{reason=~".*metacharacter.*"}[1h])
```

### Status endpoint

```bash
curl -s http://localhost:9000/v1/cloudflare/status \
  -H "Authorization: Bearer <token>" | jq .
```

```json
{
  "enabled": true,
  "zone_id": "your-zone-id",
  "async": true,
  "last_error": null,
  "last_success_at": "2026-05-27T14:05:00Z"
}
```

---

## Error handling and retries

Cloudflare API errors are retried with exponential back-off:

- **429 (Rate Limit)** — retried up to 3 times with jitter, honouring
  `Retry-After` if present.
- **5xx (Server Error)** — retried up to 3 times.
- **4xx (Client Error)** — not retried; logged at `warn` level and counted in
  `bouine_cloudflare_purge_total{status="error"}`.
- **Network errors** — retried up to 3 times.

After all retries are exhausted, the error is recorded in `last_error` (visible
via `GET /v1/cloudflare/status`) and logged. The bouine purge/ban/refresh
operation itself is **not rolled back** — the local cache and cluster peers are
still invalidated regardless of the CF outcome.

---

## Security notes

- The API token requires only the **"Cache Purge"** permission. Do not use a
  global API key.
- The token is never logged, never included in traces, and never emitted in
  error messages.
- `zone_id` is non-sensitive and safe to commit in values files or config.
- In `async: true` mode, purge goroutines use `context.WithoutCancel` so they
  are not interrupted when the HTTP request that triggered the purge completes.

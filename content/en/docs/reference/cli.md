---
title: "CLI"
weight: 91
description: "bouine command-line interface reference."
---

## Global flags

Since v0.6.0, `--server`, `--token`, and `--format text|json` are persistent
root flags shared by every admin-plane subcommand (`purge`, `ban`, `refresh`,
`config`, `keys`, `cluster`, `status`, `explain`) instead of being redeclared
per command. Values resolve **flag > environment > default**:

| Flag | Environment variable | Default |
|---|---|---|
| `--server` | `BOUINE_SERVER` | `127.0.0.1:9000` |
| `--token` | `BOUINE_TOKEN` | (admin token from config) |
| `--format` | `BOUINE_FORMAT` | `text` |

So scripts can export the connection once and the admin token never has to
be typed on a command line:

```bash
export BOUINE_SERVER=10.0.0.5:9000 BOUINE_TOKEN=my-token BOUINE_FORMAT=json
bouine purge https://example.com/page
```

All admin-plane commands accept `--format json` for machine-friendly output.

## Commands

```bash
bouine serve --config /etc/bouine/config.yaml
bouine config validate <file>
bouine config schema
bouine config get [key]
bouine config set <key> <value> [--dry-run]
bouine config diff [<a.yaml> <b.yaml>]
bouine config reload [--file <path>]
bouine completion bash|zsh|fish
bouine purge <url>
bouine ban host_regex=example.com path_regex=^/api
bouine refresh <url>
bouine keys find <url> [--peer]
bouine keys top [--limit N] [--class miss|stale|revalidated|bypass]
bouine keys recent [--limit N] [--class miss|stale|revalidated|bypass]
bouine explain <url> [--format json]
bouine status [--cluster] [--watch] [--format json]
bouine cluster peers
bouine version
```

## serve

Starts the bouine daemon. Boots every configured listener (HTTP/1.1, admin), wires the pipeline router to the upstream pools, and blocks until SIGINT/SIGTERM.

| Flag | Default | Description |
|------|---------|-------------|
| `--config` | `""` | Path to bouine config YAML file |
| `--log-level` | `info` | Log level (debug, info, warn, error) |
| `--log-format` | `json` | Log format (json, text) |

## config validate

Loads and validates a bouine YAML config file without starting the daemon. Reports validation errors only.

```bash
bouine config validate bouine.yaml
# config is valid
```

## config schema

Prints the JSON schema for the bouine Helm chart values. Useful for editor autocomplete and CI validation.

```bash
bouine config schema > schema.json
```

## config get / set / diff (hot configuration, since v0.6.0)

The hot-config knob surface: change genuinely hot-appliable fields on a
running daemon without a restart.

```bash
bouine config get
# lists every knob with its live value and source:
#   file     — matches the boot config
#   default  — boot config left it to built-in defaults (reported with the effective value)
#   runtime  — drifted from the file at runtime

bouine config set cluster.ban_ttl 45m
# applies a validated point mutation on the running daemon (and fans out to
# every live peer in strong mode), then prints a not-persisted warning:
# runtime overrides are ephemeral and lost at restart.

bouine config set cluster.ban_ttl 45m --dry-run
# validates and reports server-side without touching live state — a dry run
# predicts the real outcome exactly (same validation, same capability errors).

bouine config diff
# knobs a restart would lose (runtime drift)

bouine config diff old.yaml new.yaml
# preview a deploy by diffing two effective configs (durations humanized,
# YAML-key paths)
```

Current knobs (v0.6.x): `cluster.ban_ttl`, `url_ring_sample_rate`, and
per-pool `pool:<name>.health.passive.consecutive_5xx` and
`pool:<name>.health.passive.eject_for` (the latter only when the eject reaper
started at boot). Per-route keys are cold-only and rejected with an
explanation. Unknown keys are rejected with precise errors. Every attempt is
audited (slog key/old→new/dry-run + `bouine_config_hot_sets_total`) and rides
the admin write rate limit. See [Hot configuration](/docs/configuration/#hot-configuration).

## config reload (experimental, since v0.6.0)

Applies a config file to a running daemon without a restart. Requires
`experimental.config_reload: true` in the daemon config — a disabled daemon
answers 503 with the opt-in instructions.

```bash
bouine config reload --file /etc/bouine/config.yaml
# re-parses and validates the file (any failure leaves the running config
# untouched), applies the hot-appliable subset, and reports three sections:
# applied (old → new), unchanged, and NEEDS RESTART (cold-only fields and
# refused knobs, each with its reason). The CLI prints needs_restart loudly.
```

Reload is per-node; rollback is operational (reload the previous git-tracked
file). Audited via `bouine_config_reloads_total{result}`.

## completion

Generates shell completion scripts for bash, zsh, or fish.

```bash
# bash
source <(bouine completion bash)

# zsh
source <(bouine completion zsh)

# fish
bouine completion fish | source
```

Add to your shell profile for persistence.

## purge

Purges a single URL from the cache.

```bash
bouine purge https://example.com/page
```

## ban

Issues a predicate-based ban. The CLI supports `host_regex` and `path_regex`. Surrogate-key bans are available via the [admin API](../api/) only.

```bash
bouine ban host_regex=example.com path_regex=^/api
```

## refresh

Soft-purges a URL (marks it stale, triggers background revalidation on next request).

```bash
bouine refresh https://example.com/page
```

## keys (since v0.6.0)

Cache-key queries: query-oriented verbs, never enumeration. A URL alone cannot
select a Vary variant (that needs request headers), so `find` reports the
resolver's state plus the variant count. There is no object listing in v1:
URL→key is deterministic, key→URL is impossible (the XXH128 key is an
irreversible hash), which is why bouine, like Varnish, has no object listing.

```bash
bouine keys find https://example.com/page          # local state via a side-effect-free store probe
bouine keys find https://example.com/page --peer   # ask the ring owner (GET /v1/peer/keys/find)
bouine keys top --limit 50 --class miss             # most-requested URL prefixes — what the node is missing on
bouine keys recent --limit 50                       # most recently active URL prefixes
```

`top`/`recent` serve the URL ring's sampled non-HIT traffic with a per-cache-result
breakdown (`--class miss|stale|revalidated|bypass`; `hit` is not a filterable class —
the data plane skips HITs before recording). The ring keeps first-three-segment
prefixes, caps at 512 entries. See [Admin API](../api/) for the matching
`GET /v1/keys/find|top|recent` endpoints.

## explain (since v0.6.0)

The structured cache-decision tree for one URL (issue #814): key derivation
(with the query policy's stripped parameter names), route, variant bucket,
the fill path's cacheability verdict, the freshness lifecycle (text mode
renders a 28-cell freshness lifecycle bar; a TTY gets a ~300 ms fill ease-in),
the stored view with live variant enumeration, matched lazy bans with
descriptors, and the ring owner. Read-only by construction: it reads through
the side-effect-free store `Probe` and asks the ban registry for descriptors
instead of applying bans — O(this key), never O(store).

```bash
bouine explain https://example.com/page
bouine explain https://example.com/page --format json
```

Also available as `GET /v1/explain`.

## status (since v0.6.0)

A one-glance node overview (issue #813): node (version, uptime, readiness),
cache (hit ratio, tier fill), origins (per-pool target health), cluster
(gossip peers, peer-fetch telemetry), and insights (dashboard insight rules
evaluated server-side). Default mode is node-local and never touches the
network; `--cluster` performs one peer-metrics round-trip. On a terminal,
`--watch` renders a fullscreen TUI (q/Esc/Ctrl-C quit, r refresh, c toggle
cluster); piped output and `--format json` never take the TUI path.

```bash
bouine status
bouine status --cluster --watch
bouine status --format json
```

Also available as `GET /v1/status`.

## cluster peers

Lists live cluster peers. On a local-mode daemon the admin API answers 503
with the reason ("set listen.cluster to enable the gossip cluster") instead
of a bare 404 (since v0.6.0).

```bash
bouine cluster peers --server 127.0.0.1:9000
```

## version

Prints the bouine version, commit, and build date.

```bash
bouine version
```

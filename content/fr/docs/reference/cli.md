---
title: "CLI"
weight: 91
description: "bouine command-line interface reference."
---

## Commands

```bash
bouine serve --config /etc/bouine/config.yaml
bouine config validate <file>
bouine config schema
bouine completion bash|zsh|fish
bouine purge <url>  --token <token>
bouine ban host_regex=example.com path_regex=^/api  --token <token>
bouine refresh <url>  --token <token>
bouine cluster peers
bouine version
```

`--server` defaults to `127.0.0.1:9000`. All commands default to port 9000 so `--server` is optional when running locally.

## serve

Starts the bouine daemon. Boots every configured listener (HTTP/1.1, HTTP/2, admin), wires the pipeline router to the upstream pools, and blocks until SIGINT/SIGTERM.

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
bouine purge https://example.com/page --token my-token
```

## ban

Issues a predicate-based ban. The CLI supports `host_regex` and `path_regex`. Surrogate-key bans are available via the [admin API](../api/) only.

```bash
bouine ban host_regex=example.com path_regex=^/api --token my-token
```

## refresh

Soft-purges a URL (marks it stale, triggers background revalidation on next request).

```bash
bouine refresh https://example.com/page --token my-token
```

## cluster peers

Lists live cluster peers.

```bash
bouine cluster peers --server 127.0.0.1:9000 --token my-token
```

## version

Prints the bouine version, commit, and build date.

```bash
bouine version
```
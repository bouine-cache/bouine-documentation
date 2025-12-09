---
title: "Install"
weight: 1
description: "Install bouine from Docker Hub, GitHub release binaries, or source, and understand requirements for each method."
---

# Install

## Docker

The fastest way to run bouine is the Docker image:

```bash
docker pull thylong/bouine:latest
docker run --rm -p 8080:80 -p 9000:9000 thylong/bouine:latest
```

The default image includes a minimal config at `/etc/bouine/config.yaml` so the container starts without a volume mount.

> **For production**
>
> Mount your own config at `/etc/bouine/config.yaml`, or use the Helm chart so Kubernetes manages the ConfigMap.

## GitHub Releases

Download a binary from [GitHub Releases](https://github.com/thylong/bouine/releases):

```bash
# Linux amd64
curl -fSL -o bouine https://github.com/thylong/bouine/releases/latest/download/bouine-linux-amd64
chmod +x bouine
./bouine version
```

Binaries are published for:

| OS | Architectures |
|---|---|
| Linux | `amd64`, `arm64` |
| macOS | `amd64`, `arm64` |
| Windows | `amd64`, `arm64` |

## From source

```bash
git clone https://github.com/thylong/bouine.git
cd bouine
make build
./bin/bouine version
```

Requirements:

- Go 1.26+
- `golangci-lint` if you want to run `make lint`
- Docker if you want to build images or run integration tests

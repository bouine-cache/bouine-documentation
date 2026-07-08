---
title: "Install"
weight: 1
description: "Install bouine from Docker Hub, GitHub release binaries, or source, and understand requirements for each method."
---


## Docker

The fastest way to run bouine is the Docker image:

```bash
docker pull bouinecache/bouine:latest
docker run --rm -p 8080:80 -p 9000:9000 bouinecache/bouine:latest
```

The default image includes a minimal config at `/etc/bouine/config.yaml` so the container starts without a volume mount.

> **For production**
>
> Mount your own config at `/etc/bouine/config.yaml`, or use the Helm chart so Kubernetes manages the ConfigMap.

## GitHub Releases

Download the latest release binary from [GitHub Releases](https://github.com/bouine-cache/bouine/releases). The command below is pre-selected for your operating system and CPU architecture — switch the tabs if you need a different target:

{{< install-binary >}}

The one-liner resolves the latest version automatically, so it never goes stale. Binaries are published for:

| OS | Architectures |
|---|---|
| Linux | `amd64`, `arm64` |
| macOS | `amd64`, `arm64` |
| Windows | `amd64`, `arm64` |

> **Verify the download**
>
> Each release ships `SHA256SUMS` (with a cosign signature `SHA256SUMS.sig` and certificate `SHA256SUMS.pem`). Check the checksum after downloading if you need supply-chain assurance.

## From source

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make build
./bin/bouine version
```

Requirements:

- Go 1.26+
- `golangci-lint` if you want to run `make lint`
- Docker if you want to build images or run integration tests

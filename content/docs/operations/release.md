---
title: "Releases"
weight: 80
description: "Maintainer guide for publishing bouine releases, including binaries, Docker Hub images, checksums, SBOMs, and retries."
---

# Releases

Maintainers publish releases with:

```bash
make release TAG=v0.1.0
```

The target prompts for a one-line description, creates a GitHub release, and triggers GitHub Actions.

## What the release workflow publishes

- Binaries for:
  - Linux `amd64`, `arm64`
  - macOS `amd64`, `arm64`
  - Windows `amd64`, `arm64`
- `SHA256SUMS`
- SPDX SBOM attached to the GitHub release
- Docker Hub image `thylong/bouine`
  - `thylong/bouine:<version>`
  - `thylong/bouine:<major>.<minor>`
  - `thylong/bouine:<major>`
  - `thylong/bouine:latest`
- Docker Hub SBOM and provenance attestations

## Required secrets

Set in GitHub repository settings:

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

## Re-trying a failed release

```bash
gh release delete v0.1.0 --yes --cleanup-tag
make release TAG=v0.1.0
```

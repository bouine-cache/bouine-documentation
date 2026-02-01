---
title: "Docker"
weight: 3
description: "Run the official bouine Docker image, mount custom configuration, and build fast multi-architecture images locally."
---


## Run the official image

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  thylong/bouine:latest
```

## Mount a config file

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  -v "$PWD/config.yaml:/etc/bouine/config.yaml:ro" \
  thylong/bouine:latest
```

## Build locally

On Apple Silicon targeting a Linux amd64 cluster:

```bash
docker buildx build --platform linux/amd64 \
  -t thylong/bouine:latest \
  --push .
```

For local testing on your machine:

```bash
docker build -t bouine:dev .
docker run --rm -p 8080:80 -p 9000:9000 bouine:dev
```

The Dockerfile uses `BUILDPLATFORM`/`TARGETARCH` so Go cross-compiles natively instead of running the compiler under QEMU.

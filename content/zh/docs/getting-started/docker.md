---
title: "Docker"
weight: 3
description: "运行 bouine 官方 Docker 镜像，挂载自定义配置，并本地构建快速的多架构镜像。"
---


## 运行官方镜像

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  bouinecache/bouine:latest
```

## 挂载配置文件

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  -v "$PWD/config.yaml:/etc/bouine/config.yaml:ro" \
  bouinecache/bouine:latest
```

## 本地构建

在 Apple Silicon 上构建 Linux amd64 集群：

```bash
docker buildx build --platform linux/amd64 \
  -t bouinecache/bouine:latest \
  --push .
```

在本地机器上测试：

```bash
docker build -t bouine:dev .
docker run --rm -p 8080:80 -p 9000:9000 bouine:dev
```

Dockerfile 使用 `BUILDPLATFORM`/`TARGETARCH` 让 Go 进行原生交叉编译，而非在 QEMU 下运行编译器。

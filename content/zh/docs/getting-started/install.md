---
title: "安装"
weight: 1
description: "从 Docker Hub、GitHub release 二进制文件或源码安装 bouine，了解每种方法的要求。"
---


## Docker

运行 bouine 最快的方式是使用 Docker 镜像：

```bash
docker pull bouinecache/bouine:latest
docker run --rm -p 8080:80 -p 9000:9000 bouinecache/bouine:latest
```

默认镜像包含 `/etc/bouine/config.yaml` 中的最小配置，因此容器无需挂载卷即可启动。

> **生产环境**
>
> 将您自己的配置挂载到 `/etc/bouine/config.yaml`，或使用 Helm chart 让 Kubernetes 管理 ConfigMap。

## GitHub Releases

从 [GitHub Releases](https://github.com/bouine-cache/bouine/releases) 下载最新的 release 二进制文件。以下命令已为您的操作系统和 CPU 架构预选 — 如需其他目标请切换标签页：

{{< install-binary >}}

一键命令会自动解析最新版本，因此永不过期。二进制文件发布于：

| 操作系统 | 架构 |
|---|---|
| Linux | `amd64`, `arm64` |
| macOS | `amd64`, `arm64` |
| Windows | `amd64`, `arm64` |

> **验证下载**
>
> 每个 release 附带 `SHA256SUMS`（含 cosign 签名 `SHA256SUMS.sig` 和证书 `SHA256SUMS.pem`）。如果您需要供应链保证，请在下载后校验校验和。

## 从源码

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make build
./bin/bouine version
```

要求：

- Go 1.26+
- `golangci-lint`（如需运行 `make lint`）
- Docker（如需构建镜像或运行集成测试）

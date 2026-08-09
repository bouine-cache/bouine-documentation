---
title: "Kubernetes"
weight: 4
description: "使用 Helm 将 bouine 部署到 Kubernetes，配置 StatefulSet gossip，验证节点发现，并执行滚动更新。"
---


## 添加 chart 仓库

bouine 发布 Helm chart 仓库到 **`https://charts.bouine.org`**，
索引在 [Artifact Hub](https://artifacthub.io/packages/search?repo=bouine)。
chart 默认从 Docker Hub 拉取 `bouinecache/bouine` 镜像。

```bash
helm repo add bouine https://charts.bouine.org
helm repo update
helm search repo bouine
```

```text
NAME            CHART VERSION   APP VERSION     DESCRIPTION
bouine/bouine   0.1.0           0.1.0           Cloud-native HTTP cache in Go ...
```

## Helm 快速开始

```bash
helm install bouine bouine/bouine \
  --namespace bouine --create-namespace \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app"
```

这会部署一个带 gossip 集群的 StatefulSet、一个 headless Service 用于
节点发现，以及一个 PodDisruptionBudget。

如需从本地检出安装而非仓库，将 Helm 指向 chart 目录：

```bash
helm install bouine deploy/helm/bouine --namespace bouine --create-namespace ...
```

查看 [Helm chart 参考](/docs/configuration/helm/) 了解所有可配置值。

## StatefulSet 要求

多 Pod 集群需要使用 StatefulSet 和带 `publishNotReadyAddresses: true` 的 headless Service。参见 [集群 → Headless Service](/docs/configuration/cluster-modes/#headless-service-kubernetes) 获取完整清单。

## 管理 Token（多 Pod 要求）

所有 Pod **必须共享相同的 `admin.token`**。参见 [认证](/docs/operations/authentication/) 了解配置说明。

## 扩缩容

```bash
kubectl scale statefulset/bouine -n bouine --replicas=3
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

## 滚动更新

```bash
kubectl rollout restart statefulset/bouine -n bouine
kubectl rollout status statefulset/bouine -n bouine
```

bouine 在关闭时标记自身为未就绪并优雅离开 gossip 集群。参见 [Kubernetes 运维](/docs/operations/kubernetes/) 了解零 5xx 滚动更新流程。

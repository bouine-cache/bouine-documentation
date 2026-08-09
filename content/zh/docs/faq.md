---
title: "常见问题"
weight: 99
description: "关于 bouine 的常见问题。"
---

## 通用

### bouine 和 Varnish 有什么区别？

bouine 从第一天起就为 Kubernetes 设计：gossip 集群、Helm chart、Prometheus 指标和 OpenTelemetry 链路追踪都是内置的。Varnish 需要 Varnish Plus 商业版或外部编排来实现集群，并使用 VCL（命令式 DSL）而非声明式 YAML。参见[迁移指南](../guides/varnish-migration/)了解详细对比。

### bouine 和 NGINX 有什么区别？

NGINX 是通用反向代理，缓存是附加功能。bouine 是以缓存为核心的反向代理：每个功能都围绕 RFC 9111 一致性、缓存命中率和失效精度设计。NGINX 使用 `proxy_cache` 指令；bouine 使用每路由声明式缓存策略。参见[迁移指南](../guides/nginx-migration/)了解指令对应关系。

### 可以不用 Kubernetes 运行 bouine 吗？

可以。bouine 作为单个二进制文件运行，配合 YAML 配置文件。集群功能适用于任何基于 DNS 的发现（不限于 Kubernetes headless Service）。Docker Compose 适合开发使用。Kubernetes 是主要目标但不是必需的。

### bouine 需要外部数据库或缓存吗？

不需要。bouine 使用嵌入式 RAM 热层（分片 map）和基于 mmap 的温层（本地磁盘）。不需要 Redis、Memcached 或 etcd。

## 缓存

### 缓存键由什么组成？

主缓存键由以下构成：scheme、host（小写）、path（百分比解码后规范重编码）、query（按字典序排序的参数）和 method（GET 和 HEAD 共享相同键空间）。次键（Vary）从响应 `Vary` 头中列出的请求头派生。参见[架构参考](../architecture/)了解更多详情。

### 如何调试缓存未命中？

检查 `X-Cache` 响应头：`MISS` 表示对象不在缓存中，`BYPASS` 表示缓存被绕过（no-store、no-cache 或路由禁用缓存）。使用 `X-Cache-Source` 查看哪个层提供了响应（`hot`、`warm`、`peer`、`origin`）。

### bouine 支持 WebSocket 吗？

不支持。bouine 透传 WebSocket 升级请求但从不缓存。使用单独的反向代理处理 WebSocket 流量。

### bouine 支持 ESI 吗？

v1.0 不支持。ESI-lite（`<esi:include>`）计划在 v1.1+ 中实现。大多数现代架构更倾向于客户端组合或 CDN 级 ESI。

### bouine 如何处理 Vary 头？

bouine 规范化 `Vary` 并从列出的请求头构建次缓存键。`Vary: *` 禁用缓存。Vary 变体有上限以防止不受控的头变化导致的缓存投毒。

## 集群

### 应该使用哪种集群模式？

- **Strong**（默认）：一致性哈希环，未命中时 peer fetch。每个 URL 由唯一拥有者节点服务时命中率最佳。
- **Eventual**：每个节点独立缓存，仅通过 gossip 传播失效。适合 peer fetch 延迟不可接受的高读取负载。

参见[集群模式指南](../operations/cluster-modes/)了解更多详情。

### 节点加入或离开时会发生什么？

加入时：新节点通过 gossip 通告自己，哈希环重新均衡，新请求路由到新拥有者。新节点冷启动（无键迁移）。离开时：节点排空进行中的请求，退出 gossip 成员，peer 停止路由到它。

### 可以跨多个区域运行 bouine 吗？

v1.0 不支持。多区域联邦（跨集群分层、区域缓存级缓存）计划在 v1.2+ 中实现。

## 配置

### 可以不重启重新加载配置吗？

v1.0 不支持。配置变更通过滚动 Pod（标准 Kubernetes 滚动更新）应用。热重载非破坏性变更已在路线图中。

### bouine 支持配置中的环境变量插值吗？

支持。`${VAR}` 和 `${VAR:-default}` 在 YAML 配置解码前展开。`$$` 转义为字面 `$`。

### 如何使缓存对象失效？

三种机制：
- **Purge**（`POST /v1/purge`）：精确 URL 删除
- **Ban**（`POST /v1/ban`）：基于谓词（host regex、path regex）
- **Refresh**（`POST /v1/refresh`）：软清除，标记为过期并在下次请求时触发重新验证

参见[缓存失效指南](../operations/cache-invalidation/)。

## 性能

### 命中路径的预算是多少？

p50 每请求低于 5 µs CPU，预热后零分配。命中路径在 CI 中通过基准测试门控：`allocs/op == 0`。

### bouine 和 Varnish 在吞吐量上相比如何？

基准测试结果发布在[基准测试指南](../guides/benchmarks/)中。bouine 在标准工作负载上单节点 RPS 等于或超过 Varnish。

### 为什么我的 p99 延迟有尖峰？

检查 GC 暂停（调整 `GOMEMLIMIT` 和 `GOGC`）、工作集超出（热层太小）或重新验证风暴（增大 `jitter_percent`）。Grafana 仪表板有「GC max pause vs HIT p99」面板用于此目的。

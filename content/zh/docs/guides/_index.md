---
title: "指南"
weight: 5
description: "从 Varnish 或 NGINX 迁移、集成模式和容量规划的分步指南。"
---


- [从 Varnish 迁移](varnish-migration/) — VCL vs YAML 并排比较、purge/ban 对等、可观测性对应、行为差异和 FAQ。
- [从 NGINX 迁移](nginx-migration/) — 将 NGINX `proxy_cache` 指令映射到 bouine 配置。
- [反向代理示例](reverse-proxies/) — 在 Caddy、Traefik、HAProxy 和 nginx 前面部署 bouine。
- [容量规划](capacity-planning/) — 规划 hot 和 warm 层大小，选择集群模式和副本，在负载下验证。
- [生产环境检查清单](production-checklist/) — 上线前检查 TLS、资源、集群、缓存、可观测性和 K8s 设置。
- [Service Mesh 兼容性](service-mesh/) — 与 Istio、Linkerd 和 Cilium 一起运行 bouine。
- [基准测试](benchmarks/) — 比较 bouine 与 Varnish、NGINX 和 Envoy 在缓存命中、未命中和混合负载上的方法和结果。

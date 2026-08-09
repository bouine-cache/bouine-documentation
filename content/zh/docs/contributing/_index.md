---
title: "贡献"
weight: 6
description: "贡献者指南，涵盖本地设置、开发流程、提交格式、PR 检查和项目标准。"
---


感谢您改进 bouine。本项目重视准确性、性能和运维清晰度。

## 页面

- [代码指南](codebase/) — 包地图和适合的新手任务。
- [安全](security/) — 漏洞报告和加固说明。

## 前提条件

- Go 1.26+
- `pre-commit`（`pip install pre-commit` 或 `brew install pre-commit`）
- Docker（用于集成测试）

## 设置

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make hooks
make all
```

## 工作流程

1. **定位** — 阅读 `PLAN.md` 和相关包文档。
2. **规划** — 在写代码前先确定测试。
3. **实现** — 最小的有用改动。
4. **验证** — `make all`；如果触及 L1–L6 则 `make bench`。
5. **文档** — 行为变更时更新运行手册或配置文档。

## 提交格式

```text
feat(cache): add negative caching for 404 responses
fix(cluster): retry join until actual peers discovered
docs(runbook): document cluster join retry
```

允许的前缀：`feat`、`fix`、`chore`、`docs`、`refactor`、`test`、`perf`、`build`、`ci`。

## PR 检查清单

- [ ] `pre-commit run --all-files` 通过
- [ ] `make all` 通过
- [ ] 添加或更新测试
- [ ] 缓存变更无 cache-tests 回归
- [ ] 热路径变更无基准测试回归
- [ ] 无密钥、token 或生产主机名

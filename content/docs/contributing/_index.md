---
title: "Contributing"
weight: 6
description: "Contributor guide covering local setup, development workflow, commit format, pull request checks, and project standards."
---


Thanks for improving bouine. This project values correctness, performance, and operational clarity.

## Pages

- [Codebase guide](codebase/) — package map and good first tasks.
- [Security](security/) — vulnerability reporting and hardening notes.

## Prerequisites

- Go 1.26+
- `pre-commit` (`pip install pre-commit` or `brew install pre-commit`)
- Docker (for integration tests)

## Setup

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make hooks
make all
```

## Workflow

1. **Orient** — read `PLAN.md` and the relevant package docs.
2. **Plan** — decide tests before code.
3. **Implement** — smallest useful change.
4. **Verify** — `make all`; `make bench` if touching L1–L6.
5. **Document** — update runbooks or config docs when behavior changes.

## Commit format

```text
feat(cache): add negative caching for 404 responses
fix(cluster): retry join until actual peers discovered
docs(runbook): document cluster join retry
```

Allowed prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`.

## PR checklist

- [ ] `pre-commit run --all-files` passes
- [ ] `make all` passes
- [ ] Tests added or updated
- [ ] No cache-tests regression for cache changes
- [ ] No benchmark regression for hot-path changes
- [ ] No secrets, tokens, or production hostnames

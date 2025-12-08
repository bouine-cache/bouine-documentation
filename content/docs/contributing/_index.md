---
title: "Contributing"
weight: 6
bookCollapseSection: false
---

# Contributing

## Prerequisites

- Go 1.26+
- `pre-commit` (mandatory — `pip install pre-commit` or `brew install pre-commit`)
- Docker (for integration tests)

## Setup

```bash
git clone https://github.com/thylong/bouine.git
cd bouine
make hooks       # install pre-commit hooks (required)
make all         # lint + test + build
```

## Workflow

1. **Orient** — read `PLAN.md` for the roadmap, `AGENTS.md` for the rules
2. **Plan** — identify the layers touched, write tests first
3. **Implement** — smallest reasonable change, follow existing patterns
4. **Verify** — `make all` minimum; `make bench` if touching L1–L6
5. **Document** — update godoc, runbook, decisions if needed
6. **PR** — conventional commit message, pass all hooks

## Commit format

[Conventional Commits](https://www.conventionalcommits.org/):

```
feat(cache): add negative caching for 404 responses
fix(cluster): retry join until actual peers discovered
docs(runbook): update lifecycle for cluster join retry
refactor(admin): replace hand-rolled hash with BuildKeyFromURL
perf(cache): zero-alloc ParseCacheControl
test(conformance): wire cache-tests harness
```

Allowed prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`.

## PR checklist

- [ ] `pre-commit run --all-files` passes
- [ ] `make all` green
- [ ] Tests added/updated; coverage not reduced
- [ ] If hot path: zero-alloc benchmark proves it
- [ ] If cache logic: conformance score not regressed
- [ ] Godoc on exported identifiers
- [ ] No secrets, no PII

## Code standards

- No `panic` outside `main`
- No `init` functions that do work
- Every public function that does I/O takes `context.Context` as first argument
- No global mutable state — the daemon is a single `Engine` struct
- Errors wrap with `%w`; never log + return (pick one)
- Cite RFC clauses in comments when behavior is spec-driven

## Performance rules

- Hit-path budget: <5 µs CPU, 0 allocs/op
- No `fmt.Sprintf`, `errors.New`, map growth, interface boxing on hot loops
- Pool buffers via `sync.Pool`; always reset on put
- Body streaming for >64 KiB — never buffer in RAM

## Testing

- Table-driven unit tests, `-race` always on
- Coverage: ≥85% default, ≥95% for `cache` and `storage`
- Fuzz tests for header parsing, Cache-Control tokenizer, Vary canonicalisation
- Benchmarks gated in CI — regressions block merge

## Security

Report vulnerabilities via [GitHub private advisory](https://github.com/thylong/bouine/security/advisories/new) or email `security@bouine.dev`. See [SECURITY.md](https://github.com/thylong/bouine/blob/main/SECURITY.md).

## License

[Apache License 2.0](https://github.com/thylong/bouine/blob/main/LICENSE). By contributing, you agree your contributions are licensed under the same terms.

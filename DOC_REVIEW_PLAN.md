# Documentation Review & Update Plan

Comparison of `bouine-documentation` against `bouine` implementation (v0.3.7 / [Unreleased]).

---

## 1. Outdated — Documented but changed in implementation

### 1.1 Config reload via admin API (CRITICAL)

**Affected files:**
- `content/en/docs/operations/lifecycle.md` — entire "Config reload" section (`Via admin API`, `Via dashboard`, `What is reloaded`, `Reload failure`)
- `content/en/docs/reference/api.md` — `POST /v1/config/reload` endpoint listed in endpoint table
- `content/en/docs/reference/go-sdk.md` — `Reload` method documented in SDK reference

**What changed:** The `[Unreleased]` CHANGELOG confirms removal of:
- `POST /v1/config/reload` admin endpoint
- Dashboard "Reload config" button and `ReloadFn` field
- `bouineapi.Client.Reload` and `ReloadResult` from the Go SDK

Config is now sourced from version control and applied by **rolling the pod**. No live reload.

**Action:** Remove all config-reload documentation. Replace with a note that config changes require a rolling pod restart. Remove the Reload method from the Go SDK reference. Update the admin API endpoint table.

### 1.2 "full" cluster mode removed (CRITICAL)

**Affected files:**
- `content/en/docs/operations/cluster-modes.md` — documents three modes (strong, eventual, **full**) with per-mode expectations, memory/bandwidth budgets, and switching procedures for full mode
- `content/en/docs/configuration/cluster-modes.md` — may reference full mode
- `content/en/docs/architecture/_index.md` — may reference full mode
- `content/en/docs/faq.md` — "What cluster mode should I use?" may list full mode

**What changed:** The implementation (`internal/config/config.go`, `internal/cluster/cluster.go`) only supports two modes: `strong` and `eventual`. The `full` mode constant does not exist. The config loader rejects `"full"` as an invalid mode (`loader_test.go:532`). The CHANGELOG v1.0.0 mentions "full-replication consistency mode" as a historical feature, and v0.1.11 mentions "full-mode replication reconciliation", but it has been removed.

**Action:** Remove all references to "full" mode. Remove the `full` mode sections from operations/cluster-modes.md (per-mode expectations, memory/bandwidth budget, switching procedures from/to full). Update FAQ. Update architecture docs. Update any diagrams or tables that list three modes.

### 1.3 Dashboard views outdated

**Affected files:**
- `content/en/docs/operations/dashboard.md` — documents 5 views: Overview, Routes, Cluster, Invalidation, Config

**What changed:** The implementation (`internal/dashboard/handler.go`) has **7 views**:
1. Overview
2. **Performance** (new — not documented)
3. Routes
4. Cluster
5. Invalidation
6. Config
7. **Insights** (new — not documented, 42 rule-based operational insights)

**Action:** Add "Performance" and "Insights" views to dashboard docs. Remove any mention of a "Reload config" button from the Config view description.

### 1.4 Admin API endpoint table incomplete

**Affected file:**
- `content/en/docs/reference/api.md`

**What changed:** The implementation (`internal/admin/server.go`) has these endpoints not in the docs:
- `GET /v1/stats` — runtime stats
- `GET /v1/config` — read-only config viewer
- `GET /v1/debug/cachecheck?url=...` — cache debug endpoint
- `GET /v1/peer/metrics` — peer metrics (auth-exempt)
- `GET /debug/pprof/*` — pprof endpoints (when `pprof_enabled`)

And this endpoint must be **removed** from docs:
- ~~`POST /v1/config/reload`~~ (removed)

**Action:** Remove the reload endpoint. Add the missing endpoints with their purpose, auth requirements, and example responses.

### 1.5 Helm chart version

**Affected files:**
- `content/en/docs/configuration/helm.md`
- `content/en/docs/getting-started/kubernetes.md`

**What changed:** Chart version is now `0.3.7` / appVersion `0.3.7`. Docs may reference older versions or lack version-specific information.

**Action:** Verify version references are current. Add mention of preconfigured value files (`values-dev.yaml`, `values-ha.yaml`, `values-production.yaml`) which exist in the Helm chart but are not documented.

---

## 2. Missing — In implementation but not documented

### 2.1 Configuration fields not documented

**Affected file:** `content/en/docs/configuration/_index.md` (field reference section)

These config fields exist in `internal/config/config.go` but are not in the docs:

| Field | Section | Description |
|-------|---------|-------------|
| `listen.max_connections` | listen | Max concurrent connections (FD exhaustion protection, added v0.3.4) |
| `listen.tcp_fast_open` | listen | TCP_FASTOPEN socket option |
| `listen.tcp_defer_accept` | listen | TCP_DEFER_ACCEPT socket option |
| `listen.reuse_port` | listen | SO_REUSEPORT socket option |
| `listen.cluster` | listen | Cluster gossip listen address (default `:8443`) |
| `storage.hot_mmap_slab` | storage | Enable mmap slab allocator for hot body bytes (reduces GC, v0.3.7) |
| `storage.segment_cache_size` | storage | Warm tier segment cache size |
| `storage.tombstone_queue_size` | storage | Tombstone queue depth |
| `storage.tombstone_drain_interval` | storage | Tombstone drain interval |
| `storage.checkpoint_wal_threshold` | storage | WAL threshold for checkpoint trigger |
| `storage.compact_startup_delay` | storage | Delay before startup compaction |
| `gogc` | root | Go GC percentage (default 100, -1 disables percentage-based trigger) |
| `url_ring_sample_rate` | root | URL ring sampling rate for dashboard |
| `admin.pprof_enabled` | admin | Enable pprof debug endpoints |
| `admin.drain_duration` | admin | Drain duration for graceful shutdown |
| `admin.max_batch_size` | admin | Max batch size for purge/batch (default 1000) |
| `admin.rate_limit_per_second` | admin | Rate limit on write endpoints |
| `connect.max_connections` | upstream_pools.connect | Max connections per pool |
| `connect.response_header_timeout` | upstream_pools.connect | Response header timeout |

**Action:** Add these fields to the config reference. Keep descriptions concise — one line each where possible. Do not create new pages; add to existing field reference.

### 2.2 Response headers not documented

**Affected file:** `content/en/docs/reference/headers.md`

Only 3 headers are documented (X-Cache, Age, X-Cache-Source). Missing:

| Header | Purpose |
|--------|---------|
| `X-Bouine-Route` | Route label set by router on every request |
| `Warning: 110` | Set on stale responses per RFC 9111 |
| `Bouine-Method` | Original cached request method (internal/peer context) |

Note: Other internal headers (`X-Bouine-Host`, `X-Bouine-Path`, `Bouine-Hop`, `X-Bouine-Cluster-Version`, `Bouine-Issuer`, `Bouine-Seq`, `Bouine-Issued-At`) are internal/peer-RPC headers not user-facing. Document only the user-visible ones.

**Action:** Add X-Bouine-Route and Warning: 110 to headers.md. Mention Bouine-Method in context of peer-fetch if relevant.

### 2.3 Prometheus metrics not documented

**Affected file:** `content/en/docs/operations/monitoring.md`

Missing metrics:
- `bouine_http_smuggling_rejected_total` — HTTP request smuggling rejection counter
- `bouine_warm_store_self_heals_total` — warm tier self-heal counter
- `bouine_vary_cap_hits_total` — may be documented, verify

**Action:** Add missing metrics to the monitoring reference. Add a note about HTTP smuggling detection.

### 2.4 Insights engine not documented

**Affected file:** `content/en/docs/operations/dashboard.md`

The dashboard has an Insights page with 42 rule-based operational insights across categories: Cache, Anomaly, Upstream, CDN, Cluster, Config. Not mentioned at all in docs.

**Action:** Add a brief "Insights" view section to dashboard.md. Do not enumerate all 42 rules — describe the categories and give 2-3 example insights. The dashboard itself shows them dynamically.

### 2.5 HTTP smuggling detection not documented

The h1parser (`internal/server/h1parser/parser.go`) includes request smuggling detection and the `h1_fast_path` experimental feature depends on it. The `bouine_http_smuggling_rejected_total` metric tracks rejections.

**Action:** Mention in the experimental features page (h1_fast_path section) that the fast path includes smuggling detection and rejected requests are counted in the metric. One paragraph, no new page.

### 2.6 POST response caching (RFC 9111 §4.3.1) not documented

The cache handler (`internal/cache/handler.go`) stores successful POST responses under the GET key when cacheable with explicit freshness and Content-Location matching. Also, POST/PUT/DELETE invalidates Content-Location and Location URLs per RFC 9111 §4.4.

**Action:** Add a brief note to the cache-policy page about POST response caching and Content-Location/Location invalidation behavior. One paragraph.

### 2.7 Helm chart preconfigured value files

**Affected file:** `content/en/docs/configuration/helm.md`

The Helm chart ships with `values-dev.yaml`, `values-ha.yaml`, and `values-production.yaml` but the docs only reference the base `values.yaml`.

**Action:** Add a short section mentioning these preconfigured profiles and how to use them (`-f values-ha.yaml`). Do not reproduce their content — link to the chart.

### 2.8 Helm chart templates not fully documented

**Affected file:** `content/en/docs/configuration/helm.md`

These Helm templates exist but may not be documented:
- `hpa.yaml` — HorizontalPodAutoscaler
- `pdb.yaml` — PodDisruptionBudget
- `networkpolicy.yaml` — NetworkPolicy for admin port isolation
- `podmonitor.yaml` / `servicemonitor.yaml` / `prometheusrule.yaml` — Prometheus Operator CRDs

**Action:** Add these to the Helm values reference under their respective sections. Brief mention of what each enables, not full template documentation.

---

## 3. Doesn't exist anymore — Remove from docs

### 3.1 Remove config reload documentation

- Remove "Config reload" section from `operations/lifecycle.md`
- Remove `POST /v1/config/reload` from `reference/api.md`
- Remove `Reload` method from `reference/go-sdk.md`
- Remove "Reload config" button from `operations/dashboard.md`

### 3.2 Remove "full" cluster mode

- Remove all "full" mode sections from `operations/cluster-modes.md`
- Remove full mode from any comparison tables, diagrams, or switching procedures
- Remove full mode references from `architecture/_index.md`
- Remove full mode from FAQ if present

### 3.3 Remove empty placeholder pages

These pages are empty and serve no purpose:
- `content/en/docs/resources.md` (empty, sitemap_exclude: true)
- `content/en/docs/guides/example.md` (empty, sitemap_exclude: true)
- `content/en/docs/reference/example.md` (empty, sitemap_exclude: true)

**Action:** Delete these files and their translations. They add noise to the content tree without value.

---

## 4. Can be improved

### 4.1 Headers reference is too sparse

`reference/headers.md` only documents 3 headers. Even after adding the missing ones (section 2.2), consider adding a table format with columns: Header, Values, Set on, Description. This improves scannability without growing content.

### 4.2 Architecture page — mmap slab allocator

The hot tier now uses mmap for body bytes (v0.3.7) to reduce GC pressure. The architecture page mentions SIEVE eviction but not the mmap slab allocator. Add one sentence in the "Eviction" or "Performance" subsection.

### 4.3 Go SDK — version bump to v2

The CHANGELOG notes the SDK surface moves to v2.0 due to the Reload removal. The Go SDK docs should reflect the import path / version change if applicable. Verify the module path in `go.mod` and update the installation instructions.

### 4.4 FAQ updates

- "Can I reload config without restarting?" → answer must change to "No, config changes require a rolling pod restart"
- "What cluster mode should I use?" → remove "full" mode from the answer if present
- Consider adding: "Does bouine detect HTTP request smuggling?" → Yes, the fast-path parser includes smuggling detection

### 4.5 Production checklist

- Remove "config reload" from the operations checklist if present
- Add "enable pprof only in debug" if not already there
- Add GOMEMLIMIT tuning reference (may already be there, verify)

### 4.6 CLI reference

The CLI reference (`reference/cli.md`) documents commands. Verify:
- `serve` flags: `--config`, `--log-level`, `--log-format` — all present in implementation
- `config schema` command — prints embedded Helm values JSON schema. Verify this is documented.
- No new commands to add (all 10 commands appear documented)

### 4.7 Compare page

The `/compare/` page compares bouine against Envoy, NGINX, HAProxy, Varnish, Caddy. Verify the comparison data is still accurate given the feature changes (e.g., "full" mode removal, config reload removal).

---

## 5. Translation plan (French & Chinese)

### 5.1 Current state

| Metric | French | Chinese |
|--------|--------|---------|
| Total files | 46 | 46 |
| Fully translated | 16 (35%) | 14 (30%) |
| Title-only translated | 20 (43%) | 23 (50%) |
| Completely untranslated | 10 (22%) | 9 (20%) |
| Missing files | 9 | 9 |
| i18n UI strings | ✅ Complete | ✅ Complete |

### 5.2 Missing files (both FR and ZH)

These 9 files exist in EN but not in FR or ZH:
1. `404.md` — 404 error page
2. `privacy.md` — Privacy policy
3. `tags/_index.md` — Tags listing
4. `blog/_index.md` — Blog index
5. `categories/_index.md` — Categories listing
6. `contributors/_index.md` — Contributors page
7. `docs/resources.md` — Empty placeholder (will be deleted, see 3.3)
8. `docs/guides/example.md` — Empty placeholder (will be deleted, see 3.3)
9. `docs/reference/example.md` — Empty placeholder (will be deleted, see 3.3)

**Action:** After deleting the 3 empty placeholders from EN, 6 files remain missing. Create translated versions of the 6 non-doc files (404, privacy, tags, blog, categories, contributors). These are structural pages with minimal text.

### 5.3 Translation workflow

**Phase 1: Update English docs first**
Complete all changes in sections 1-4 above. Do not translate until English is stable.

**Phase 2: Sync FR and ZH file trees**
- Delete the 3 empty placeholder files from FR and ZH if they exist (they don't — they were never created)
- Create the 6 missing structural pages in FR and ZH
- Remove deleted content (config reload, full mode) from existing FR and ZH files

**Phase 3: Translate updated content**
For each file that was modified in English:

| Priority | Files | FR status | ZH status |
|----------|-------|-----------|-----------|
| P0 | `operations/lifecycle.md` | Title only | Title only |
| P0 | `operations/cluster-modes.md` | Title only | Title only |
| P0 | `operations/dashboard.md` | Title only | Title only |
| P0 | `reference/api.md` | Title only | Title only |
| P0 | `reference/go-sdk.md` | Untranslated | Untranslated |
| P0 | `reference/headers.md` | Fully translated | Fully translated |
| P1 | `configuration/_index.md` | Fully translated | Fully translated |
| P1 | `operations/monitoring.md` | Title only | Title only |
| P1 | `configuration/experimental.md` | Title only | Title only |
| P1 | `configuration/cache-policy.md` | Title only | Title only |
| P2 | `configuration/helm.md` | Untranslated | Untranslated |
| P2 | `getting-started/kubernetes.md` | Fully translated | Fully translated |
| P2 | `docs/faq.md` | Untranslated | Fully translated |
| P2 | `architecture/_index.md` | Fully translated | Fully translated |
| P3 | All other modified files | Various | Various |

**Phase 4: Translate remaining untranslated content**
After the updated content is translated, address the backlog:
- FR: 10 completely untranslated files + 20 title-only files
- ZH: 9 completely untranslated files + 23 title-only files

**Translation approach:**
- Use the English source as the single source of truth
- Translate front matter (title + description) and body content
- Keep code blocks, config examples, CLI commands, and header names in English (standard practice for technical docs)
- Keep technical terms in English when no standard translation exists (e.g., "SIEVE eviction", "singleflight", "mmap")
- FR-specific: use proper French typographic conventions (spaces before colons, guillemets « »)
- ZH-specific: keep English technical terms inline as is already done in the i18n files

### 5.4 Translation priority order

1. **P0 — Breaking changes** (config reload removal, full mode removal): Must be translated immediately to avoid misleading users. 5 files.
2. **P1 — New features** (dashboard views, new metrics, new config fields): Should be translated next. 4 files.
3. **P2 — Reference updates** (Helm chart, headers, FAQ, architecture): Important for completeness. 4 files.
4. **P3 — Backlog** (all remaining untranslated content): Ongoing effort. ~30 files per language.

---

## 6. Execution order

| Step | Task | Files touched (EN) | Estimated effort |
|------|------|---------------------|-----------------|
| 1 | Remove config reload docs | lifecycle.md, api.md, go-sdk.md, dashboard.md | Small |
| 2 | Remove "full" cluster mode | operations/cluster-modes.md, architecture/_index.md, faq.md | Medium |
| 3 | Add missing dashboard views | operations/dashboard.md | Small |
| 4 | Add missing admin API endpoints | reference/api.md | Small |
| 5 | Add missing config fields | configuration/_index.md | Medium |
| 6 | Add missing headers | reference/headers.md | Small |
| 7 | Add missing metrics | operations/monitoring.md | Small |
| 8 | Add insights engine to dashboard | operations/dashboard.md | Small |
| 9 | Add POST caching & Content-Location invalidation | configuration/cache-policy.md | Small |
| 10 | Add smuggling detection note | configuration/experimental.md | Small |
| 11 | Add Helm preconfigured profiles & templates | configuration/helm.md | Small |
| 12 | Add mmap slab to architecture | architecture/_index.md | Tiny |
| 13 | Update FAQ answers | faq.md | Small |
| 14 | Update Go SDK (remove Reload, v2 note) | reference/go-sdk.md | Small |
| 15 | Delete empty placeholder pages | resources.md, guides/example.md, reference/example.md | Tiny |
| 16 | Verify compare page accuracy | compare/_index.md | Small |
| 17 | Verify production checklist | guides/production-checklist.md | Small |
| 18 | Verify CLI reference | reference/cli.md | Tiny |
| 19 | **Sync FR/ZH file trees** | FR + ZH content dirs | Small |
| 20 | **Translate P0 changes (FR)** | 5 files | Medium |
| 21 | **Translate P0 changes (ZH)** | 5 files | Medium |
| 22 | **Translate P1 changes (FR)** | 4 files | Medium |
| 23 | **Translate P1 changes (ZH)** | 4 files | Medium |
| 24 | **Translate P2-P3 backlog (FR)** | ~30 files | Large |
| 25 | **Translate P2-P3 backlog (ZH)** | ~31 files | Large |

---

## 7. What NOT to do

- **Do not create new documentation pages** — all updates fit within existing pages
- **Do not document internal/peer-RPC headers** (`Bouine-Hop`, `Bouine-Issuer`, `Bouine-Seq`, etc.) — these are implementation details, not user-facing
- **Do not enumerate all 42 insight rules** — the dashboard shows them dynamically; describe categories only
- **Do not document pprof endpoints in detail** — a one-line mention that `pprof_enabled` exposes `/debug/pprof/*` is sufficient
- **Do not add a version history/changelog page** — the CHANGELOG lives in the bouine repo, not the docs repo
- **Do not expand the comparison page** — only verify accuracy of existing data
- **Do not translate code blocks, config examples, or CLI commands** — keep these in English in all languages

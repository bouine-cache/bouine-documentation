# Plan: Documentation Versioning for bouine.org

## Goal

Add a version dropdown to the docs navbar (like [docs.gofiber.io](https://docs.gofiber.io)) so users can browse documentation scoped to a specific minor/major version of bouine (e.g. `v0.4.x`, `v0.3.x`, `v0.2.x`).

---

## Current State

| Aspect | Status |
|---|---|
| Doks theme versioning params | `docsVersioning = false`, `docsVersion = "1.0"` (theme defaults, never overridden) |
| Version dropdown in `header.html` | Custom dropdown exists but disabled; links point to non-existent `/docs/0.2/prologue/...` paths |
| Versioned content directories | None — all docs live at `content/<lang>/docs/` (en, fr, zh) |
| `versions.json` or version data | None (`data/` is empty) |
| Build/deploy | Single Hugo build → Docker image → k3s; no version orchestration |
| bouine release versions | `v0.0.9` → `v0.4.3` (minor series: 0.0, 0.1, 0.2, 0.3, 0.4; next: 0.5) |
| Languages | en (default, root), fr (`/fr/`), zh (`/zh/`) — all share identical doc structure |

---

## Research: How the Hugo Ecosystem Does Versioning

### Three idiomatic approaches in the Hugo community

| Approach | How it works | Used by | Pros | Cons |
|---|---|---|---|---|
| **Multi-build** (rendered site) | Run `hugo` N times, once per version, outputting to subdirectories (`public/v0.3/`, etc.) | Go Fiber (Docusaurus-style), many Hugo sites | Simple, each build is isolated, themes/layouts can evolve per version | Requires orchestration script |
| **Branch-per-version** (external) | Each version is a git branch; a tool clones all branches and assembles a single build | Kubernetes docs (subdomain-per-version variant), `hugo-multiversion` tool | Clean cherry-picking of fixes across branches, git-native | More complex CI; external tooling needed |
| **Module mounts** (single build) | Import each version's content as a Hugo Module at a specific git tag; mount into `content/v0.3/` etc. | Hugo docs site concept, Grafana docs | Single build, everything in one repo, Go module versioning | Most complex setup; requires Go module infrastructure; content must be a separate module |

### What the Doks theme actually provides

The Doks theme's versioning support is **minimal**: two config params (`docsVersioning`, `docsVersion`) that inject a version prefix into URLs on the homepage CTA buttons. There is **no** version-switcher dropdown partial, **no** multi-build orchestration, and **no** content-mounting logic in the theme itself. The versioning recipe page on getdoks.org says "New setup — available with the next release" and is currently empty.

The custom `header.html` in this repo added a hardcoded dropdown (not from the theme) — but it points to non-existent paths.

### What Go Fiber does

Go Fiber uses **Docusaurus** (not Hugo). It builds each version separately and serves them at subdirectories (`/next/`, root for latest). The dropdown is a Docusaurus built-in component. This is the multi-build approach, adapted to Docusaurus.

### What Kubernetes docs do

Kubernetes uses Hugo with the Docsy theme. They use **branch-per-version** with **subdomain-per-version** deployment (`v1-35.docs.kubernetes.io`). Each release branch (`release-1.35`) is deployed independently via Netlify branch deploys. A `[[params.versions]]` array in `hugo.toml` drives the version dropdown.

---

## Recommended Approach: Multi-Build with Git Worktrees

### Why this approach (and not the alternatives)

| Criterion | Multi-build (worktrees) | Module mounts | Branch + subdomain |
|---|---|---|---|
| Complexity | Medium — one shell script | High — Go modules, separate content repos | High — DNS + reverse proxy per version |
| URL structure | `/v0.3/docs/...` (subdirectory) | `/v0.3/docs/...` (subdirectory) | `v0-3.docs.bouine.org/docs/...` (subdomain) |
| Fits existing k3s deploy | Yes — single static site | Yes — single build | No — needs per-version ingress routing |
| Fits existing single-repo structure | Yes — branches in same repo | No — content must be a separate Go module | Yes — but needs infra changes |
| Search index per version | Automatic (each build is isolated) | Requires careful mount config | Automatic (separate sites) |
| Language support (fr, zh) | Automatic (each build has all langs) | Requires mounts per language per version | Automatic |
| Backport fixes to old versions | Git cherry-pick between branches | Re-tag content module | Git cherry-pick between branches |
| Build time | N × single-build time (~40s for 4 versions) | Single build (faster) | N × single-build time |
| Theme/layout evolution per version | Full freedom (each branch has its own layouts) | Shared layouts (one build) | Full freedom |

**Decision:** Multi-build with `git worktree` is the most pragmatic approach for this project. It:
- Works within the existing single-repo, single-Docker-image, single-k3s-deployment setup
- Produces subdirectory-based URLs (`/v0.3/docs/...`) matching the Go Fiber UX
- Requires only a shell script — no Go module infrastructure, no DNS changes
- Keeps each version's build fully isolated (search index, llms.txt, layouts all correct)
- Allows cherry-picking fixes to old version branches

**Module mounts** would be more elegant for a single-build solution but requires restructuring content into a separate Go module repo — a significant architectural change for limited benefit at this scale (4 versions, ~45 pages each).

---

## Design

### URL Structure

```
https://bouine.org/                        ← latest (v0.4.x), built from main branch
https://bouine.org/v0.3/docs/...           ← v0.3.x docs snapshot
https://bouine.org/v0.2/docs/...           ← v0.2.x docs snapshot
https://bouine.org/v0.1/docs/...           ← v0.1.x docs snapshot
https://bouine.org/fr/                      ← latest, French
https://bouine.org/fr/v0.3/docs/...        ← v0.3.x, French  (if languages are preserved)
```

> **Language + version interaction:** Each version build includes all languages. The `baseURL` for v0.3 is `https://bouine.org/v0.3/`, so French content at `content/fr/` renders to `https://bouine.org/v0.3/fr/docs/...`. The version dropdown links use `relLangURL` so they respect the current language.

### Branch Strategy

- `main` — always builds the **latest** version (deployed to site root)
- `docs-v0.3` — snapshot of `main` at tag `v0.3.7` (last patch of v0.3 series)
- `docs-v0.2` — snapshot of `main` at tag `v0.2.7`
- `docs-v0.1` — snapshot of `main` at tag `v0.1.25`

When v0.5.0 is released:
1. Create `docs-v0.4` from `main` at that point
2. Bump `docsVersion` to `0.5` on `main`
3. Add `0.4` to the archived versions list

### Build Orchestration

```
scripts/build-versioned.sh
  ├─ hugo --environment production  →  public/           (latest, from main)
  ├─ git worktree add tmp/v0.3 docs-v0.3
  │   └─ cd tmp/v0.3 && hugo --environment v0.3  →  public/v0.3/
  ├─ git worktree add tmp/v0.2 docs-v0.2
  │   └─ cd tmp/v0.2 && hugo --environment v0.2  →  public/v0.2/
  ├─ git worktree add tmp/v0.1 docs-v0.1
  │   └─ cd tmp/v0.1 && hugo --environment v0.1  →  public/v0.1/
  └─ cleanup worktrees
```

Each version build uses a Hugo environment config (`config/v0.3/hugo.toml`) that sets:
- `baseURL = "https://bouine.org/v0.3/"`
- `docsVersion = "0.3"`

### Version Dropdown

Driven by `data/versions.json` (single source of truth, same file on all branches):

```json
[
  { "version": "0.4", "label": "v0.4.x", "latest": true, "path": "" },
  { "version": "0.3", "label": "v0.3.x", "path": "/v0.3" },
  { "version": "0.2", "label": "v0.2.x", "path": "/v0.2" },
  { "version": "0.1", "label": "v0.1.x", "path": "/v0.1" }
]
```

The dropdown partial iterates over this data. The current version is highlighted based on `site.Params.doks.docsVersion`. Links use `relLangURL` to preserve the language prefix.

---

## Implementation Plan

### Phase 1: Version Dropdown UI (main branch)

> Can be done and deployed immediately, even before any snapshot branches exist. The dropdown will show the current version as "latest" and list placeholder entries for older versions (which will 404 until snapshots are created in Phase 3).

#### 1.1 Create `data/versions.json`

```json
[
  { "version": "0.4", "label": "v0.4.x", "latest": true, "path": "" },
  { "version": "0.3", "label": "v0.3.x", "path": "/v0.3" },
  { "version": "0.2", "label": "v0.2.x", "path": "/v0.2" },
  { "version": "0.1", "label": "v0.1.x", "path": "/v0.1" }
]
```

#### 1.2 Enable versioning in `hugo.toml`

Add to `[params.doks]`:
```toml
docsVersioning = true
docsVersion = "0.4"
docsLatestVersion = "0.4"
```

#### 1.3 Rewrite the version dropdown in `layouts/_partials/header/header.html`

Replace the current hardcoded dropdown (the block gated by `{{ if eq site.Params.doks.docsVersioning true }}`) with:

```html
{{ if eq site.Params.doks.docsVersioning true -}}
<div class="dropdown mt-1 order-lg-3">
  <button class="btn btn-dropdown dropdown-toggle" id="doks-versions"
          data-bs-toggle="dropdown" aria-expanded="false"
          data-bs-display="static" aria-label="Toggle version menu">
    <span class="d-none">Version:</span> v{{ site.Params.doks.docsVersion }}.x
    <span class="dropdown-caret">
      <svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-chevron-down" width="20" height="20" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path stroke="none" d="M0 0h24v24H0z" fill="none"></path>
        <path d="M6 9l6 6 6-6"></path>
      </svg>
    </span>
  </button>
  <ul class="dropdown-menu dropdown-menu-lg-end me-lg-2 shadow rounded border-0" aria-labelledby="doks-versions">
    {{ range site.Data.versions -}}
      {{ $isCurrent := eq .version site.Params.doks.docsVersion -}}
      <li>
        <a class="dropdown-item{{ if $isCurrent }} active{{ end }}"
           href="{{ if eq .path "" }}{{ relLangURL "" }}{{ else }}{{ .path }}/{{ relLangURL "" }}{{ end }}"
           {{ if $isCurrent }}aria-current="true"{{ end }}>
          {{ .label }}{{ if .latest }} <span class="badge bg-primary ms-1">latest</span>{{ end }}
        </a>
      </li>
    {{ end -}}
    <li><hr class="dropdown-divider"></li>
    <li><a class="dropdown-item" href="https://github.com/bouine-cache/bouine/releases">All releases</a></li>
  </ul>
</div>
{{ end -}}
```

#### 1.4 Add "not latest" banner for archived versions

Create `layouts/_partials/header/version-banner.html`:
```html
{{ if and (eq site.Params.doks.docsVersioning true) (ne site.Params.doks.docsVersion site.Params.doks.docsLatestVersion) -}}
<div class="alert alert-warning mb-0 rounded-0 text-center py-2">
  You are reading documentation for bouine <strong>v{{ site.Params.doks.docsVersion }}.x</strong> — not the latest version.
  <a href="{{ relLangURL "" }}" class="alert-link">View latest →</a>
</div>
{{ end -}}
```

Include it in `header.html` just before the `<header class="navbar">` tag:
```html
{{ partial "header/version-banner.html" . }}
```

#### 1.5 Fix homepage CTA links for versioning

In `layouts/home.html`, update CTA links to respect `docsVersioning`:
```html
href="/docs/{{ if site.Params.doks.docsVersioning }}{{ site.Params.doks.docsVersion }}/{{ end }}getting-started/install/"
```

(The theme's `home.html` already does this; the custom `layouts/home.html` override needs to match.)

---

### Phase 2: Per-Version Hugo Environments

#### 2.1 Create environment config files

Hugo supports per-environment config overrides via `config/<environment>/`.

**`config/production/hugo.toml`** (latest build, already the default):
```toml
baseURL = 'https://bouine.org/'

[params.doks]
  docsVersioning = true
  docsVersion = "0.4"
  docsLatestVersion = "0.4"
```

**`config/v0.3/hugo.toml`**:
```toml
baseURL = 'https://bouine.org/v0.3/'

[params.doks]
  docsVersioning = true
  docsVersion = "0.3"
  docsLatestVersion = "0.4"
```

**`config/v0.2/hugo.toml`** and **`config/v0.1/hugo.toml`**: same pattern with appropriate version numbers.

> **Note:** The `config/` directory overrides are merged with the root `hugo.toml`. We only specify the deltas (baseURL + doks params). Everything else (languages, menus, outputs, theme) is inherited.

#### 2.2 Create build script

**`scripts/build-versioned.sh`**:
```bash
#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-public}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Archived versions to build (must match data/versions.json entries without "latest")
VERSIONS=("v0.3" "v0.2" "v0.1")

echo "▶ Building latest version → ${OUTPUT_DIR}/"
rm -rf "$OUTPUT_DIR"
(cd "$REPO_ROOT" && hugo --environment production --minify --gc --destination "$OUTPUT_DIR")

for ver in "${VERSIONS[@]}"; do
  branch="docs-${ver}"
  echo "▶ Building ${ver} from branch '${branch}' → ${OUTPUT_DIR}/${ver}/"

  worktree=$(mktemp -d)
  git worktree add --force "$worktree" "$branch"

  # Copy the shared data/versions.json and config/ into the worktree
  # (snapshot branches may have an older versions.json — we want consistency)
  cp "$REPO_ROOT/data/versions.json" "$worktree/data/versions.json"
  cp -r "$REPO_ROOT/config/" "$worktree/config/"

  (cd "$worktree" && hugo --environment "$ver" --minify --gc --destination "${OUTPUT_DIR}/${ver}")

  git worktree remove --force "$worktree"
  rm -rf "$worktree"
done

echo "✓ All versions built → ${OUTPUT_DIR}/"
```

> **Key detail:** The script copies `data/versions.json` and `config/` from `main` into each worktree before building. This ensures the version dropdown is consistent across all versions — an old snapshot branch doesn't have an outdated dropdown. Only `content/` and `layouts/` come from the snapshot branch.

#### 2.3 Update Makefile

```makefile
build-versioned: ## Build all documentation versions (latest + archived) to ./public.
	./scripts/build-versioned.sh public

serve-versioned: ## Build and serve all versions locally on :1313.
	./scripts/build-versioned.sh public
	python3 -m http.server 1313 --directory public
```

---

### Phase 3: Snapshot Branch Creation

#### 3.1 Create snapshot branches

```bash
# Create snapshot branches at the last tag of each minor series
git branch docs-v0.3 v0.3.7
git branch docs-v0.2 v0.2.7
git branch docs-v0.1 v0.1.25
git push origin docs-v0.3 docs-v0.2 docs-v0.1
```

#### 3.2 Snapshot creation helper script

**`scripts/snapshot-version.sh`**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Create a documentation snapshot branch for a released minor version.
# Usage: scripts/snapshot-version.sh <minor-version> [git-ref]
# Example: scripts/snapshot-version.sh 0.4 v0.4.3
#          scripts/snapshot-version.sh 0.4 HEAD

VER="$1"
REF="${2:-HEAD}"

if [[ -z "$VER" ]]; then
  echo "Usage: $0 <minor-version> [git-ref]"
  exit 1
fi

BRANCH="docs-v${VER}"
echo "Creating snapshot branch '${BRANCH}' from ref '${REF}'..."
git branch "$BRANCH" "$REF"
git push origin "$BRANCH"

echo ""
echo "Next steps:"
echo "  1. Add v${VER} to data/versions.json (as non-latest)"
echo "  2. Bump docsVersion in config/production/hugo.toml to the new latest"
echo "  3. Add v${VER} to VERSIONS array in scripts/build-versioned.sh"
echo "  4. Create config/v${VER}/hugo.toml"
```

#### 3.3 Backport workflow

For critical fixes to old docs (security advisory, broken example, typo):
```bash
git checkout docs-v0.3
# make the fix, commit, push
git push origin docs-v0.3
# Next deploy will rebuild v0.3 with the fix
```

---

### Phase 4: CI Integration

#### 4.1 Update `.github/workflows/build.yml`

Add a versioned build job:

```yaml
  build-versioned:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0  # full history — needed for git worktree branches

      - uses: actions/setup-node@v4
        with:
          node-version: "24"

      - name: Install dependencies
        run: npm ci || npm install

      - name: Install Hugo (extended)
        env:
          HUGO_VERSION: "0.154.5"
        run: |
          set -euo pipefail
          curl -fsSL -o hugo.deb \
            "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.deb"
          sudo dpkg -i hugo.deb

      - name: Build all versions
        run: ./scripts/build-versioned.sh public

      - name: Verify version directories
        run: |
          test -f public/index.html
          test -f public/v0.3/index.html
          test -f public/v0.2/index.html
          test -f public/v0.1/index.html
```

#### 4.2 Update `make deploy` for versioned builds

```makefile
docker-build: ## Build the container image with all doc versions.
	git submodule update --init
	./scripts/build-versioned.sh public
	docker buildx build --platform linux/amd64 -t $(CONTAINER):$(TAG) --load .
```

---

### Phase 5: Verification Checklist

After implementing all phases:

- [ ] Version dropdown appears in navbar on all pages
- [ ] Dropdown shows all versions from `data/versions.json`
- [ ] Current version is marked "active" in dropdown
- [ ] Latest version has a "latest" badge
- [ ] Clicking a version navigates to the correct subdirectory
- [ ] "Not latest" banner appears on archived version pages
- [ ] Each version has its own `search-index.json` (FlexSearch works per-version)
- [ ] Each version has its own `llms.txt`
- [ ] Language switching works within each version (e.g. `/v0.3/fr/docs/...`)
- [ ] `make build-versioned` produces all version directories
- [ ] CI workflow builds all versions successfully
- [ ] Homepage CTA links respect versioning

---

## File Change Summary

### New Files
| File | Purpose |
|---|---|
| `data/versions.json` | Version list driving the dropdown |
| `scripts/build-versioned.sh` | Multi-version build orchestrator (git worktree per version) |
| `scripts/snapshot-version.sh` | Snapshot branch creation helper |
| `config/production/hugo.toml` | Environment config for latest build |
| `config/v0.3/hugo.toml` | Environment config for v0.3 build |
| `config/v0.2/hugo.toml` | Environment config for v0.2 build |
| `config/v0.1/hugo.toml` | Environment config for v0.1 build |
| `layouts/_partials/header/version-banner.html` | "Not latest version" warning banner |

### Modified Files
| File | Changes |
|---|---|
| `hugo.toml` | Add `docsVersioning = true`, `docsVersion = "0.4"`, `docsLatestVersion = "0.4"` |
| `layouts/_partials/header/header.html` | Rewrite dropdown to use `data/versions.json`, add version banner include |
| `Makefile` | Add `build-versioned` and `serve-versioned` targets |
| `.github/workflows/build.yml` | Add versioned build job |
| `layouts/home.html` | Version-aware CTA links |

### New Git Branches
| Branch | Created at tag | Content |
|---|---|---|
| `docs-v0.3` | `v0.3.7` | Snapshot of docs at v0.3 series end |
| `docs-v0.2` | `v0.2.7` | Snapshot of docs at v0.2 series end |
| `docs-v0.1` | `v0.1.25` | Snapshot of docs at v0.1 series end |

---

## Implementation Order

```
Phase 1 (UI)           → Ship immediately; dropdown works, old versions 404 until snapshots exist
  ├─ 1.1 data/versions.json
  ├─ 1.2 hugo.toml params
  ├─ 1.3 header.html dropdown rewrite
  ├─ 1.4 version banner
  └─ 1.5 home.html links

Phase 2 (Environments) → Required before multi-version builds work
  ├─ 2.1 config/<env>/hugo.toml files
  └─ 2.2 build-versioned.sh

Phase 3 (Snapshots)    → Create snapshot branches at tag boundaries
  ├─ 3.1 git branch docs-v* <tag>
  └─ 3.2 snapshot-version.sh for future use

Phase 4 (CI)           → Wire it all together
  └─ 4.1 build.yml update

Phase 5 (Verify)       → Test all paths, search, languages
```

---

## Why Not Module Mounts? (Rejected Alternative)

Hugo Module Mounts can import content from versioned git tags into a single build:

```toml
[[module.imports]]
  path = "github.com/bouine-cache/bouine-documentation"
  version = "v0.3.7"
  [[module.imports.mounts]]
    source = "content"
    target = "content/v0.3"
```

This is elegant but was rejected because:
1. **Requires the content repo to be a Go module** (`go.mod` + `go.sum`) — the repo is not currently a Go module
2. **Single build** means all versions share the same layouts/theme — you cannot have version-specific layout changes
3. **Mount conflicts** — mounting 3 versions × 3 languages into `content/` requires careful mount configuration to avoid collisions
4. **Go module proxy dependency** — builds require network access to the Go module proxy to fetch tagged versions
5. **Complexity vs. benefit** — at 4 versions and ~45 pages, the build-time savings of a single build (~30s) are negligible compared to the setup complexity

The multi-build approach with `git worktree` achieves the same result with a simple shell script and no infrastructure changes.
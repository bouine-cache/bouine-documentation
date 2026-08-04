# Agent Guide for `bouine-documentation`

Documentation website for [bouine](https://github.com/bouine-cache/bouine) — a Kubernetes-native HTTP reverse-proxy cache written in Go.

---

## Critical Rules

- **NEVER restart the k3s cluster or any k3s/node systemd service (`systemctl restart k3s`, `systemctl restart containerd`, etc.) without explicit approval from the owner.** Restarting k3s causes downtime on all workloads on the node. Use alternative approaches (e.g., `k3s ctr images import` to side-load images) that do not require a service restart.

---

## Essential Commands

All commands go through `make` (which delegates to npm/hugo):

| Command | What it does |
|---|---|
| `make install` | Install Node dependencies (required after clone) |
| `make serve` | Start dev server on http://localhost:1313/ |
| `make build` | Production build → `./public/` |
| `make clean` | Remove `public/` and `resources/` |

**Important flags on the dev server** (set in package.json):
- `--disableFastRender` — disables Hugo's fast render (needed when editing shortcodes or layouts)
- `--noHTTPCache` — disables browser caching in dev mode
- `--baseURL http://localhost:1313/` — ensures links resolve correctly

### Prerequisites

- **Node.js >= 24.13.0** (enforced in package.json engines)
- **Hugo Extended** (the Doks theme compiles SCSS; standard Hugo will fail)
- Git submodules initialized (`git submodule update --init --recursive`) — the Doks theme lives at `themes/doks` and is a submodule

---

## Project Structure

```
├── archetypes/                  # Hugo archetypes for new pages
├── assets/
│   ├── jsconfig.json            # Maps asset paths for IDE resolution
│   └── scss/                    # Custom SCSS overrides
├── content/
│   ├── _index.md                # Homepage content (lead paragraph, SEO)
│   └── docs/                    # All documentation pages
│       ├── _index.md            # Docs landing/overview
│       ├── getting-started/     # Install, Docker, K8s, quick start
│       ├── configuration/       # YAML config reference, cache policy, storage, TLS, clustering, Helm
│       ├── operations/          # Runbooks: lifecycle, auth, invalidation, monitoring, dashboard, K8s ops
│       ├── architecture/        # Design docs and internals
│       ├── guides/              # Migration guides (NGINX, Varnish, reverse proxies), capacity planning
│       ├── contributing/        # Contributor guide, security
│       └── reference/           # CLI, API & headers reference
├── layouts/
│   ├── home.html                # Custom homepage template (overrides theme)
│   ├── shortcodes/              # Custom Hugo shortcodes
│   │   ├── arch-diagram.html    # Animated SVG architecture diagram
│   │   └── peer-fetch-diagram.html  # Animated SVG peer-fetch diagram
│   └── _partials/header/
│       └── header.html          # Custom header with bouine branding
├── static/
│   ├── favicon/                 # Favicon assets
│   └── bouine_anglerfish_*.png  # Logo variants (light/dark mode)
├── themes/doks/                 # Doks theme (Git submodule)
├── hugo.toml                    # Site config (baseURL, params, menu, outputs)
├── package.json                 # Node deps + scripts
├── Makefile                     # Unified build interface
└── hugo_stats.json              # Hugo-generated CSS class inventory (checked in)
```

### Hugo Outputs (Custom)

The site produces four output formats on the home page:
- `HTML` — normal site
- `RSS` / `sitemap` — feeds
- `searchIndex` — JSON for FlexSearch
- `llms` — **plain text aggregation of all docs**, intended for LLM ingestion (`/llms.txt`)

---

## Theme & Theming

- **Base theme**: [Doks](https://github.com/thuliteio/doks) via Git submodule at `themes/doks`
- **Override strategy**: Files in `layouts/` and `assets/` shadow the theme. Never edit inside `themes/doks/` directly.
- **Homepage**: Fully overridden in `layouts/home.html` (not the theme's default).

### Branding

- The "bouine" logo is an anglerfish. Two PNG variants exist for light/dark mode:
  - `bouine_anglerfish_homepage_white.png` — shown in light mode
  - `bouine_anglerfish_homepage.png` — shown in dark mode
- CSS classes `.bouine-logo-light` and `.bouine-logo-dark` toggle visibility via the theme's color mode system.

---

## Content Conventions

### Front Matter

Use YAML front matter. Every docs section needs an `_index.md` with:

```yaml
---
title: "Human-readable title"
weight: 1            # Controls sidebar order (lower = earlier)
description: "..."   # Used for SEO meta + listing summaries
---
```

### Archetype

The default archetype (`archetypes/default.md`) uses TOML (`+++`) front matter template syntax:

```toml
+++
date = '{{ .Date }}'
draft = true
title = '{{ replace .File.ContentBaseName "-" " " | title }}'
+++
```

New pages via `hugo new` will use this. Note the mix of TOML (archetype) vs YAML (actual content) is intentional and matches the Doks convention.

### Writing Docs

- Use `##` for top-level headings within a page (ToC starts at level 2).
- Code blocks: use fenced markdown with language identifiers.
- Include practical examples and copy-pastable commands where possible.
- When documenting bouine's YAML config, prefer complete minimal examples over exhaustive field listings.

### Markdown Rendering

In `hugo.toml`:

```toml
[markup.goldmark.renderer]
  unsafe = true
```

This permits raw HTML in markdown. The custom shortcodes and homepage rely on this.

---

## Custom Shortcodes

Two shortcodes inject animated SVG diagrams into pages:

### `arch-diagram`

Usage: `{{< arch-diagram >}}`

A step-by-step animated architecture overview (client → bouine → origin, then layer stack L1–L8). Uses [anime.js](https://cdnjs.cloudflare.com/ajax/libs/animejs/3.2.2/anime.min.js) from CDN.

### `peer-fetch-diagram`

Usage: `{{< peer-fetch-diagram >}}`

Animates the peer-fetch flow (cache MISS on node A → consistent-hash lookup → HIT on owner node B → response back). Also uses anime.js CDN.

**Important**: Both shortcodes inline a `<script>` tag that fetches anime.js from CDN. If you duplicate a shortcode on the same page, the CDN script will load twice — it is idempotent but wastes a request. Prefer one shortcode per page.

---

## Homepage

The homepage (`layouts/home.html`) is fully custom and overrides the Doks theme entirely.

Key parts:
1. **Hero section** — Bouine logo (light/dark variants), title, lead text, CTA buttons.
2. **Features grid** — Three columns with Tabler icons.
3. **Why bouine?** — Six-item feature grid with colored icons.
4. **Footer CTA** — Final call-to-action section.
5. **WebGL background** — Fixed full-screen GLSL noise shader (box-muller Gaussian noise) on `<canvas id="bouine-noise">`. Falls back gracefully if WebGL unavailable.
6. **CSS radial tint** — Purple-tinted radial gradient overlay on `<div id="bouine-tint">`.

The WebGL script is self-contained inline JavaScript — no external build step needed.

---

## Static Assets

Place images, logos, and favicons in `static/`. They are copied verbatim to the site root. Reference them with `{{ relURL "filename" }}` or simply `/filename`.

Examples from the header:
```html
<img src="/bouine_anglerfish_homepage_white.png" ... class="bouine-logo-light">
<img src="/bouine_anglerfish_homepage.png" ... class="bouine-logo-dark">
```

---

## Sidebar Navigation

Configured in `hugo.toml` under `[menu]` for the top bar. The docs sidebar is **automatically generated** from the `content/docs/` file tree using Doks' `section-menu.html` partial.

To add a new top-level docs section:
1. Create the folder under `content/docs/<section>/`
2. Add an `_index.md` with `title` and `weight`
3. Add pages inside it
4. The sidebar will auto-populate; ordering is controlled by `weight` in `_index.md` and individual pages.

The `sectionNav` parameter in `hugo.toml` controls which sections get the auto sidebar:
```toml
sectionNav = ['docs']
```

---

## Editing the Header

The navbar is overridden in `layouts/_partials/header/header.html`. Key customizations vs. stock Doks:
- Bouine logo (light/dark PNGs) linked to home
- GitHub social icon in the nav
- Section navigation for mobile (offcanvas)
- FlexSearch integration (search toggle on desktop and mobile)

If you need to change the menu items, edit `hugo.toml` `[menu.main]` instead of the template.

---

## Search

- **Engine**: FlexSearch (client-side, no external service)
- **Index**: Generated at build time via the `searchIndex` output format
- **Config**: In `hugo.toml` under `[params.doks]`:
  - `flexSearch = true`
  - `searchLimit = 20`

---

## Link Checking

Internal links should use Hugo's `relURL` or `relLangURL` helpers, or simple absolute paths (`/docs/foo/`). Avoid hardcoding the production domain in internal links.

The `editPage` feature is enabled — it links each docs page to its source on GitHub:
```toml
[params.doks]
  editPage = true
  docsRepo = "https://github.com/bouine-cache/bouine-documentation"
  docsRepoBranch = "main"
```

---

## CI / Deployment

There is no `.github/workflows/` in this repository. Deployment is likely handled externally (e.g., Cloudflare Pages, Netlify, or another static host). The `baseURL` in `hugo.toml` points to `https://bouine.org/`.

If adding CI, the build command should be:
```bash
npm ci && npm run build
# or: make install && make build
```

Output is `public/`.

---

## Common Gotchas

1. **Git submodule not initialized** → Hugo fails with "theme not found" or build errors. Fix: `git submodule update --init --recursive`.

2. **Hugo standard instead of Hugo Extended** → SCSS compilation fails. Install Hugo Extended.

3. **Fast render skips layout changes** → The dev server uses `--disableFastRender` for exactly this reason; if running bare `hugo server` without the script, layout edits may not refresh.

4. **`hugo_stats.json` is checked in** — This file is auto-generated by Hugo's `buildStats` feature and is used by the Doks theme for Tailwind CSS purging. It can be regenerated by running a build. Do not hand-edit it.

5. **`unsafe = true` in Goldmark** — Enables raw HTML in markdown. Be careful when accepting external content; for internal docs it's fine and required by the shortcodes.

6. **Node version enforcement** — Use Node >= 24.13.0. Older versions may cause issues with `@thulite/doks-core` or other dependencies.

7. **No GitHub Actions here** — This is the *documentation* repo, not the bouine source repo. The bouine Go source lives at `github.com/bouine-cache/bouine`.

8. **Language support** — German (`de`) and Dutch (`nl`) are explicitly disabled in `hugo.toml`. Only English is built. Do not add multilingual content without also enabling the language.

9. **Anime.js CDN dependency** — The animated diagrams shortcodes load anime.js from `cdnjs.cloudflare.com`. Offline builds will not render animations; the static SVG still displays.

---

## Similar Files & References

- `hugo.toml` — all site configuration, menu, params, outputs, markup.
- `package.json` — npm scripts and Node dependency versions.
- `themes/doks/config/` — Doks theme defaults (reference only; override via `hugo.toml`).
- `content/docs/contributing/codebase.md` — bouine Go codebase map (if it exists; this is a docs page, not the actual source).

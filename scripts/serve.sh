#!/usr/bin/env bash
set -euo pipefail

# Start the local dev server with all documentation versions available.
#
# Archived versions are built first, then copied into static/v<ver>/ so Hugo's
# dev server serves them as static files alongside the latest version (which
# gets live reload). This avoids Hugo overwriting or 404-ing the archived paths.
#
# Usage: scripts/serve.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Read archived versions from data/versions.json
ARCHIVED_VERSIONS=$(python3 -c "
import json
with open('data/versions.json') as f:
    versions = json.load(f)
for v in versions:
    if not v.get('latest') and v.get('version'):
        print(v['version'])
" 2>/dev/null || echo "")

# Clean up any previous archived version static dirs
find static -maxdepth 1 -name 'v*' -type d -exec rm -rf {} + 2>/dev/null || true

if [[ -n "$ARCHIVED_VERSIONS" ]]; then
  echo "▶ Building archived versions..."
  while IFS= read -r ver; do
    [[ -z "$ver" ]] && continue
    branch="docs-v${ver}"
    echo "  Building v${ver} from branch '${branch}'"

    worktree="${REPO_ROOT}/.worktrees/v${ver}"
    rm -rf "$worktree"
    mkdir -p "$(dirname "$worktree")"
    git worktree add --force "$worktree" "$branch" 2>/dev/null

    (cd "$worktree" && git submodule update --init --recursive 2>/dev/null)

    # Copy shared infrastructure from main
    rm -rf "$worktree/hugo.toml" "$worktree/layouts" "$worktree/assets" "$worktree/config" "$worktree/data"
    cp "$REPO_ROOT/hugo.toml" "$worktree/hugo.toml"
    cp -r "$REPO_ROOT/layouts" "$worktree/layouts"
    cp -r "$REPO_ROOT/assets" "$worktree/assets"
    cp -r "$REPO_ROOT/config/" "$worktree/config/"
    mkdir -p "$worktree/data"
    cp "$REPO_ROOT/data/versions.json" "$worktree/data/versions.json"

    (cd "$worktree" && npm install --silent 2>/dev/null)

    # Build into a temp dir, then copy into static/v<ver>/ so Hugo's dev server
    # serves it as a static file (no 404, no overwriting).
    tmp_build=$(mktemp -d)
    (cd "$worktree" && hugo --environment "v${ver}" --minify --gc --destination "$tmp_build" 2>/dev/null)
    mkdir -p "static/v${ver}"
    cp -r "$tmp_build/"* "static/v${ver}/"
    rm -rf "$tmp_build"

    git worktree remove --force "$worktree"
    rm -rf "$worktree"
  done <<< "$ARCHIVED_VERSIONS"
  rmdir "${REPO_ROOT}/.worktrees" 2>/dev/null || true
  echo "✓ Archived versions built into static/"
fi

# Start Hugo dev server. Archived versions in static/v<ver>/ are served as
# static files; the latest version gets live reload.
# baseURL is set in config/development/hugo.toml to http://localhost:1313/
echo "▶ Starting Hugo dev server on http://localhost:1313/"
exec hugo server --disableFastRender --noHTTPCache
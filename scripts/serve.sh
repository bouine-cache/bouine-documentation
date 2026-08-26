#!/usr/bin/env bash
set -euo pipefail

# Start the local dev server with all documentation versions available.
#
# Archived versions are built first into public/v<ver>/, then Hugo runs with
# --renderToDisk so it serves the latest version (with live reload) from the
# same public/ directory. Pre-built archived version files are not overwritten
# by Hugo.
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

if [[ -n "$ARCHIVED_VERSIONS" ]]; then
  echo "▶ Building archived versions..."
  while IFS= read -r ver; do
    [[ -z "$ver" ]] && continue
    branch="docs-v${ver}"
    echo "  Building v${ver} from branch '${branch}' → public/v${ver}/"

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

    mkdir -p "public/v${ver}"
    (cd "$worktree" && hugo --environment "v${ver}" --minify --gc --destination "${REPO_ROOT}/public/v${ver}" 2>/dev/null)

    git worktree remove --force "$worktree"
    rm -rf "$worktree"
  done <<< "$ARCHIVED_VERSIONS"
  rmdir "${REPO_ROOT}/.worktrees" 2>/dev/null || true
  echo "✓ Archived versions built"
fi

# Start Hugo dev server. Hugo server renders to disk by default, so pre-built
# archived version files in public/v<ver>/ are served alongside the live
# latest version (with hot reload).
echo "▶ Starting Hugo dev server on http://localhost:1313/"
exec hugo server --disableFastRender --noHTTPCache --baseURL http://localhost:1313/
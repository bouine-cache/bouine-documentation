#!/usr/bin/env bash
set -euo pipefail

# Build all documentation versions (latest + archived) into a single output directory.
# The latest version is built from the current working directory (main branch).
# Archived versions are built from snapshot branches via git worktree.
#
# For archived versions, only `content/` comes from the snapshot branch.
# Everything else (hugo.toml, layouts/, config/, data/, assets/) is copied from
# main so the version dropdown, output formats, and theme are consistent across
# all versions. npm install is run in each worktree to resolve theme dependencies.
#
# Usage: scripts/build-versioned.sh [output-dir]
# Defaults to ./public

OUTPUT_DIR="${1:-public}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Archived versions to build (must match data/versions.json entries without "latest")
VERSIONS=()

echo "▶ Building latest version → ${OUTPUT_DIR}/"
rm -rf "$OUTPUT_DIR"
(cd "$REPO_ROOT" && hugo --environment production --minify --gc --destination "$OUTPUT_DIR")

for ver in "${VERSIONS[@]}"; do
  branch="docs-${ver}"
  echo "▶ Building ${ver} from branch '${branch}' → ${OUTPUT_DIR}/${ver}/"

  worktree="${REPO_ROOT}/.worktrees/${ver}"
  rm -rf "$worktree"
  mkdir -p "$(dirname "$worktree")"
  git worktree add --force "$worktree" "$branch"

  # Ensure the theme submodule is initialized in the worktree.
  (cd "$worktree" && git submodule update --init --recursive)

  # Overwrite shared infrastructure from main so the version dropdown, output
  # formats, and theme are consistent. Only content/ comes from the snapshot.
  rm -rf "$worktree/hugo.toml" "$worktree/layouts" "$worktree/assets" "$worktree/config" "$worktree/data"
  cp "$REPO_ROOT/hugo.toml" "$worktree/hugo.toml"
  cp -r "$REPO_ROOT/layouts" "$worktree/layouts"
  cp -r "$REPO_ROOT/assets" "$worktree/assets"
  cp -r "$REPO_ROOT/config/" "$worktree/config/"
  mkdir -p "$worktree/data"
  cp "$REPO_ROOT/data/versions.json" "$worktree/data/versions.json"

  # Install npm dependencies (Doks theme layouts come from node_modules/@thulite/doks-core).
  (cd "$worktree" && npm install --silent)

  (cd "$worktree" && hugo --environment "$ver" --minify --gc --destination "${OUTPUT_DIR}/${ver}")

  git worktree remove --force "$worktree"
  rm -rf "$worktree"
done

# Clean up the worktrees directory
rmdir "${REPO_ROOT}/.worktrees" 2>/dev/null || true

echo "✓ All versions built → ${OUTPUT_DIR}/"
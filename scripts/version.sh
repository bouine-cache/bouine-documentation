#!/usr/bin/env bash
set -euo pipefail

# Cut a new documentation version when a new bouine minor/major release is published.
#
# This script:
#   1. Snapshots the current main as docs-v<old> branch
#   2. Updates data/versions.json (old → archived, new → latest)
#   3. Bumps docsVersion/docsLatestVersion in hugo.toml and config/production/hugo.toml
#   4. Creates config/v<old>/hugo.toml for the archived version
#   5. Adds v<old> to the VERSIONS array in scripts/build-versioned.sh
#   6. Launches a crush subagent to update content for the new version (all languages)
#   7. Commits everything
#
# Usage: make version V=0.5
#   Or:  scripts/version.sh 0.5
#
# Prerequisites:
#   - You are on the main branch with a clean working tree
#   - The bouine source repo is at ../bouine (for CHANGELOG access)
#   - crush CLI is installed and in PATH

NEW_VER="${1:-}"
if [[ -z "$NEW_VER" ]]; then
  echo "Usage: $0 <new-minor-version>"
  echo "Example: $0 0.5"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUINE_REPO="${BOUINE_REPO:-$(cd "$REPO_ROOT/../bouine" 2>/dev/null && pwd)}"

if [[ -z "$BOUINE_REPO" ]] || [[ ! -d "$BOUINE_REPO" ]]; then
  echo "ERROR: bouine source repo not found at ../bouine"
  echo "Set BOUINE_REPO env var to the correct path."
  exit 1
fi

cd "$REPO_ROOT"

# Ensure we're on main with a clean tree
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]] && [[ "$CURRENT_BRANCH" != feat/* ]]; then
  echo "ERROR: Must be on 'main' branch (currently on '$CURRENT_BRANCH')"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree must be clean. Commit or stash your changes first."
  git status --short
  exit 1
fi

# Read the current latest version from data/versions.json
OLD_VER=$(python3 -c "
import json
with open('data/versions.json') as f:
    versions = json.load(f)
latest = [v for v in versions if v.get('latest')]
if not latest:
    print('ERROR: No version marked as latest in data/versions.json')
    exit(1)
print(latest[0]['version'])
")

echo "Current latest version: v${OLD_VER}.x"
echo "New latest version:     v${NEW_VER}.x"
echo ""

# Step 1: Create snapshot branch for the old version
OLD_BRANCH="docs-v${OLD_VER}"
if git show-ref --verify --quiet "refs/heads/${OLD_BRANCH}" 2>/dev/null; then
  echo "⚠ Snapshot branch '${OLD_BRANCH}' already exists — skipping creation."
else
  echo "▶ Step 1: Creating snapshot branch '${OLD_BRANCH}' from main..."
  git branch "$OLD_BRANCH" main
  git push origin "$OLD_BRANCH"
  echo "  ✓ Created and pushed '${OLD_BRANCH}'"
fi

# Step 2: Update data/versions.json
echo "▶ Step 2: Updating data/versions.json..."
python3 -c "
import json

new_ver = '${NEW_VER}'
old_ver = '${OLD_VER}'

with open('data/versions.json') as f:
    versions = json.load(f)

# Demote current latest to archived
for v in versions:
    if v.get('latest'):
        v.pop('latest', None)
        if not v.get('path'):
            v['path'] = '/v' + v['version']

# Add new latest at the top
versions.insert(0, {
    'version': new_ver,
    'label': f'v{new_ver}.x',
    'latest': True,
    'path': ''
})

with open('data/versions.json', 'w') as f:
    json.dump(versions, f, indent=2)
    f.write('\n')
"
echo "  ✓ Updated versions.json"

# Step 3: Bump docsVersion in hugo.toml
echo "▶ Step 3: Bumping docsVersion in hugo.toml..."
sed -i.bak "s/docsVersion = \"${OLD_VER}\"/docsVersion = \"${NEW_VER}\"/" hugo.toml
sed -i.bak "s/docsLatestVersion = \"${OLD_VER}\"/docsLatestVersion = \"${NEW_VER}\"/" hugo.toml
rm -f hugo.toml.bak
echo "  ✓ Updated hugo.toml"

# Step 3b: Bump in config/production/hugo.toml
echo "▶ Step 3b: Bumping docsVersion in config/production/hugo.toml..."
sed -i.bak "s/docsVersion = \"${OLD_VER}\"/docsVersion = \"${NEW_VER}\"/" config/production/hugo.toml
sed -i.bak "s/docsLatestVersion = \"${OLD_VER}\"/docsLatestVersion = \"${NEW_VER}\"/" config/production/hugo.toml
rm -f config/production/hugo.toml.bak
echo "  ✓ Updated config/production/hugo.toml"

# Step 4: Create config/v<old>/hugo.toml
OLD_CONFIG="config/v${OLD_VER}/hugo.toml"
if [[ -f "$OLD_CONFIG" ]]; then
  echo "▶ Step 4: config/v${OLD_VER}/hugo.toml already exists — updating docsLatestVersion..."
  sed -i.bak "s/docsLatestVersion = \"${OLD_VER}\"/docsLatestVersion = \"${NEW_VER}\"/" "$OLD_CONFIG"
  rm -f "${OLD_CONFIG}.bak"
else
  echo "▶ Step 4: Creating config/v${OLD_VER}/hugo.toml..."
  mkdir -p "config/v${OLD_VER}"
  cat > "$OLD_CONFIG" <<EOF
baseURL = 'https://bouine.org/v${OLD_VER}/'

[params.doks]
  docsVersioning = true
  docsVersion = "${OLD_VER}"
  docsLatestVersion = "${NEW_VER}"
EOF
fi
echo "  ✓ Updated config/v${OLD_VER}/hugo.toml"

# Step 5: Update VERSIONS array in scripts/build-versioned.sh
echo "▶ Step 5: Updating scripts/build-versioned.sh..."
BUILD_SCRIPT="scripts/build-versioned.sh"
if grep -q "v${OLD_VER}" "$BUILD_SCRIPT"; then
  echo "  ⚠ v${OLD_VER} already in VERSIONS array — skipping."
else
  # Insert the old version at the beginning of the VERSIONS array
  sed -i.bak "s/VERSIONS=(\"v/VERSIONS=(\"v${OLD_VER}\" \"v/" "$BUILD_SCRIPT"
  rm -f "${BUILD_SCRIPT}.bak"
  echo "  ✓ Added v${OLD_VER} to VERSIONS array"
fi

# Step 6: Launch crush subagent to update content
echo "▶ Step 6: Launching crush subagent to update documentation content..."
echo "  (This will update English, French, and Chinese content based on the bouine CHANGELOG)"
echo ""

CHANGELOG_PATH="${BOUINE_REPO}/CHANGELOG.md"
NEW_TAG="v${NEW_VER}.0"

crush run \
  "You are updating the bouine documentation site at $(pwd) for the new release ${NEW_TAG}.

The bouine source code is at ${BOUINE_REPO}. Read ${CHANGELOG_PATH} to understand what changed in ${NEW_TAG} — look at the [Unreleased] section and all entries up to and including the ${NEW_TAG} release.

Then update the documentation content in content/en/docs/, content/fr/docs/, and content/zh/docs/ to reflect these changes. All three languages must stay in sync — the French (fr) and Chinese (zh) content should be accurate translations of the English (en) content.

Focus on:
- New features that need documentation (new config fields, new CLI flags, new API endpoints)
- Changed behavior that requires updated examples or explanations
- Removed features that should be deleted from docs
- New pages that should be created for significant new capabilities
- Configuration reference pages (content/*/docs/configuration/) are the most critical to keep accurate

Do NOT change:
- hugo.toml, config/, data/, scripts/, layouts/, or any non-content files (already handled)
- The version dropdown or versioning infrastructure

After making changes, run 'make build' to verify the site builds successfully. Fix any build errors." \
  2>&1 || echo "  ⚠ crush subagent exited with non-zero status — check content manually."

echo ""
echo "▶ Step 6 complete."

# Step 7: Commit everything
echo "▶ Step 7: Committing changes..."
git add -A

# Check if there are changes to commit
if git diff --cached --quiet; then
  echo "  ⚠ No changes to commit (crush subagent may not have made changes)."
else
  git commit -m "$(cat <<EOF
docs: cut v${NEW_VER}.x and snapshot v${OLD_VER}.x

- Snapshot main as docs-v${OLD_VER} branch for archived v${OLD_VER}.x docs
- Bump docsVersion from ${OLD_VER} to ${NEW_VER}
- Add v${OLD_VER} to data/versions.json and build-versioned.sh
- Create config/v${OLD_VER}/hugo.toml for archived version build
- Update content for v${NEW_VER}.x (en, fr, zh)
EOF
)"
  echo "  ✓ Committed"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Done! v${NEW_VER}.x is now the latest, v${OLD_VER}.x is archived."
echo ""
echo "  Next steps:"
echo "    1. Review the changes: git show HEAD --stat"
echo "    2. Push to origin:    git push origin main"
echo "    3. Deploy:            make deploy"
echo "════════════════════════════════════════════════════════════"
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
echo "  1. Add v${VER} to data/versions.json (as non-latest entry)"
echo "  2. Bump docsVersion in config/production/hugo.toml to the new latest"
echo "  3. Add v${VER} to VERSIONS array in scripts/build-versioned.sh"
echo "  4. Create config/v${VER}/hugo.toml"
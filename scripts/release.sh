#!/usr/bin/env bash
# release.sh — GoBuild release automation script.
#
# Usage:
#   ./scripts/release.sh <version>
#   ./scripts/release.sh 0.3.0
#
# What it does:
#   1. Validates git state (on main, clean working tree, tag does not exist)
#   2. Updates CHANGELOG.md — promotes [Unreleased] → [VERSION] — DATE and
#      inserts a fresh empty [Unreleased] section above it
#   3. Bumps version= in addons/go_build/plugin.cfg
#   4. Runs verify.sh (GDScript syntax + lint)
#   5. Commits both files: "chore: bump version to vVERSION"
#   6. Creates annotated tag vVERSION
#   7. Pushes main + tags to origin
#
# After this script finishes:
#   - The release.yml CI workflow triggers on the tag and creates a draft
#     GitHub Release containing the plugin zip, the changelog section, and
#     the Godot Asset Library archive URL.
#   - Review and publish the draft on GitHub, then submit to the Asset Library
#     using the URL printed in the release body.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Argument check ─────────────────────────────────────────────────────────────
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh <version>  (e.g. 0.3.0)" >&2
    exit 1
fi

TAG="v${VERSION}"
DATE=$(date +%Y-%m-%d)

echo "GoBuild — Release $TAG ($DATE)"
echo "────────────────────────────────────────"

# ── Validate git state ─────────────────────────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Error: must be on main (currently on '$BRANCH')" >&2
    exit 1
fi

if ! git diff --quiet HEAD 2>/dev/null; then
    echo "Error: working tree has uncommitted changes — commit or stash first" >&2
    git status --short >&2
    exit 1
fi

if git rev-parse "$TAG" &>/dev/null; then
    echo "Error: tag '$TAG' already exists" >&2
    exit 1
fi

# ── Validate CHANGELOG has an [Unreleased] section ────────────────────────────
if ! grep -q "^## \[Unreleased\]" CHANGELOG.md; then
    echo "Error: no '## [Unreleased]' section found in CHANGELOG.md" >&2
    exit 1
fi

# ── Update CHANGELOG.md ────────────────────────────────────────────────────────
echo "→ Updating CHANGELOG.md..."

# Replace '## [Unreleased]' with both a fresh empty [Unreleased] heading and
# the new versioned heading.  The existing '---' already in the file (which
# separates [Unreleased] from the previous release) becomes the separator
# between the two versioned sections — no extra '---' needed.
sed -i "s/^## \[Unreleased\]/## [Unreleased]\n\n---\n\n## [${VERSION}] — ${DATE}/" CHANGELOG.md

echo "  ✓ [Unreleased] → [${VERSION}] — ${DATE}"

# ── Bump plugin.cfg ────────────────────────────────────────────────────────────
echo "→ Updating addons/go_build/plugin.cfg..."
sed -i "s/^version=.*/version=\"${VERSION}\"/" addons/go_build/plugin.cfg
echo "  ✓ version → ${VERSION}"

# ── Verify ─────────────────────────────────────────────────────────────────────
echo "→ Running verify.sh..."
bash verify.sh

# ── Commit ─────────────────────────────────────────────────────────────────────
echo "→ Committing..."
git add CHANGELOG.md addons/go_build/plugin.cfg
git commit -m "chore: bump version to ${TAG}"

# ── Tag ────────────────────────────────────────────────────────────────────────
echo "→ Tagging ${TAG}..."
git tag -a "${TAG}" -m "Release ${TAG}"

# ── Push ───────────────────────────────────────────────────────────────────────
echo "→ Pushing main + ${TAG}..."
git push origin main --tags

echo ""
echo "────────────────────────────────────────"
echo "✓  Released ${TAG}"
echo ""
echo "Next steps:"
echo "  1. Review the draft GitHub Release at:"
echo "     https://github.com/marcel-b-roodt/GoBuild/releases"
echo "     It contains the plugin zip, changelog, and the asset library URL."
echo "  2. Publish the draft."
echo "  3. Copy the asset library URL from the release body and submit to"
echo "     https://godotengine.org/asset-library"
echo "  4. Post community announcements (Patreon / Reddit / Discord / Twitter)."

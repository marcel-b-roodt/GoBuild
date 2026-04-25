#!/usr/bin/env bash
# release.sh — GoBuild release automation script.
#
# Usage:
#   ./scripts/release.sh <version>
#   ./scripts/release.sh <version> --dev
#   ./scripts/release.sh 0.3.0
#   ./scripts/release.sh 0.5.0-dev1 --dev
#
# What it does:
#   1. Validates git state (on main, clean working tree, tag does not exist)
#      and validates version format:
#        stable: X.Y.Z
#        dev:    X.Y.Z-devN
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
CHANNEL="${2:-stable}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh <version> [--dev]  (e.g. 0.3.0 or 0.5.0-dev1 --dev)" >&2
    exit 1
fi

if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "--dev" ]]; then
    echo "Error: unknown second argument '$CHANNEL' (expected '--dev' or omitted)" >&2
    exit 1
fi

IS_DEV=false
if [[ "$CHANNEL" == "--dev" ]]; then
    IS_DEV=true
fi

if $IS_DEV; then
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-dev[0-9]+$ ]]; then
        echo "Error: dev version must match X.Y.Z-devN (e.g. 0.5.0-dev1)" >&2
        exit 1
    fi
else
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: stable version must match X.Y.Z (e.g. 0.5.0)" >&2
        exit 1
    fi
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
if $IS_DEV; then
    git commit -m "chore: bump prerelease version to ${TAG}"
else
    git commit -m "chore: bump version to ${TAG}"
fi

# ── Tag ────────────────────────────────────────────────────────────────────────
echo "→ Tagging ${TAG}..."
if $IS_DEV; then
    git tag -a "${TAG}" -m "Prerelease ${TAG}"
else
    git tag -a "${TAG}" -m "Release ${TAG}"
fi

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
echo "     Add screenshots/GIFs, then publish the draft."
echo "  2. Submit to the Godot Asset Library by linking the published GitHub Release."
echo "  3. Post community announcements (Patreon / Reddit / Discord / Twitter)."

#!/usr/bin/env bash
# release-dev.sh — convenience wrapper for prerelease/dev tags.
#
# Usage:
#   ./scripts/release-dev.sh <version>
#   ./scripts/release-dev.sh 0.5.0-dev1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release-dev.sh <version>  (e.g. 0.5.0-dev1)" >&2
    exit 1
fi

bash scripts/release.sh "$VERSION" --dev

#!/usr/bin/env bash
# verify.sh — GoBuild pre-commit verification script
#
# Checks all GDScript files for syntax errors (gdparse) and style issues (gdlint).
# Run manually before committing:   ./verify.sh
# Or wire it up once:               git config core.hooksPath .githooks
#
# Requires gdtoolkit:  pip install gdtoolkit
#                      (or: pip install --break-system-packages gdtoolkit on Arch)

set -euo pipefail

# Resolve script location so this works from any working directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── Collect all GDScript files ──────────────────────────────────────────
# Exclude addons/gdUnit4 — that is a third-party dependency; its files are
# not our responsibility and may contain patterns that trip our toolchain.
mapfile -t ADDON_SCRIPTS < <(find addons -name "*.gd" -not -path "addons/gdUnit4/*" 2>/dev/null)
mapfile -t TEST_SCRIPTS  < <(find tests  -name "*.gd" 2>/dev/null)
ALL_SCRIPTS=("${ADDON_SCRIPTS[@]}" "${TEST_SCRIPTS[@]}")

if [ "${#ALL_SCRIPTS[@]}" -eq 0 ]; then
  echo "No GDScript files found. Nothing to verify."
  exit 0
fi

echo "GoBuild — pre-commit verification"
echo "Files: ${#ALL_SCRIPTS[@]} GDScript file(s)"
echo "────────────────────────────────────────"

# ── 1. Check gdtoolkit is available ─────────────────────────────────────
if ! command -v gdparse &>/dev/null; then
  echo "ERROR: gdparse not found."
  echo "Install it:  pip install gdtoolkit"
  echo "  (Arch)     pip install --break-system-packages gdtoolkit"
  exit 1
fi

# ── 2. Syntax check (gdparse) ───────────────────────────────────────────
echo ""
echo "→ Syntax check (gdparse)..."
PARSE_FAILED=0
for f in "${ALL_SCRIPTS[@]}"; do
  if ! gdparse "$f" 2>&1; then
    echo "  FAIL: $f"
    PARSE_FAILED=1
  fi
done
if [ "$PARSE_FAILED" -ne 0 ]; then
  echo ""
  echo "✗ Syntax errors found. Fix them before committing."
  exit 1
fi
echo "  ✓ All files parsed OK."

# ── 3. Lint check (gdlint) ──────────────────────────────────────────────
echo ""
echo "→ Lint check (gdlint)..."
if gdlint "${ALL_SCRIPTS[@]}" 2>&1; then
  echo "  ✓ No lint problems."
else
  echo ""
  echo "✗ Lint issues found. Fix them or update .gdlintrc to suppress false positives."
  exit 1
fi

# ── Done ────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
echo "✓ Verification passed — safe to commit."


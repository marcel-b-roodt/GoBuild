#!/usr/bin/env bash
# run_tests.sh — Run the GoBuild GdUnit4 test suite headlessly.
#
# Usage:
#   ./scripts/run_tests/run_tests.sh [--godot-bin /path/to/godot]
#
# The Godot 4 binary is resolved in this priority order:
#   1. --godot-bin <path>   (highest priority)
#   2. GODOT_BIN env var
#   3. 'godot4' or 'godot' on PATH
#   4. ~/Godot Engine/**/Godot_v4*   (newest version first, skips .zip)
#
# Exits 0 when all tests pass; non-zero when any test fails or Godot is missing.
#
# Requires: a Godot 4 binary (downloaded from https://godotengine.org or via
#           your distro's package manager, e.g. pacman -S godot).

# -u  treat unbound variables as errors
# -o pipefail  propagate pipe failures
# NOTE: -e is intentionally omitted so we can capture Godot's exit code and
#       print a summary before relaying it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Parse arguments ──────────────────────────────────────────────────────────
_GODOT_BIN_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --godot-bin)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --godot-bin requires a path argument." >&2
                exit 1
            fi
            _GODOT_BIN_ARG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--godot-bin /path/to/godot]"
            echo ""
            echo "Run the full GoBuild GdUnit4 test suite headlessly."
            echo ""
            echo "Options:"
            echo "  --godot-bin <path>   Path to a Godot 4 binary (overrides env / auto-detect)"
            echo "  -h, --help           Show this help and exit"
            echo ""
            echo "Environment variables:"
            echo "  GODOT_BIN            Path to a Godot 4 binary"
            echo ""
            echo "Auto-detection order (when neither --godot-bin nor GODOT_BIN is set):"
            echo "  1. 'godot4' or 'godot' on PATH"
            echo "  2. ~/Godot Engine/**/Godot_v4*  (newest version first)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ── Resolve Godot binary ──────────────────────────────────────────────────────
_godot=""

if [[ -n "$_GODOT_BIN_ARG" ]]; then
    _godot="$_GODOT_BIN_ARG"
elif [[ -n "${GODOT_BIN:-}" ]]; then
    _godot="$GODOT_BIN"
else
    # Auto-detect: check PATH candidates first.
    for _candidate in godot4 godot; do
        if command -v "$_candidate" &>/dev/null; then
            _godot="$(command -v "$_candidate")"
            break
        fi
    done

    # Auto-detect: ~/Godot Engine/**/Godot_v4* (downloaded from godotengine.org).
    # Reverse-sorts so the highest version string is tried first.
    if [[ -z "$_godot" ]]; then
        while IFS= read -r -d $'\0' _found; do
            if [[ -f "$_found" && -x "$_found" ]]; then
                _godot="$_found"
                break
            fi
        done < <(find "$HOME/Godot Engine" -maxdepth 4 \
                     -name "Godot_v4*" \
                     -not -name "*.zip" \
                     -not -name "*.tar*" \
                     -print0 2>/dev/null | sort -rz)
    fi
fi

if [[ -z "$_godot" ]]; then
    echo "ERROR: Could not find a Godot 4 binary." >&2
    echo "Provide it via --godot-bin or set the GODOT_BIN environment variable." >&2
    echo "Alternatively, install Godot 4 so 'godot4' appears on your PATH." >&2
    exit 1
fi

if [[ ! -f "$_godot" ]]; then
    echo "ERROR: Godot binary does not exist: $_godot" >&2
    exit 1
fi

if [[ ! -x "$_godot" ]]; then
    echo "ERROR: Godot binary is not executable: $_godot" >&2
    exit 1
fi

# ── Run tests ─────────────────────────────────────────────────────────────────
echo "GoBuild — GdUnit4 test runner"
echo "Godot  : $_godot"
echo "Project: $REPO_ROOT"
echo "────────────────────────────────────────"
echo ""

_exit_code=0
"$_godot" \
    --headless \
    --path "$REPO_ROOT" \
    -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    -a res://tests \
    -c \
    --ignoreHeadlessMode \
    || _exit_code=$?

echo ""
echo "────────────────────────────────────────"
if [[ $_exit_code -eq 0 ]]; then
    echo "✓ All tests passed."
else
    echo "✗ Tests failed (exit code: $_exit_code)."
fi

exit $_exit_code




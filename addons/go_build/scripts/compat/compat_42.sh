#!/usr/bin/env bash
# compat_42.sh — Make GoBuild compatible with Godot 4.2.
#
# Applies all transforms needed to run GoBuild on Godot 4.2:
#   1. Strip typed for-loop variables              (4.2+ syntax)
#   2. Replace DOCK_SLOT_BOTTOM with integer 7     (4.3+ constant)
#   3. Replace StaticBody3D.DisableMode enum       (4.3+ — use int constants)
#   4. Replace Vector3.min()/max() with minf/maxf  (4.3+ methods)
#   5. Replace "as int" enum casts with int()      (4.3+ cast syntax)
#
# Run with no arguments. The script finds the addon root relative to its own
# location and transforms files in-place. Re-download or re-extract the addon
# to restore the original files.
#
# Usage:
#   ./scripts/compat/compat_42.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Validate we're inside a GoBuild addon directory
if [ ! -f "${ADDON_ROOT}/plugin.cfg" ]; then
	echo "Error: Cannot find plugin.cfg at ${ADDON_ROOT}" >&2
	echo "       Make sure this script lives inside addons/go_build/scripts/compat/" >&2
	exit 1
fi

# Safety check: refuse to run inside a git repository (the dev source).
if [ -d "${ADDON_ROOT}/.git" ] || git -C "${ADDON_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
	echo "Warning: This appears to be a git repository." >&2
	echo "         Running compat transforms on the source repo will modify tracked files." >&2
	echo "         Press Ctrl+C to abort, or Enter to continue." >&2
	read -r
fi

# Source transform functions
source "${SCRIPT_DIR}/functions/strip_typed_fors.sh"
source "${SCRIPT_DIR}/functions/replace_dock_slot_bottom.sh"
source "${SCRIPT_DIR}/functions/replace_disable_mode_enum.sh"
source "${SCRIPT_DIR}/functions/replace_vector3_minmax.sh"
source "${SCRIPT_DIR}/functions/replace_enum_int_cast.sh"

echo "GoBuild — Godot 4.2 compat (in-place)"
echo "Target: ${ADDON_ROOT}"
echo ""

echo "→ Stripping typed for-loop variables..."
compat::strip_typed_fors "${ADDON_ROOT}"

echo "→ Replacing DOCK_SLOT_BOTTOM with integer constant (4.3+)..."
compat::replace_dock_slot_bottom "${ADDON_ROOT}"

echo "→ Replacing StaticBody3D.DisableMode with int constants (4.3+)..."
compat::replace_disable_mode_enum "${ADDON_ROOT}"

echo "→ Replacing Vector3.min()/max() with minf()/maxf() (4.3+)..."
compat::replace_vector3_minmax "${ADDON_ROOT}"

echo "→ Replacing 'as int' enum casts with int() (4.3+)..."
compat::replace_enum_int_cast "${ADDON_ROOT}"

echo ""
echo "Done. The addon at ${ADDON_ROOT} is now 4.2-compatible."
echo "Re-download or re-extract the addon to restore the original files."
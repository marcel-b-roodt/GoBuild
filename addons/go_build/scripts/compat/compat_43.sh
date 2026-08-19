#!/usr/bin/env bash
# compat_43.sh — Make GoBuild compatible with Godot 4.3.
#
# Applies transforms needed to run GoBuild on Godot 4.3:
#   1. Replace DOCK_SLOT_BOTTOM with DOCK_SLOT_LEFT_UR  (4.4+ constant)
#
# Godot 4.3 lacks DOCK_SLOT_BOTTOM (added in 4.4). The equivalent slot
# integer value is DOCK_SLOT_LEFT_UR, which exists in 4.3.
#
# All other 4.4+ incompatibilities (typed for-loops, DisableMode enum,
# Vector3.min/max, "as int" casts) are already valid in 4.3.
#
# Run with no arguments. The script finds the addon root relative to its own
# location and transforms files in-place. Re-download or re-extract the addon
# to restore the original files.
#
# Usage:
#   ./scripts/compat/compat_43.sh

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

# Source transform function
source "${SCRIPT_DIR}/functions/replace_dock_slot_bottom_43.sh"

echo "GoBuild — Godot 4.3 compat (in-place)"
echo "Target: ${ADDON_ROOT}"
echo ""

echo "→ Replacing DOCK_SLOT_BOTTOM with DOCK_SLOT_LEFT_UR (4.4+)..."
compat::replace_dock_slot_bottom_43 "${ADDON_ROOT}"

echo ""
echo "Done. The addon at ${ADDON_ROOT} is now 4.3-compatible."
echo "Re-download or re-extract the addon to restore the original files."
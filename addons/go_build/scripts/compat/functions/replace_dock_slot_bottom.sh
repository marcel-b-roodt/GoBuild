#!/usr/bin/env bash
# replace_dock_slot_bottom.sh — Replace DOCK_SLOT_BOTTOM with integer constant.
#
# DOCK_SLOT_BOTTOM was introduced in Godot 4.3. In earlier versions, the
# equivalent integer value (7) maps to DOCK_SLOT_LEFT_UR, which is a
# reasonable fallback for a UV editor panel.
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Source this file, do not execute it directly.

compat::replace_dock_slot_bottom() {
	local dir="$1"

	while IFS= read -r -d '' file; do
		sed -i -E 's/DOCK_SLOT_BOTTOM/7/g' "${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
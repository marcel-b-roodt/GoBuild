#!/usr/bin/env bash
# replace_disable_mode_enum.sh — Replace StaticBody3D.DisableMode (4.3+) with int.
#
# StaticBody3D.DisableMode was introduced in Godot 4.3.
# This function replaces type annotations and enum values with int equivalents:
#   StaticBody3D.DisableMode                 → int
#   StaticBody3D.DISABLE_MODE_REMOVE         → 0
#   StaticBody3D.DISABLE_MODE_MAKE_STATIC    → 1
#   StaticBody3D.DISABLE_MODE_MAKE_KINEMATIC → 2
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Source this file, do not execute it directly.

compat::replace_disable_mode_enum() {
	local dir="$1"

	while IFS= read -r -d '' file; do
		sed -i -E \
			-e 's/StaticBody3D\.DisableMode/int/g' \
			-e 's/StaticBody3D\.DISABLE_MODE_REMOVE/0/g' \
			-e 's/StaticBody3D\.DISABLE_MODE_MAKE_STATIC/1/g' \
			-e 's/StaticBody3D\.DISABLE_MODE_MAKE_KINEMATIC/2/g' \
			"${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
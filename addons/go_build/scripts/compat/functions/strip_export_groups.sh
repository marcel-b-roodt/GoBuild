#!/usr/bin/env bash
# strip_export_groups.sh — Remove @export_group and @export_subgroup lines (4.1+ → 4.0).
#
# @export_group and @export_subgroup were introduced in Godot 4.1.
# Stripping them makes all exported properties appear flat in the Inspector
# (ungrouped), which works in 4.0.
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Source this file, do not execute it directly.

compat::strip_export_groups() {
	local dir="$1"

	while IFS= read -r -d '' file; do
		sed -i '/^@export_group\|^@export_subgroup/d' "${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
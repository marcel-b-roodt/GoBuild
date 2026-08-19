#!/usr/bin/env bash
# strip_typed_fors.sh — Remove typed for-loop variable annotations (4.1+ → 4.0).
#
# Godot 4.1+ supports `for x: Type in arr:` but Godot 4.0 does not.
# This function strips the `: Type` annotation from every for-loop in
# all .gd files under the given directory.
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Handles types with dots (GoBuildFace.UvMode), brackets (Array[int]),
# and simple types (int, String, bool, etc.).
#
# Source this file, do not execute it directly.

compat::strip_typed_fors() {
	local dir="$1"

	while IFS= read -r -d '' file; do
		sed -i -E \
			-e 's/for ([a-zA-Z_][a-zA-Z0-9_]*): [a-zA-Z_][a-zA-Z0-9_.]+\[([^]]*)\] in/for \1 in/g' \
			-e 's/for ([a-zA-Z_][a-zA-Z0-9_]*): [a-zA-Z_][a-zA-Z0-9_.]+ in/for \1 in/g' \
			"${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
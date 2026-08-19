#!/usr/bin/env bash
# replace_vector3_minmax.sh — Replace Vector2/Vector3 .min()/.max() with minf/maxf.
#
# Vector2.min(), Vector2.max(), Vector3.min(), Vector3.max() were introduced
# in Godot 4.3. In 4.2 and earlier, these methods don't exist.
#
# This function handles both types in two passes:
#   Pass 1: Replace all .min()/.max() as Vector3 (3 components)
#   Pass 2: Downgrade Vector3 → Vector2 for variables with _uv suffix
#           (GoBuild's Vector2 convention)
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Source this file, do not execute it directly.

compat::replace_vector3_minmax() {
	local dir="$1"

	# Pass 1: Replace all .min()/.max() as Vector3 (3 components).
	# Pattern: lhs = rhs.min(arg) → lhs = Vector3(minf(rhs.x, arg.x), minf(rhs.y, arg.y), minf(rhs.z, arg.z))
	while IFS= read -r -d '' file; do
		sed -i -E \
			-e 's/([a-zA-Z_][a-zA-Z0-9_]*) = ([a-zA-Z_][a-zA-Z0-9_]*)\.min\(([^)]+)\)/\1 = Vector3(minf(\2.x, \3.x), minf(\2.y, \3.y), minf(\2.z, \3.z))/g' \
			-e 's/([a-zA-Z_][a-zA-Z0-9_]*) = ([a-zA-Z_][a-zA-Z0-9_]*)\.max\(([^)]+)\)/\1 = Vector3(maxf(\2.x, \3.x), maxf(\2.y, \3.y), maxf(\2.z, \3.z))/g' \
			"${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)

	# Pass 2: Downgrade Vector3 → Vector2 for _uv suffix variables.
	# Only variables ending in _uv are Vector2 in GoBuild; the rest are Vector3.
	while IFS= read -r -d '' file; do
		perl -i -pe \
			's/Vector3\((minf\([^)]*_uv\.x,\s*[^)]+\.x\),\s*minf\([^)]*_uv\.y,\s*[^)]+\.y\)),\s*minf\([^)]*_uv\.z,\s*[^)]+\.z\)\)/Vector2($1)/g; s/Vector3\((maxf\([^)]*_uv\.x,\s*[^)]+\.x\),\s*maxf\([^)]*_uv\.y,\s*[^)]+\.y\)),\s*maxf\([^)]*_uv\.z,\s*[^)]+\.z\)\)/Vector2($1)/g' \
			"${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
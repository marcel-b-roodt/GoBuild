#!/usr/bin/env bash
# replace_enum_int_cast.sh — Replace "as int" enum casts with int() calls.
#
# Godot 4.3+ allows `MyEnum.Value as int`, but 4.2 treats this as an
# invalid cast. The fix is to use `int(MyEnum.Value)` instead, which
# works in all Godot 4.x versions.
#
# This function replaces:
#   <expression> as int   →   int(<expression>)
#
# But only in contexts where the expression is an enum value assignment,
# specifically patterns like:  var mode_int: int = mode as int
# Which becomes:              var mode_int: int = int(mode)
#
# Arguments:
#   $1 — Directory containing .gd files to transform (modified in-place)
#
# Source this file, do not execute it directly.

compat::replace_enum_int_cast() {
	local dir="$1"

	while IFS= read -r -d '' file; do
		# Replace " <expr> as int" with "int(<expr>)"
		# Matches patterns like: = mode as int  →  = int(mode)
		# and: = value as int   →  = int(value)
		sed -i -E 's/([a-zA-Z_][a-zA-Z0-9_]*) as int/int(\1)/g' "${file}" 2>/dev/null || true
	done < <(find "${dir}" -name '*.gd' -print0)
}
#!/usr/bin/env bats
# Tests for the root verify.sh script.
#
# Covers:
#   - Script presence and executability
#   - Exit 0 on a clean repository
#   - Output format (file count line)
#   - Exit 1 on a file with a syntax error
#   - Exit 1 on a file with a lint error
#   - Exit 0 when no GDScript files exist (nothing to verify)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
VERIFY_SCRIPT="$REPO_ROOT/verify.sh"

# ---------------------------------------------------------------------------
# Helpers — set up / tear down an isolated temp project
# ---------------------------------------------------------------------------

setup() {
  TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP_DIR"
}

# Run verify.sh inside $TMP_DIR (it resolves REPO_ROOT from its own location).
_run_in_tmp() {
  cp "$VERIFY_SCRIPT" "$TMP_DIR/verify.sh"
  chmod +x "$TMP_DIR/verify.sh"
  cd "$TMP_DIR"
  run bash verify.sh
}

# ---------------------------------------------------------------------------
# Basic checks
# ---------------------------------------------------------------------------

@test "verify.sh exists" {
  [ -f "$VERIFY_SCRIPT" ]
}

@test "verify.sh is executable" {
  [ -x "$VERIFY_SCRIPT" ]
}

# ---------------------------------------------------------------------------
# Integration — clean repository
# ---------------------------------------------------------------------------

@test "passes on the clean GoBuild repository" {
  cd "$REPO_ROOT"
  run bash verify.sh
  [ "$status" -eq 0 ]
}

@test "output contains GDScript file count line" {
  cd "$REPO_ROOT"
  run bash verify.sh
  echo "$output" | grep -q "GDScript file(s)"
}

@test "output contains verification passed message" {
  cd "$REPO_ROOT"
  run bash verify.sh
  echo "$output" | grep -q "Verification passed"
}

# ---------------------------------------------------------------------------
# No GDScript files → exit 0 (nothing to verify)
# ---------------------------------------------------------------------------

@test "exits 0 with message when no GDScript files exist" {
  # TMP_DIR has no addons/ or tests/ folders
  _run_in_tmp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Nothing to verify"
}

# ---------------------------------------------------------------------------
# Syntax error → exit 1
# ---------------------------------------------------------------------------

@test "exits 1 when a GDScript file has a syntax error" {
  mkdir -p "$TMP_DIR/addons"
  # Deliberately broken: unclosed parenthesis
  echo "func broken(:" > "$TMP_DIR/addons/bad_syntax.gd"
  _run_in_tmp
  [ "$status" -ne 0 ]
}

@test "syntax failure output mentions the bad file" {
  mkdir -p "$TMP_DIR/addons"
  echo "func broken(:" > "$TMP_DIR/addons/bad_syntax.gd"
  _run_in_tmp
  [ "$status" -ne 0 ]
  # Output should reference the broken file or report a syntax failure
  echo "$output" | grep -qiE "(bad_syntax|Syntax errors|FAIL)"
}

# ---------------------------------------------------------------------------
# Lint error → exit 1
# ---------------------------------------------------------------------------

@test "exits 1 when a GDScript file has a lint error" {
  mkdir -p "$TMP_DIR/addons"
  # PascalCase function name violates gdlint's function-name rule
  cat > "$TMP_DIR/addons/bad_lint.gd" << 'GDEOF'
class_name BadLint
extends RefCounted

func MyBadFunctionName() -> void:
	pass
GDEOF
  _run_in_tmp
  [ "$status" -ne 0 ]
}


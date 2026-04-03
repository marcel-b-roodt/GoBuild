#!/usr/bin/env bats
# Tests for scripts/run_tests/run_tests.sh.
#
# Covers:
#   - Script presence and executability
#   - --help flag
#   - Unknown argument → exit non-zero
#   - --godot-bin missing value → exit non-zero
#   - --godot-bin non-existent path → exit non-zero
#   - --godot-bin non-executable file → exit non-zero
#   - Fake godot exits 0 → script exits 0, prints success marker
#   - Fake godot exits 1 → script exits 1, prints failure marker
#   - Exact exit code is relayed from the Godot binary

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/run_tests/run_tests.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup() {
    TMP_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Create a fake Godot binary at $1 that exits with code $2 (default 0).
_make_fake_godot() {
    local path="$1"
    local code="${2:-0}"
    cat > "$path" << BATS_EOF
#!/usr/bin/env bash
exit ${code}
BATS_EOF
    chmod +x "$path"
}

# ---------------------------------------------------------------------------
# Presence
# ---------------------------------------------------------------------------

@test "run_tests.sh exists" {
    [ -f "$SCRIPT" ]
}

@test "run_tests.sh is executable" {
    [ -x "$SCRIPT" ]
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

@test "--help exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "--help output contains 'Usage'" {
    run bash "$SCRIPT" --help
    echo "$output" | grep -qi "usage"
}

@test "--help output mentions --godot-bin" {
    run bash "$SCRIPT" --help
    echo "$output" | grep -q -- "--godot-bin"
}

@test "--help output mentions GODOT_BIN env var" {
    run bash "$SCRIPT" --help
    echo "$output" | grep -q "GODOT_BIN"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "exits non-zero on unknown argument" {
    run bash "$SCRIPT" --unknown-flag
    [ "$status" -ne 0 ]
}

@test "error on unknown argument references --help" {
    run bash "$SCRIPT" --unknown-flag
    echo "$output" | grep -q "help"
}

@test "exits non-zero when --godot-bin is the last argument with no value" {
    run bash "$SCRIPT" --godot-bin
    [ "$status" -ne 0 ]
}

@test "exits non-zero when --godot-bin path does not exist" {
    run bash "$SCRIPT" --godot-bin "/nonexistent/path/to/godot_binary"
    [ "$status" -ne 0 ]
}

@test "error message mentions 'does not exist' for missing --godot-bin path" {
    run bash "$SCRIPT" --godot-bin "/nonexistent/path/to/godot_binary"
    echo "$output" | grep -qi "does not exist"
}

@test "exits non-zero when --godot-bin file exists but is not executable" {
    touch "$TMP_DIR/godot_no_exec"
    chmod -x "$TMP_DIR/godot_no_exec"
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/godot_no_exec"
    [ "$status" -ne 0 ]
}

@test "error message mentions 'not executable' for non-executable --godot-bin" {
    touch "$TMP_DIR/godot_no_exec"
    chmod -x "$TMP_DIR/godot_no_exec"
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/godot_no_exec"
    echo "$output" | grep -qi "not executable"
}

# ---------------------------------------------------------------------------
# GODOT_BIN env var — validation path (no actual Godot needed)
# ---------------------------------------------------------------------------

@test "exits non-zero when GODOT_BIN points to a non-existent file" {
    run env GODOT_BIN="/nonexistent/godot" bash "$SCRIPT"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Fake Godot — success path
# ---------------------------------------------------------------------------

@test "exits 0 when fake godot exits 0" {
    _make_fake_godot "$TMP_DIR/fake_godot" 0
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot"
    [ "$status" -eq 0 ]
}

@test "prints success marker when fake godot exits 0" {
    _make_fake_godot "$TMP_DIR/fake_godot" 0
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot"
    echo "$output" | grep -q "✓"
}

@test "output contains 'GoBuild' header" {
    _make_fake_godot "$TMP_DIR/fake_godot" 0
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot"
    echo "$output" | grep -q "GoBuild"
}

@test "output shows the resolved Godot binary path" {
    _make_fake_godot "$TMP_DIR/fake_godot" 0
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot"
    echo "$output" | grep -q "fake_godot"
}

# ---------------------------------------------------------------------------
# Fake Godot — failure path
# ---------------------------------------------------------------------------

@test "exits non-zero when fake godot exits 1" {
    _make_fake_godot "$TMP_DIR/fake_godot_fail" 1
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot_fail"
    [ "$status" -ne 0 ]
}

@test "prints failure marker when fake godot exits non-zero" {
    _make_fake_godot "$TMP_DIR/fake_godot_fail" 1
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot_fail"
    echo "$output" | grep -q "✗"
}

@test "relays exit code 2 from godot" {
    _make_fake_godot "$TMP_DIR/fake_godot_code2" 2
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot_code2"
    [ "$status" -eq 2 ]
}

@test "relays exit code 42 from godot" {
    _make_fake_godot "$TMP_DIR/fake_godot_code42" 42
    run bash "$SCRIPT" --godot-bin "$TMP_DIR/fake_godot_code42"
    [ "$status" -eq 42 ]
}


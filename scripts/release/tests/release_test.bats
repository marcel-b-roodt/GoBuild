#!/usr/bin/env bats
# Tests for scripts/release.sh
#
# Covers:
#   - Script presence and executability
#   - No argument → exit 1 with usage message
#   - Git guard: not on main branch → exit 1
#   - Git guard: dirty working tree → exit 1
#   - Git guard: tag already exists → exit 1
#   - CHANGELOG guard: no [Unreleased] section → exit 1
#   - CHANGELOG.md is updated with versioned heading and today's date
#   - CHANGELOG.md retains a fresh [Unreleased] section above the new version
#   - plugin.cfg version= line is bumped
#   - Git commit is created with the expected message
#   - Annotated tag is created
#   - Success message is printed on completion

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
RELEASE_SCRIPT="$REPO_ROOT/scripts/release.sh"

# Real git binary — captured here so the push mock can delegate to it.
REAL_GIT="/usr/bin/git"

# ---------------------------------------------------------------------------
# Helpers — isolated temp repo
# ---------------------------------------------------------------------------

setup() {
    TMP_DIR="$(mktemp -d)"

    # Place the script in scripts/ so REPO_ROOT resolves to TMP_DIR.
    mkdir -p "$TMP_DIR/scripts"
    cp "$RELEASE_SCRIPT" "$TMP_DIR/scripts/release.sh"
    chmod +x "$TMP_DIR/scripts/release.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Set up a minimal git repo in TMP_DIR with:
#   - main branch, one initial commit
#   - CHANGELOG.md with an [Unreleased] section
#   - addons/go_build/plugin.cfg with version="0.1.0"
#   - verify.sh that exits 0 (no GDScript toolchain needed in tests)
_setup_git_repo() {
    cd "$TMP_DIR"
    "$REAL_GIT" init -b main
    "$REAL_GIT" config user.email "test@gobuild.test"
    "$REAL_GIT" config user.name "GoBuild Test"

    cat > CHANGELOG.md << 'EOF'
# Changelog

## [Unreleased]

### Added
- Some feature

---

## [0.1.0] — 2026-01-01

### Added
- Initial release
EOF

    mkdir -p addons/go_build
    printf '[plugin]\n\nversion="0.1.0"\n' > addons/go_build/plugin.cfg

    # Fake verify.sh — avoids requiring gdparse/gdlint in the test environment.
    printf '#!/usr/bin/env bash\necho "  ✓ All files parsed OK."\necho "✓ Verification passed — safe to commit."\n' \
        > verify.sh
    chmod +x verify.sh

    "$REAL_GIT" add .
    "$REAL_GIT" commit -m "initial"
}

# Prepend a git wrapper to PATH that swallows 'push' and delegates everything
# else to the real git binary, avoiding infinite recursion.
_mock_git_push() {
    mkdir -p "$TMP_DIR/bin"
    cat > "$TMP_DIR/bin/git" << EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "push" ]]; then
    echo "[mocked] git push (no-op)"
    exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
    chmod +x "$TMP_DIR/bin/git"
    export PATH="$TMP_DIR/bin:$PATH"
}

# Run the script under test, forwarding any extra arguments.
_run_release() {
    run bash "$TMP_DIR/scripts/release.sh" "$@"
}

# ---------------------------------------------------------------------------
# Script basics
# ---------------------------------------------------------------------------

@test "release.sh exists" {
    [ -f "$RELEASE_SCRIPT" ]
}

@test "release.sh is executable" {
    [ -x "$RELEASE_SCRIPT" ]
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "exits 1 with usage when no argument is given" {
    _run_release
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Usage"
}

# ---------------------------------------------------------------------------
# Git guards
# ---------------------------------------------------------------------------

@test "exits 1 when not on main branch" {
    _setup_git_repo
    cd "$TMP_DIR"
    "$REAL_GIT" checkout -b feature/something
    _run_release 0.3.0
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "must be on main"
}

@test "exits 1 when working tree has uncommitted changes" {
    _setup_git_repo
    cd "$TMP_DIR"
    echo "dirty" >> CHANGELOG.md
    _run_release 0.3.0
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "uncommitted"
}

@test "exits 1 when the target tag already exists" {
    _setup_git_repo
    cd "$TMP_DIR"
    "$REAL_GIT" tag v0.3.0
    _run_release 0.3.0
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "already exists"
}

# ---------------------------------------------------------------------------
# CHANGELOG guard
# ---------------------------------------------------------------------------

@test "exits 1 when CHANGELOG.md has no Unreleased section" {
    _setup_git_repo
    cd "$TMP_DIR"
    sed -i 's/\[Unreleased\]/[AlreadyReleased]/' CHANGELOG.md
    "$REAL_GIT" add CHANGELOG.md
    "$REAL_GIT" commit -m "remove unreleased"
    _run_release 0.3.0
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "Unreleased"
}

# ---------------------------------------------------------------------------
# File mutations (happy path)
# ---------------------------------------------------------------------------

@test "CHANGELOG.md gets a versioned heading" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    grep -q "## \[0.3.0\]" "$TMP_DIR/CHANGELOG.md"
}

@test "CHANGELOG.md versioned heading contains today's date" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    TODAY=$(date +%Y-%m-%d)
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    grep -q "## \[0.3.0\] — ${TODAY}" "$TMP_DIR/CHANGELOG.md"
}

@test "CHANGELOG.md retains a fresh [Unreleased] section above the new version" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    # [Unreleased] must appear on an earlier line than [0.3.0]
    UNRELEASED_LINE=$(grep -n "## \[Unreleased\]" "$TMP_DIR/CHANGELOG.md" | head -1 | cut -d: -f1)
    VERSIONED_LINE=$(grep -n "## \[0.3.0\]" "$TMP_DIR/CHANGELOG.md" | head -1 | cut -d: -f1)
    [ "$UNRELEASED_LINE" -lt "$VERSIONED_LINE" ]
}

@test "plugin.cfg version= is updated to the new version" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    grep -q 'version="0.3.0"' "$TMP_DIR/addons/go_build/plugin.cfg"
}

@test "plugin.cfg old version is no longer present" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    ! grep -q 'version="0.1.0"' "$TMP_DIR/addons/go_build/plugin.cfg"
}

# ---------------------------------------------------------------------------
# Git output
# ---------------------------------------------------------------------------

@test "creates a git commit with the expected message" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    "$REAL_GIT" -C "$TMP_DIR" log --oneline | grep -q "chore: bump version to v0.3.0"
}

@test "creates an annotated tag" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    "$REAL_GIT" -C "$TMP_DIR" tag | grep -q "^v0.3.0$"
}

@test "tag points to the version-bump commit" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    TAG_SHA=$("$REAL_GIT" -C "$TMP_DIR" rev-parse v0.3.0^{commit})
    HEAD_SHA=$("$REAL_GIT" -C "$TMP_DIR" rev-parse HEAD)
    [ "$TAG_SHA" = "$HEAD_SHA" ]
}

# ---------------------------------------------------------------------------
# Output messages
# ---------------------------------------------------------------------------

@test "prints a success line on completion" {
    _setup_git_repo
    _mock_git_push
    cd "$TMP_DIR"
    _run_release 0.3.0
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Released v0.3.0"
}

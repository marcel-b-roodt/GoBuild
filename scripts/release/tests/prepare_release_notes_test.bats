#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
PREP_SCRIPT="$REPO_ROOT/scripts/release/prepare_release_notes.sh"
REAL_GIT="/usr/bin/git"

setup() {
	TMP_DIR="$(mktemp -d)"
	mkdir -p "$TMP_DIR/scripts/release"
	cp "$PREP_SCRIPT" "$TMP_DIR/scripts/release/prepare_release_notes.sh"
	chmod +x "$TMP_DIR/scripts/release/prepare_release_notes.sh"
}

teardown() {
	rm -rf "$TMP_DIR"
}

_setup_git_repo() {
	cd "$TMP_DIR"
	"$REAL_GIT" init -b main
	"$REAL_GIT" config user.email "test@gobuild.test"
	"$REAL_GIT" config user.name "GoBuild Test"

	cat > CHANGELOG.md << 'EOF'
# Changelog

## [Unreleased]

---

## [0.1.0] — 2026-01-01

### Added
- Initial release
EOF

	printf 'alpha\n' > file.txt
	"$REAL_GIT" add .
	"$REAL_GIT" commit -m "initial"
	"$REAL_GIT" tag v0.1.0

	echo 'beta' >> file.txt
	"$REAL_GIT" add file.txt
	"$REAL_GIT" commit -m "add box projection"

	echo 'gamma' >> file.txt
	"$REAL_GIT" add file.txt
	"$REAL_GIT" commit -m "fix(editor): smooth object mode UV updates"
}

_run_prep() {
	run bash "$TMP_DIR/scripts/release/prepare_release_notes.sh" "$@"
}

@test "prepare_release_notes.sh exists" {
	[ -f "$PREP_SCRIPT" ]
}

@test "writes generated notes into Unreleased by default" {
	_setup_git_repo
	cd "$TMP_DIR"
	_run_prep
	[ "$status" -eq 0 ]
	grep -q "### Added" CHANGELOG.md
	grep -q -- "- add box projection" CHANGELOG.md
	grep -q "### Fixed" CHANGELOG.md
	grep -q -- "- Editor - smooth object mode UV updates" CHANGELOG.md
}

@test "can target a named release section" {
	_setup_git_repo
	cd "$TMP_DIR"
	printf '\n## [0.2.0-dev1] — 2026-02-01\n\n---\n' >> CHANGELOG.md
	_run_prep --section 0.2.0-dev1 --from v0.1.0 --to HEAD
	[ "$status" -eq 0 ]
	grep -q "## \[0.2.0-dev1\]" CHANGELOG.md
	grep -q -- "- add box projection" CHANGELOG.md
}

@test "fails when target section does not exist" {
	_setup_git_repo
	cd "$TMP_DIR"
	_run_prep --section 9.9.9
	[ "$status" -eq 1 ]
	echo "$output" | grep -q "section '9.9.9' not found"
}
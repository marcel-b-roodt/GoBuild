#!/usr/bin/env bash
# prepare_release_notes.sh — draft changelog notes from git history.
#
# Default usage:
#   ./scripts/release/prepare_release_notes.sh
#
# Writes a generated summary of commits since the latest tag into the
# [Unreleased] section of CHANGELOG.md.  Use --section/--from/--to to target a
# specific release section or range.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CHANGELOG_PATH="CHANGELOG.md"
SECTION="Unreleased"
FROM_REF=""
TO_REF="HEAD"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--section)
			SECTION="${2:-}"
			shift 2
			;;
		--from)
			FROM_REF="${2:-}"
			shift 2
			;;
		--to)
			TO_REF="${2:-}"
			shift 2
			;;
		-h|--help)
			cat <<'EOF'
Usage: scripts/release/prepare_release_notes.sh [--section <name>] [--from <ref>] [--to <ref>]

Examples:
  scripts/release/prepare_release_notes.sh
  scripts/release/prepare_release_notes.sh --section 0.5.0-dev1 --from v0.4.1 --to v0.5.0-dev1
EOF
			exit 0
			;;
		*)
			echo "Error: unknown argument '$1'" >&2
			exit 1
			;;
	esac
done

if [[ -z "$SECTION" ]]; then
	echo "Error: --section cannot be empty" >&2
	exit 1
fi

if [[ -z "$FROM_REF" ]]; then
	FROM_REF="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi

RANGE="$TO_REF"
if [[ -n "$FROM_REF" ]]; then
	RANGE="$FROM_REF..$TO_REF"
fi

if ! git rev-parse --verify "$TO_REF" >/dev/null 2>&1; then
	echo "Error: unknown --to ref '$TO_REF'" >&2
	exit 1
fi
if [[ -n "$FROM_REF" ]] && ! git rev-parse --verify "$FROM_REF" >/dev/null 2>&1; then
	echo "Error: unknown --from ref '$FROM_REF'" >&2
	exit 1
fi

prefix="## [$SECTION]"
if ! grep -Fq "$prefix" "$CHANGELOG_PATH"; then
	echo "Error: section '$SECTION' not found in $CHANGELOG_PATH" >&2
	exit 1
fi

format_subject() {
	local subject="$1"
	local scoped_re='^([a-z]+)\(([^)]*)\):[[:space:]]*(.*)$'
	local plain_re='^([a-z]+):[[:space:]]*(.*)$'
	if [[ "$subject" =~ $scoped_re ]]; then
		local scope="${BASH_REMATCH[2]}"
		local text="${BASH_REMATCH[3]}"
		echo "${scope^} - $text"
		return
	fi
	if [[ "$subject" =~ $plain_re ]]; then
		echo "${BASH_REMATCH[2]}"
		return
	fi
	echo "$subject"
}

mapfile -t commits < <(git --no-pager log --reverse --format='%s' $RANGE)

added=()
changed=()
fixed=()
tests=()

for subject in "${commits[@]}"; do
	[[ -z "$subject" ]] && continue
	if [[ "$subject" =~ ^chore:\ bump\ (pre)?release\ version\ to\ v ]]; then
		continue
	fi
	formatted="$(format_subject "$subject")"
	lower="$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')"
	if [[ "$lower" == fix* ]]; then
		fixed+=("$formatted")
	elif [[ "$lower" == test* || "$lower" == tests* || "$lower" == fix\(tests\)* ]]; then
		tests+=("$formatted")
	elif [[ "$lower" == feat* || "$lower" == add* ]]; then
		added+=("$formatted")
	else
		changed+=("$formatted")
	fi
done

tmp_notes="$(mktemp)"
if [[ ${#added[@]} -eq 0 && ${#changed[@]} -eq 0 && ${#fixed[@]} -eq 0 && ${#tests[@]} -eq 0 ]]; then
	printf '### Changed\n- No user-facing changes recorded in `%s`.\n' "$RANGE" > "$tmp_notes"
else
	{
		if [[ ${#added[@]} -gt 0 ]]; then
			echo '### Added'
			for item in "${added[@]}"; do echo "- $item"; done
			echo
		fi
		if [[ ${#changed[@]} -gt 0 ]]; then
			echo '### Changed'
			for item in "${changed[@]}"; do echo "- $item"; done
			echo
		fi
		if [[ ${#fixed[@]} -gt 0 ]]; then
			echo '### Fixed'
			for item in "${fixed[@]}"; do echo "- $item"; done
			echo
		fi
		if [[ ${#tests[@]} -gt 0 ]]; then
			echo '### Tests'
			for item in "${tests[@]}"; do echo "- $item"; done
			echo
		fi
	} > "$tmp_notes"
	# Trim trailing blank line for tidy changelog output.
	perl -0pi -e 's/\n+\z/\n/' "$tmp_notes"
fi

tmp_changelog="$(mktemp)"
awk -v prefix="$prefix" -v notes_file="$tmp_notes" '
	BEGIN { in_section=0; wrote=0 }
	index($0, prefix) == 1 {
		print
		while ((getline line < notes_file) > 0) print line
		in_section=1
		wrote=1
		next
	}
	in_section && /^## \[/ {
		in_section=0
		print
		next
	}
	!in_section { print }
	END {
		if (!wrote) exit 2
	}
' "$CHANGELOG_PATH" > "$tmp_changelog"

mv "$tmp_changelog" "$CHANGELOG_PATH"
rm -f "$tmp_notes"

echo "Prepared release notes in $CHANGELOG_PATH section [$SECTION] from ${FROM_REF:-<root>}..$TO_REF"
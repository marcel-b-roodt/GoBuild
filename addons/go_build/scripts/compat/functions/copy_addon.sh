#!/usr/bin/env bash
# copy_addon.sh — Copy the addon source tree to an output directory.
#
# Arguments:
#   $1 — Source path (e.g. addons/go_build)
#   $2 — Output parent directory
#
# Creates $2/<source_dirname>/ with a clean copy of the addon source.
# Removes any previous copy first.
#
# Source this file, do not execute it directly.

compat::copy_addon() {
	local source="$1"
	local output="$2"
	local dirname="$(basename "${source}")"

	rm -rf "${output}/${dirname}"
	mkdir -p "${output}"
	cp -r "${source}" "${output}/${dirname}"
}

# compat::check_addon_root — Validate that a directory looks like go_build.
# Returns 0 if plugin.cfg exists, exits with error if not.

compat::check_addon_root() {
	local dir="$1"
	if [ ! -f "${dir}/plugin.cfg" ]; then
		echo "Error: Cannot find plugin.cfg at ${dir}" >&2
		echo "       Make sure this script lives inside addons/go_build/scripts/compat/" >&2
		exit 1
	fi
}
#!/usr/bin/env bash

# lib.sh - Shared helpers for the verification scripts
#
# Description:
#   Library meant to be sourced by the other scripts in this directory. It
#   defines logging helpers, name normalization and CSV splitting. It has no
#   side effect when sourced and prints no ANSI colour codes.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Functions:
#   log_ok <message>      - print "✅ <message>" on stdout
#   log_error <message>   - print "❌ <message>" on stderr
#   die <message>         - log_error, then exit 1
#   normalize_name <name> - PEP 503/685 normalization (lowercase, runs of
#                           "-", "_" and "." become a single "-")
#   split_csv <list>      - print one normalized item per line, trimming
#                           spaces and dropping empty items
#   group_start <title>   - open a collapsed GitHub Actions log group
#   group_end             - close the log group
#
# Exit Codes:
#   Functions return 0, except die which exits with 1.

log_ok() {
	echo "✅ $*"
}

log_error() {
	echo "❌ $*" >&2
}

die() {
	log_error "$@"
	exit 1
}

normalize_name() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '._-' '---'
}

split_csv() {
	local item
	local items
	IFS=',' read -r -a items <<<"${1:-}"
	for item in ${items[@]+"${items[@]}"}; do
		# Trim leading and trailing whitespace.
		item="${item#"${item%%[![:space:]]*}"}"
		item="${item%"${item##*[![:space:]]}"}"
		if [ -n "${item}" ]; then
			normalize_name "${item}"
			echo
		fi
	done
}

group_start() {
	echo "::group::$*"
}

group_end() {
	echo "::endgroup::"
}

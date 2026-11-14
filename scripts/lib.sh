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
#   log_error <message>   - print "❌ <message>" on stderr, plus a
#                           "::error::<message>" annotation when
#                           GITHUB_ACTIONS is "true". When REPORT_FILE is
#                           set, also append "error|<message>" to it (the
#                           job summary of verify.sh is built from it)
#   die <message>         - log_error, then exit 1
#   normalize_name <name> - PEP 503/685 normalization (lowercase, runs of
#                           "-", "_" and "." become a single "-")
#   split_csv <list>      - print one normalized item per line, trimming
#                           spaces and dropping empty items
#   default_module_name <package-name>
#                         - import name derived from a distribution name:
#                           "-" and "." replaced by "_"
#   is_dotted_identifier <value>
#                         - succeed if value is a Python module path such as
#                           "a" or "a.b_c" (identifiers separated by dots)
#   is_version_spec <value>
#                         - succeed if value is "latest" or a version such as
#                           "1.2.3", "1.1.414" or "2.0rc1"
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
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		echo "::error::$*"
	fi
	if [ -n "${REPORT_FILE:-}" ]; then
		echo "error|$*" >>"${REPORT_FILE}"
	fi
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

default_module_name() {
	local name="$1"
	name="${name//-/_}"
	echo "${name//./_}"
}

is_dotted_identifier() {
	[[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]
}

is_version_spec() {
	[ "${1:-}" = "latest" ] || [[ "${1:-}" =~ ^[0-9][A-Za-z0-9.!+_-]*$ ]]
}

group_start() {
	echo "::group::$*"
}

group_end() {
	echo "::endgroup::"
}

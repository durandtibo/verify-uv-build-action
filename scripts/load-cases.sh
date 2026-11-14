#!/usr/bin/env bash

# load-cases.sh - Print the test case matrix of tests/cases.json
#
# Description:
#   CI helper. Prints the rows of tests/cases.json as a compact JSON array, to
#   be consumed with fromJson as a GitHub Actions matrix. Rows with a "skip"
#   key are never returned.
#
# Usage:
#   scripts/load-cases.sh <mode> [cases-file]
#
# Arguments:
#   mode        - "all" returns every row, "released" only the rows with
#                 "released": true (cases the last release supports)
#   cases-file  - Optional path of the JSON file (default: tests/cases.json
#                 next to this script's repository root)
#
# Exit Codes:
#   0 - Success
#   2 - Bad usage (unknown mode, missing file, jq not installed)

set -euo pipefail

main() {
	local mode="${1:-}"
	local file="${2:-"$(dirname "${BASH_SOURCE[0]}")/../tests/cases.json"}"
	local filter

	case "$mode" in
	all) filter='map(select(has("skip") | not))' ;;
	released) filter='map(select((has("skip") | not) and .released == true))' ;;
	*)
		echo "❌ Usage: load-cases.sh all|released [cases-file]" >&2
		return 2
		;;
	esac
	if [ ! -f "$file" ]; then
		echo "❌ Cases file not found: $file" >&2
		return 2
	fi
	if ! command -v jq >/dev/null 2>&1; then
		echo "❌ jq is required" >&2
		return 2
	fi
	jq -c "$filter" "$file"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi

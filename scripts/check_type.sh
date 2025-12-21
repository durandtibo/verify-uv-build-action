#!/usr/bin/env bash

# check_type.sh - Verify package type completeness with pyright
#
# Description:
#   This script validates that a Python package has proper type annotations
#   and is marked as typed (py.typed). It uses pyright's --verifytypes feature
#   to analyze the package's public interface and report type completeness.
#
# Usage:
#   ./check_type.sh <package_name>
#
# Arguments:
#   package_name - Name of the package to check (required)
#
# Examples:
#   ./check_type.sh mypackage
#   ./check_type.sh requests
#
# Requirements:
#   - pyright must be installed and available in PATH
#   - The specified package must be installed in the current environment
#
# Exit Codes:
#   0 - Type checking passed successfully
#   1 - Type checking failed or pyright encountered errors
#   2 - Invalid arguments

set -euo pipefail

run_and_show() {
	echo "$ $*"
	echo ""
	"$@"
}

check_type() {
	local package_name="$1"

	echo "🔍 Verifying type completeness for package: ${package_name}"
	echo ""

	# Use pyright's --verifytypes to check type completeness
	# --ignoreexternal: Don't report issues with external dependencies
	run_and_show pyright --verifytypes "${package_name}" --ignoreexternal

	echo "✅ Type hints validated for ${package_name}"
}

main() {
	# Parse arguments
	if [ $# -eq 0 ]; then
		echo "Error: Package name is required" >&2
		echo "Usage: $0 <package_name>" >&2
		exit 2
	fi

	local package_name="$1"
	check_type "${package_name}"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi

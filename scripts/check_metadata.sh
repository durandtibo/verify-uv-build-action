#!/usr/bin/env bash

# check_metadata.sh - Validate package metadata
#
# Description:
#   Checks that the installed package has correct metadata including
#   the package name and required dependencies.
#
# Usage:
#   ./check_metadata.sh PACKAGE_NAME [DEPENDENCIES]
#
# Arguments:
#   PACKAGE_NAME   - Name of the package to check
#   DEPENDENCIES   - Optional comma-separated list of required dependencies
#
# Examples:
#   ./check_metadata.sh myproject
#   ./check_metadata.sh myproject coola
#   ./check_metadata.sh myproject "coola,numpy,pandas"
#
# Requirements:
#   - uv must be installed
#   - Package must be installed in the current environment
#
# Exit Codes:
#   0 - Metadata validation passed
#   1 - Metadata validation failed

set -euo pipefail

# Check if package name argument is provided
if [ $# -lt 1 ]; then
	echo "Error: Package name is required" >&2
	echo "Usage: $0 PACKAGE_NAME [DEPENDENCIES]" >&2
	exit 1
fi

PACKAGE_NAME="$1"
DEPENDENCIES="${2:-}" # Second argument, empty string if not provided

METADATA=$(uv pip show "$PACKAGE_NAME")

echo "$METADATA"
echo ""

# Check package name
if ! echo "$METADATA" | grep -q "Name: $PACKAGE_NAME"; then
	echo "❌ Error: Package name '$PACKAGE_NAME' not found in metadata" >&2
	exit 1
fi
echo "✅ Package name '$PACKAGE_NAME' verified"

# Check dependencies if provided
if [ -n "$DEPENDENCIES" ]; then
	# Split comma-separated string into array
	IFS=',' read -ra DEPS <<<"$DEPENDENCIES"

	for dep in "${DEPS[@]}"; do
		# Trim whitespace from dependency name
		dep=$(echo "$dep" | xargs)

		if ! echo "$METADATA" | grep -q "Requires:.*$dep"; then
			echo "❌ Error: Required dependency '$dep' not found in package metadata" >&2
			exit 1
		fi
		echo "✅ Required dependency '$dep' found"
	done
fi

echo ""
echo "🎉 All metadata validation checks passed for $PACKAGE_NAME"

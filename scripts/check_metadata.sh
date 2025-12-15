#!/usr/bin/env bash

# check_metadata.sh - Validate package metadata
#
# Description:
#   Checks that the installed package has correct metadata including
#   the package name and required dependencies.
#
# Usage:
#   ./check_metadata.sh PACKAGE_NAME [REQUIRED_DEPENDENCY ...]
#
# Arguments:
#   PACKAGE_NAME          - Name of the package to check
#   REQUIRED_DEPENDENCY   - Optional dependency names to verify (can specify multiple)
#
# Examples:
#   ./check_metadata.sh myproject
#   ./check_metadata.sh myproject coola
#   ./check_metadata.sh myproject coola numpy pandas
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
    echo "Usage: $0 PACKAGE_NAME [REQUIRED_DEPENDENCY ...]" >&2
    exit 1
fi

PACKAGE_NAME="$1"
shift  # Remove the first argument, leaving any dependencies

METADATA=$(uv pip show "$PACKAGE_NAME")

echo "$METADATA"
echo ""

# Check package name
echo "$METADATA" | grep -q "Name: $PACKAGE_NAME"

# Check each required dependency if provided
for dep in "$@"; do
    echo "$METADATA" | grep -q "Requires:.*$dep"
done

echo "✅ Metadata validation passed for $PACKAGE_NAME"
#!/usr/bin/env bash

# check_metadata.sh - Validate package metadata
#
# Description:
#   Checks that the installed package has correct metadata including
#   the package name and required dependencies.
#
# Usage:
#   ./check_metadata.sh
#
# Requirements:
#   - uv must be installed
#   - Package must be installed in the current environment
#
# Exit Codes:
#   0 - Metadata validation passed
#   1 - Metadata validation failed

set -euo pipefail

METADATA=$(uv pip show myproject)

echo "$METADATA"

echo "$METADATA" | grep -q "Name: myproject"
echo "$METADATA" | grep -q "Requires: coola"

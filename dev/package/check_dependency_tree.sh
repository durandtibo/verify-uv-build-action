#!/usr/bin/env bash

# check_dependency_tree.sh - Validate package dependency tree
#
# Description:
#   Verifies that the package dependency tree matches expected structure.
#   Checks that dependencies are installed with correct version requirements.
#
# Usage:
#   ./check_dependency_tree.sh
#
# Requirements:
#   - uv must be installed
#   - Package must be installed in the current environment
#
# Exit Codes:
#   0 - Dependency tree validation passed
#   1 - Dependency tree validation failed

set -euo pipefail

OUTPUT=$(uv pip tree --package myproject --show-version-specifiers)
echo "$OUTPUT"

# Define patterns for each line (in order).
PATTERNS=(
  '^myproject v[0-9]+(\.[0-9]+)*[A-Za-z0-9]*$'
  '^└── coola v[0-9]+(\.[0-9]+)*[[:space:]]+\[required:.*\]$'
)

# Number of lines we want to check
MAX_LINES=${#PATTERNS[@]}

# --- Validator ---
i=1
while IFS= read -r line; do
    # Stop once all patterns have been checked
    if (( i > MAX_LINES )); then
        break
    fi

    pattern="${PATTERNS[$((i-1))]}"

    if ! [[ "$line" =~ $pattern ]]; then
        echo "❌ Line $i does NOT match expected pattern"
        echo "   Line content:    '$line'"
        echo "   Expected pattern: $pattern"
        exit 1
    fi

    ((i++))
done <<< "$OUTPUT"

echo "✅ First $MAX_LINES lines match."

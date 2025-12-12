#!/usr/bin/env bash

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

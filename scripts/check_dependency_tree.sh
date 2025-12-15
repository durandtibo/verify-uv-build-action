#!/usr/bin/env bash

# check_dependency_tree.sh - Validate package dependency tree structure
#
# Description:
#   This script verifies that a package has the correct dependency tree structure.
#   It checks that:
#   1. The package is properly installed and recognized
#   2. The expected dependencies are present
#   3. The dependency versions match expected patterns
#
# Usage:
#   ./check_dependency_tree.sh <package_name> [dependencies]
#
#   Arguments:
#     package_name   - Name of the package to check
#     dependencies   - Optional comma-separated list of required dependencies
#
#   Examples:
#     ./check_dependency_tree.sh mypackage requests
#     ./check_dependency_tree.sh mypackage "requests,flask,numpy"
#     ./check_dependency_tree.sh mypackage "requests, flask, numpy"
#
# Requirements:
#   - uv must be installed and available in PATH
#   - The specified package must be installed in the current environment
#
# Exit Codes:
#   0 - Dependency tree validation passed
#   1 - Dependency tree validation failed (unexpected dependencies or versions)
#   2 - Invalid arguments

set -euo pipefail

# Check for minimum arguments
if [ $# -lt 1 ]; then
    echo "❌ ERROR: Missing required arguments"
    echo ""
    echo "Usage: $0 <package_name> [dependencies]"
    echo ""
    echo "Examples:"
    echo "  $0 mypackage \"requests,flask,numpy\""
    exit 2
fi

# First argument is the package name
package="$1"
DEPENDENCIES="${2:-}"  # Second argument, empty string if not provided

# Parse dependencies from comma-separated string
dependencies=()
if [ -n "$DEPENDENCIES" ]; then
    # Split comma-separated string into array
    IFS=',' read -ra DEPS <<< "$DEPENDENCIES"

    # Trim whitespace from each dependency
    for dep in "${DEPS[@]}"; do
        trimmed=$(echo "$dep" | xargs)
        dependencies+=("$trimmed")
    done
fi

# Get the uv pip tree output
tree_output=$(uv pip tree --package "$package" --show-version-specifiers)

echo "Dependency tree for: $package"
echo "$tree_output"
echo ""

# Check if first line matches the pattern
first_line=$(echo "$tree_output" | head -n 1)
if ! echo "$first_line" | grep -qE "^${package} v[0-9]+(\.[0-9]+)*[A-Za-z0-9]*$"; then
    echo "❌ ERROR: First line does not match expected pattern"
    echo "Expected: $package v<version>"
    echo "Got: $first_line"
    exit 1
fi
echo "✅ First line matches pattern: $first_line"
echo ""

# If no dependencies specified, just validate the package exists and exit
if [ ${#dependencies[@]} -eq 0 ]; then
    echo "ℹ️  No dependencies specified to check"
    echo "🎉 Package validation complete!"
    exit 0
fi

# Track results
missing_dependencies=()
found_dependencies=()

# Check each package
for dep in "${dependencies[@]}"; do
    # Match package name at second level (lines starting with ├── or └──)
    # Case-insensitive match for package names
    if echo "$tree_output" | grep -qiE "^[├└]── ${dep} v"; then
        found_dependencies+=("$dep")
        echo "✅ Found: $dep"
    else
        missing_dependencies+=("$dep")
        echo "❌ Missing: $dep"
    fi
done

echo ""
echo "📊 Summary:"
echo " Found: ${#found_dependencies[@]}"
echo " Missing: ${#missing_dependencies[@]}"

# Exit with error if any dependencies are missing
if [ ${#missing_dependencies[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Missing dependencies:"
    printf '  • %s\n' "${missing_dependencies[@]}"
    exit 1
else
    echo ""
    echo "🎉 All dependencies found!"
fi
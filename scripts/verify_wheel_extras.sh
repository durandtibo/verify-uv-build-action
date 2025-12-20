#!/bin/bash
#
# verify_wheel_extras.sh - Verify that extras are defined in wheel metadata
#
# DESCRIPTION:
#   This script extracts and verifies optional dependency extras from a Python
#   wheel file's metadata. It checks that requested extras are properly defined
#   in the built distribution, which is useful for validating your build process
#   and preventing installation issues.
#
# USAGE:
#   verify_wheel_extras.sh <wheel_file> [extra1,extra2,...]
#
# ARGUMENTS:
#   wheel_file    Path to the .whl file to inspect
#   extras        Comma-separated list of extra names to verify (optional)
#                 If no extras are specified, only lists available extras
#
# EXIT CODES:
#   0    All requested extras are defined (or only listing was requested)
#   1    One or more extras are not defined, or file not found
#
# EXAMPLES:
#   # List all extras in a wheel
#   ./verify_wheel_extras.sh dist/coola-0.9.2a0-py3-none-any.whl
#
#   # Check if a single extra exists
#   ./verify_wheel_extras.sh dist/coola-*.whl numpy
#
#   # Check multiple extras at once
#   ./verify_wheel_extras.sh dist/coola-*.whl numpy,pandas,torch
#
#   # Use in a CI pipeline
#   if ./verify_wheel_extras.sh dist/*.whl numpy,pandas; then
#       echo "Extras verified, proceeding with upload..."
#       twine upload dist/*.whl
#   fi
#
# HOW IT WORKS:
#   1. Extracts the wheel file (which is a zip archive) to a temp directory
#   2. Locates the METADATA file inside the *.dist-info directory
#   3. Parses all "Provides-Extra:" lines from the metadata
#   4. Compares requested extras against defined extras
#   5. Returns success only if all requested extras are found
#
# REQUIREMENTS:
#   - unzip command must be available
#   - grep, cut, sort, find standard utilities
#
# NOTES:
#   - The script creates a temporary directory that is automatically cleaned up
#   - Wheel files must have a .whl extension
#   - Extra names are case-sensitive
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#
# Function: usage
# Description: Display usage information and exit
#
usage() {
	echo "Usage: $0 <wheel_file> [extra1,extra2,...]"
	echo ""
	echo "Verify that optional dependency extras are defined in a wheel's metadata."
	echo ""
	echo "Examples:"
	echo "  $0 dist/coola-0.9.2a0-py3-none-any.whl"
	echo "  $0 dist/coola-0.9.2a0-py3-none-any.whl numpy"
	echo "  $0 dist/coola-0.9.2a0-py3-none-any.whl numpy,pandas,torch"
	echo ""
	echo "Exit codes:"
	echo "  0    All requested extras are defined"
	echo "  1    One or more extras are not defined, or file not found"
	exit 1
}

#
# Function: validate_wheel_file
# Description: Check if the wheel file exists and is valid
# Arguments:
#   $1 - Path to wheel file
# Returns:
#   0 if valid, exits with 1 if invalid
#
validate_wheel_file() {
	local wheel_file="$1"

	if [ ! -f "$wheel_file" ]; then
		echo -e "${RED}❌ Error: Wheel file not found: $wheel_file${NC}" >&2
		exit 1
	fi

	if [[ ! "$wheel_file" =~ \.whl$ ]]; then
		echo -e "${RED}❌ Error: File is not a wheel: $wheel_file${NC}" >&2
		exit 1
	fi
}

#
# Function: extract_metadata
# Description: Extract METADATA content from wheel
# Arguments:
#   $1 - Path to wheel file
# Output:
#   Prints the METADATA file content to stdout
# Returns:
#   0 on success, exits with 1 on failure
# Note:
#   Uses unzip -p to read directly without creating temp files
#
extract_metadata() {
	local wheel_file="$1"

	# List contents to find the METADATA file path
	local metadata_path
	metadata_path=$(unzip -l "$wheel_file" 2>/dev/null | grep -o '[^[:space:]]*\.dist-info/METADATA' | head -n 1)

	if [ -z "$metadata_path" ]; then
		echo -e "${RED}❌ Error: Could not find METADATA in wheel${NC}" >&2
		exit 1
	fi

	# Extract and output the METADATA content directly
	unzip -p "$wheel_file" "$metadata_path" 2>/dev/null || {
		echo -e "${RED}❌ Error: Failed to extract METADATA from wheel${NC}" >&2
		exit 1
	}
}

#
# Function: get_defined_extras
# Description: Extract all Provides-Extra entries from METADATA content
# Arguments:
#   $1 - METADATA file content (as string)
# Output:
#   Prints sorted list of extras (one per line)
#
get_defined_extras() {
	local metadata_content="$1"
	echo "$metadata_content" | grep "^Provides-Extra:" | cut -d' ' -f2- | sort || true
}

#
# Function: parse_requested_extras
# Description: Parse comma-separated extras string into array
# Arguments:
#   $1 - Comma-separated string of extras (or empty)
# Output:
#   Prints extras one per line (after trimming whitespace)
#
parse_requested_extras() {
	local extras_string="$1"

	if [ -z "$extras_string" ]; then
		return
	fi

	# Split by comma and trim whitespace, remove empty lines
	echo "$extras_string" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
}

#
# Function: display_extras
# Description: Display all extras defined in the wheel
# Arguments:
#   $1 - Newline-separated list of extras
#
display_extras() {
	local extras="$1"

	if [ -z "$extras" ]; then
		echo ""
		echo -e "${YELLOW}⚠ Warning: No extras defined in wheel${NC}"
		return
	fi

	echo ""
	echo "Extras defined in wheel:"
	echo "========================"
	echo "$extras" | while read -r extra; do
		[ -n "$extra" ] && echo "  - $extra"
	done
	echo ""

	local count
	count=$(echo "$extras" | grep -c '^' || echo "0")
	echo "Total: $count extras"
}

#
# Function: verify_extras
# Description: Verify that all requested extras are defined
# Arguments:
#   $1 - Newline-separated list of defined extras
#   $2 - Newline-separated list of requested extras
# Returns:
#   0 if all extras are valid, 1 if any are invalid
#
verify_extras() {
	local defined_extras="$1"
	local requested_extras="$2"

	if [ -z "$requested_extras" ]; then
		return 0
	fi

	echo ""
	echo "Checking requested extras..."
	echo "============================"

	local all_valid=true

	while IFS= read -r extra; do
		[ -z "$extra" ] && continue

		if echo "$defined_extras" | grep -q "^${extra}$"; then
			echo -e "  ${GREEN}✓${NC} $extra"
		else
			echo -e "  ${RED}✗${NC} $extra - NOT DEFINED"
			all_valid=false
		fi
	done <<<"$requested_extras"

	echo ""

	if [ "$all_valid" = true ]; then
		echo -e "${GREEN}✓ All requested extras are defined in the wheel${NC}"
		return 0
	else
		echo -e "${RED}❌ Some extras are not defined in the wheel${NC}" >&2
		echo ""
		echo "Available extras:"
		echo "$defined_extras" | while read -r extra; do
			[ -n "$extra" ] && echo "  - $extra"
		done
		return 1
	fi
}

#
# Main function
#
main() {
	# Check arguments
	if [ $# -lt 1 ]; then
		usage
	fi

	local wheel_file="$1"
	local extras_arg="${2:-}"

	# Validate wheel file
	validate_wheel_file "$wheel_file"

	echo "Extracting metadata from: $(basename "$wheel_file")"

	# Extract and parse metadata
	local metadata_content
	metadata_content=$(extract_metadata "$wheel_file")

	local defined_extras
	defined_extras=$(get_defined_extras "$metadata_content")

	# Check if no extras defined and user requested some
	if [ -z "$defined_extras" ] && [ -n "$extras_arg" ]; then
		echo ""
		echo -e "${YELLOW}⚠ Warning: No extras defined in wheel${NC}"
		echo -e "${RED}❌ Requested extras but none are defined${NC}" >&2
		exit 1
	fi

	# Display all defined extras
	display_extras "$defined_extras"

	# If no extras requested, exit successfully
	if [ -z "$extras_arg" ]; then
		exit 0
	fi

	# Parse and verify requested extras
	local requested_extras
	requested_extras=$(parse_requested_extras "$extras_arg")

	if verify_extras "$defined_extras" "$requested_extras"; then
		exit 0
	else
		exit 1
	fi
}

# Run main function if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	main "$@"
fi

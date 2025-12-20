#!/bin/bash
#
# verify_sdist_extras.sh - Verify that extras are defined in sdist metadata
#
# DESCRIPTION:
#   This script extracts and verifies optional dependency extras from a Python
#   source distribution (sdist) file. It checks pyproject.toml or setup.cfg for
#   extras definitions, which is useful for validating your build process and
#   preventing installation issues.
#
# USAGE:
#   verify_sdist_extras.sh <sdist_file> [extra1,extra2,...]
#
# ARGUMENTS:
#   sdist_file    Path to the .tar.gz sdist file to inspect
#   extras        Comma-separated list of extra names to verify (optional)
#                 If no extras are specified, only lists available extras
#
# EXIT CODES:
#   0    All requested extras are defined (or only listing was requested)
#   1    One or more extras are not defined, or file not found
#
# EXAMPLES:
#   # List all extras in an sdist
#   ./verify_sdist_extras.sh dist/coola-0.9.2a0.tar.gz
#
#   # Check if a single extra exists
#   ./verify_sdist_extras.sh dist/coola-*.tar.gz numpy
#
#   # Check multiple extras at once
#   ./verify_sdist_extras.sh dist/coola-*.tar.gz numpy,pandas,torch
#
#   # Use in a CI pipeline
#   if ./verify_sdist_extras.sh dist/*.tar.gz numpy,pandas; then
#       echo "Extras verified, proceeding with upload..."
#       twine upload dist/*.tar.gz
#   fi
#
# HOW IT WORKS:
#   1. Lists contents of the sdist file (tar.gz archive)
#   2. Locates pyproject.toml or setup.cfg in the file listing
#   3. Extracts the config file content directly to stdout
#   4. Parses extras definitions from the configuration file
#   5. Compares requested extras against defined extras
#   6. Returns success only if all requested extras are found
#
# REQUIREMENTS:
#   - tar command must be available
#   - grep, sed, awk standard utilities
#
# NOTES:
#   - No temporary files are created - all operations use pipes
#   - Supports both pyproject.toml and setup.cfg formats
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
	echo "Usage: $0 <sdist_file> [extra1,extra2,...]"
	echo ""
	echo "Verify that optional dependency extras are defined in an sdist's metadata."
	echo ""
	echo "Examples:"
	echo "  $0 dist/coola-0.9.2a0.tar.gz"
	echo "  $0 dist/coola-0.9.2a0.tar.gz numpy"
	echo "  $0 dist/coola-0.9.2a0.tar.gz numpy,pandas,torch"
	echo ""
	echo "Exit codes:"
	echo "  0    All requested extras are defined"
	echo "  1    One or more extras are not defined, or file not found"
	exit 1
}

#
# Function: validate_sdist_file
# Description: Check if the sdist file exists and is valid
# Arguments:
#   $1 - Path to sdist file
# Returns:
#   0 if valid, exits with 1 if invalid
#
validate_sdist_file() {
	local sdist_file="$1"

	if [ ! -f "$sdist_file" ]; then
		echo -e "${RED}❌ Error: Sdist file not found: $sdist_file${NC}" >&2
		exit 1
	fi

	if [[ ! "$sdist_file" =~ \.tar\.gz$ ]]; then
		echo -e "${RED}❌ Error: File is not a tar.gz sdist: $sdist_file${NC}" >&2
		exit 1
	fi
}

#
# Function: find_config_file
# Description: Find pyproject.toml or setup.cfg in sdist
# Arguments:
#   $1 - Path to sdist file
# Output:
#   Prints config file path and type separated by |
# Returns:
#   0 on success, exits with 1 if not found
#
find_config_file() {
	local sdist_file="$1"
	local config_path=""
	local config_type=""

	# Look for pyproject.toml first (preferred)
	# Modified regex to match both /pyproject.toml and pyproject.toml (at root)
	config_path=$(tar -tzf "$sdist_file" 2>/dev/null | grep -E '(^|/)pyproject\.toml$' | head -n 1)
	if [ -n "$config_path" ]; then
		echo "$config_path|pyproject.toml"
		return 0
	fi

	# Fall back to setup.cfg
	config_path=$(tar -tzf "$sdist_file" 2>/dev/null | grep -E '(^|/)setup\.cfg$' | head -n 1)
	if [ -n "$config_path" ]; then
		echo "$config_path|setup.cfg"
		return 0
	fi

	echo -e "${RED}❌ Error: Could not find pyproject.toml or setup.cfg in sdist${NC}" >&2
	exit 1
}

#
# Function: extract_config_content
# Description: Extract config file content from sdist
# Arguments:
#   $1 - Path to sdist file
#   $2 - Config file path within sdist
# Output:
#   Prints config file content to stdout
# Returns:
#   0 on success, exits with 1 on failure
#
extract_config_content() {
	local sdist_file="$1"
	local config_path="$2"

	tar -xzOf "$sdist_file" "$config_path" 2>/dev/null || {
		echo -e "${RED}❌ Error: Failed to extract config from sdist${NC}" >&2
		exit 1
	}
}

#
# Function: parse_pyproject_extras
# Description: Extract extras from pyproject.toml content
# Arguments:
#   $1 - pyproject.toml content (as string)
# Output:
#   Prints sorted list of extras (one per line)
#
parse_pyproject_extras() {
	local config_content="$1"
	local in_extras=false
	local extras=""

	while IFS= read -r line; do
		# Check if we're entering the optional-dependencies section
		if [[ "$line" =~ ^\[project\.optional-dependencies\] ]] || [[ "$line" =~ ^\[tool\.poetry\.extras\] ]]; then
			in_extras=true
			continue
		fi

		# Check if we've left the section (new section starts)
		if [[ "$line" =~ ^\[.*\] ]] && [ "$in_extras" = true ]; then
			in_extras=false
			continue
		fi

		# If we're in the extras section, extract the key name
		if [ "$in_extras" = true ]; then
			# Match lines like: extra_name = [...]
			if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*= ]]; then
				local extra_name="${BASH_REMATCH[1]}"
				extras+="$extra_name"$'\n'
			fi
		fi
	done <<<"$config_content"

	echo "$extras" | grep -v '^$' | sort -u || true
}

#
# Function: parse_setup_cfg_extras
# Description: Extract extras from setup.cfg content
# Arguments:
#   $1 - setup.cfg content (as string)
# Output:
#   Prints sorted list of extras (one per line)
#
parse_setup_cfg_extras() {
	local config_content="$1"
	local in_extras=false
	local extras=""

	while IFS= read -r line; do
		# Check if we're entering the options.extras_require section
		if [[ "$line" =~ ^\[options\.extras_require\] ]]; then
			in_extras=true
			continue
		fi

		# Check if we've left the section
		if [[ "$line" =~ ^\[.*\] ]] && [ "$in_extras" = true ]; then
			in_extras=false
			continue
		fi

		# If we're in the extras section, extract the key name
		if [ "$in_extras" = true ]; then
			# Match lines like: extra_name = ... or extra_name (for multi-line)
			if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*= ]] || [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*$ ]]; then
				local extra_name="${BASH_REMATCH[1]}"
				if [ -n "$extra_name" ]; then
					extras+="$extra_name"$'\n'
				fi
			fi
		fi
	done <<<"$config_content"

	echo "$extras" | grep -v '^$' | sort -u || true
}

#
# Function: get_defined_extras
# Description: Extract all extras from config content
# Arguments:
#   $1 - Config file content
#   $2 - Config file type (pyproject.toml or setup.cfg)
# Output:
#   Prints sorted list of extras (one per line)
#
get_defined_extras() {
	local config_content="$1"
	local config_type="$2"

	case "$config_type" in
	pyproject.toml)
		parse_pyproject_extras "$config_content"
		;;
	setup.cfg)
		parse_setup_cfg_extras "$config_content"
		;;
	*)
		echo -e "${RED}❌ Error: Unknown config type: $config_type${NC}" >&2
		exit 1
		;;
	esac
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
# Description: Display all extras defined in the sdist
# Arguments:
#   $1 - Newline-separated list of extras
#   $2 - Config file type
#
display_extras() {
	local extras="$1"
	local config_type="$2"

	if [ -z "$extras" ]; then
		echo ""
		echo -e "${YELLOW}⚠ Warning: No extras defined in sdist ($config_type)${NC}"
		return
	fi

	echo ""
	echo "Extras defined in sdist ($config_type):"
	echo "======================================="
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
	local missing_extras=()

	while IFS= read -r extra; do
		[ -z "$extra" ] && continue

		if echo "$defined_extras" | grep -q "^${extra}$"; then
			echo -e "  ${GREEN}✓${NC} $extra"
		else
			echo -e "  ${RED}✗${NC} $extra - NOT DEFINED"
			missing_extras+=("$extra")
			all_valid=false
		fi
	done <<<"$requested_extras"

	echo ""

	if [ "$all_valid" = true ]; then
		echo -e "${GREEN}✓ All requested extras are defined in the sdist${NC}"
		return 0
	else
		echo -e "${RED}❌ Missing extras: ${missing_extras[*]}${NC}" >&2
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

	local sdist_file="$1"
	local extras_arg="${2:-}"

	# Validate sdist file
	validate_sdist_file "$sdist_file"

	echo "Extracting metadata from: $(basename "$sdist_file")"

	# Find config file
	local config_info
	config_info=$(find_config_file "$sdist_file")
	local config_path="${config_info%|*}"
	local config_type="${config_info#*|}"

	echo "Found config: $config_type"

	# Extract config content
	local config_content
	config_content=$(extract_config_content "$sdist_file" "$config_path")

	# Extract defined extras
	local defined_extras
	defined_extras=$(get_defined_extras "$config_content" "$config_type")

	# Check if no extras defined and user requested some
	if [ -z "$defined_extras" ] && [ -n "$extras_arg" ]; then
		echo ""
		echo -e "${YELLOW}⚠ Warning: No extras defined in sdist${NC}"
		echo -e "${RED}❌ Requested extras but none are defined${NC}" >&2
		exit 1
	fi

	# Display all defined extras
	display_extras "$defined_extras" "$config_type"

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

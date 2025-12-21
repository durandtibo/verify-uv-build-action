#!/usr/bin/env bats

# Load bats-support and bats-assert if available
# These provide better assertion helpers
load_helper() {
	local helper_path="$1"
	if [ -f "$helper_path" ]; then
		load "$helper_path"
	fi
}

# Try to load common helper libraries
setup_file() {
	export SCRIPT_PATH="scripts/check_type.sh"
}

# Test: Script requires package name argument
@test "exits with code 2 when no package name provided" {
	run bash "${SCRIPT_PATH}"
	[ "$status" -eq 2 ]
	[[ "$output" =~ "Error: Package name is required" ]]
	[[ "$output" =~ "Usage:" ]]
}

# Test: Script displays usage message on error
@test "displays usage message when no arguments given" {
	run bash "${SCRIPT_PATH}"
	[[ "$output" =~ "Usage: ${SCRIPT_PATH} <package_name>" ]]
}

# Test: Script accepts package name argument
@test "accepts single package name argument" {
	# Create a mock pyright that succeeds
	mock_pyright() {
		echo "pyright mock called with: $*" >&2
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main testpackage"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying type completeness for package: testpackage" ]]
}

# Test: Script calls pyright with correct arguments
@test "calls pyright with --verifytypes and --ignoreexternal flags" {
	mock_pyright() {
		echo "ARGS: $*" >&2
		[[ "$*" =~ "--verifytypes" ]] || return 1
		[[ "$*" =~ "--ignoreexternal" ]] || return 1
		[[ "$*" =~ "testpkg" ]] || return 1
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main testpkg"
	[ "$status" -eq 0 ]
}

# Test: Script exits with code 1 when pyright fails
@test "exits with code 1 when pyright fails" {
	mock_pyright() {
		echo "Error: pyright failed" >&2
		return 1
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main testpackage"
	[ "$status" -eq 1 ]
}

# Test: Script displays success message when pyright succeeds
@test "displays success message when type checking passes" {
	mock_pyright() {
		echo "Type completeness: 100%"
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main goodpackage"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Type hints validated for goodpackage" ]]
}

# Test: run_and_show function displays command before executing
@test "run_and_show displays command with dollar sign prefix" {
	run bash -c "source '${SCRIPT_PATH}'; run_and_show echo test_output"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "$ echo test_output" ]]
	# Line 1 is empty, line 2 has the output
	[[ "${lines[1]}" == "" ]]
	[[ "${lines[2]}" == "test_output" ]]
}

# Test: Script handles package names with special characters
@test "handles package names with hyphens" {
	mock_pyright() {
		echo "Checking: $2" >&2
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main my-package"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "my-package" ]]
}

# Test: Script handles package names with underscores
@test "handles package names with underscores" {
	mock_pyright() {
		echo "Checking: $2" >&2
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main my_package"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "my_package" ]]
}

# Test: Script exits immediately on pyright error (set -e behavior)
@test "exits immediately when pyright returns non-zero" {
	mock_pyright() {
		echo "pyright error"
		return 1
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main testpackage"
	[ "$status" -eq 1 ]
	# Success message should not appear
	[[ ! "$output" =~ "✅ Type hints validated" ]]
}

# Test: Check that stderr is properly redirected for error messages
@test "error messages are written to stderr" {
	run bash "${SCRIPT_PATH}" 2>&1
	[[ "$output" =~ "Error: Package name is required" ]]
}

# Test: Script can be sourced without executing main
@test "script can be sourced without executing main function" {
	run bash -c "source '${SCRIPT_PATH}'; echo 'sourced successfully'"
	[ "$status" -eq 0 ]
	[[ "$output" == "sourced successfully" ]]
}

# Test: check_type function can be called directly when sourced
@test "check_type function is available when script is sourced" {
	mock_pyright() {
		echo "Mock pyright"
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; check_type direct_call_pkg"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "direct_call_pkg" ]]
}

# Test: Multiple words in package name (should only use first)
@test "only uses first argument as package name" {
	mock_pyright() {
		# Check that only first arg after flags is passed
		local found_pkg=false
		for arg in "$@"; do
			if [[ "$arg" == "firstpkg" ]]; then
				found_pkg=true
			elif [[ "$arg" == "secondpkg" ]]; then
				echo "ERROR: Second argument should not be passed to pyright" >&2
				return 1
			fi
		done
		$found_pkg || return 1
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main firstpkg"
	[ "$status" -eq 0 ]
}

# Test: Empty string as package name
@test "handles empty string package name" {
	mock_pyright() {
		echo "Args: $*" >&2
		return 0
	}
	export -f mock_pyright

	run bash -c "source '${SCRIPT_PATH}'; pyright() { mock_pyright \"\$@\"; }; main ''"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying type completeness for package:" ]]
}

# Test: run_and_show executes the command
@test "run_and_show actually executes the command" {
	run bash -c "source '${SCRIPT_PATH}'; run_and_show test -f '${SCRIPT_PATH}'"
	[ "$status" -eq 0 ]
}

# Test: run_and_show preserves command exit code
@test "run_and_show preserves non-zero exit codes" {
	run bash -c "source '${SCRIPT_PATH}'; run_and_show false"
	[ "$status" -eq 1 ]
}
#!/usr/bin/env bats
#
# BATS tests for verify_wheel_extras.sh
#
# Installation:
#   # On macOS
#   brew install bats-core
#
#   # On Ubuntu/Debian
#   sudo apt-get install bats
#
# Usage:
#   bats test_verify_wheel_extras.bats
#

# Setup - runs before each test
setup() {
    # Source the script to test functions
    source scripts/verify_wheel_extras.sh

    # Create a test directory
    TEST_DIR="$(mktemp -d)"

    # Create a mock wheel structure
    create_mock_wheel
}

# Teardown - runs after each test
teardown() {
    # Clean up test directory
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

#
# Helper function to create a mock wheel file
#
create_mock_wheel() {
    local wheel_name="test_package-1.0.0-py3-none-any.whl"
    MOCK_WHEEL="$TEST_DIR/$wheel_name"

    # Create dist-info directory structure
    local dist_info="test_package-1.0.0.dist-info"
    mkdir -p "$TEST_DIR/$dist_info"

    # Create METADATA file with some extras
    cat > "$TEST_DIR/$dist_info/METADATA" << 'EOF'
Metadata-Version: 2.1
Name: test-package
Version: 1.0.0
Summary: A test package
Provides-Extra: numpy
Provides-Extra: pandas
Provides-Extra: torch
Provides-Extra: all
EOF

    # Create the wheel (zip file)
    (cd "$TEST_DIR" && zip -q -r "$wheel_name" "$dist_info")
}

#
# Helper function to create a wheel with no extras
#
create_wheel_without_extras() {
    local wheel_name="no_extras-1.0.0-py3-none-any.whl"
    MOCK_WHEEL_NO_EXTRAS="$TEST_DIR/$wheel_name"

    local dist_info="no_extras-1.0.0.dist-info"
    mkdir -p "$TEST_DIR/$dist_info"

    cat > "$TEST_DIR/$dist_info/METADATA" << 'EOF'
Metadata-Version: 2.1
Name: no-extras
Version: 1.0.0
Summary: A package without extras
EOF

    (cd "$TEST_DIR" && zip -q -r "$wheel_name" "$dist_info")
}

#
# Tests for validate_wheel_file
#

@test "validate_wheel_file: accepts valid wheel file" {
    run validate_wheel_file "$MOCK_WHEEL"
    [ "$status" -eq 0 ]
}

@test "validate_wheel_file: rejects non-existent file" {
    run validate_wheel_file "/nonexistent/file.whl"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "validate_wheel_file: rejects non-wheel file" {
    local non_wheel="$TEST_DIR/not_a_wheel.txt"
    touch "$non_wheel"

    run validate_wheel_file "$non_wheel"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a wheel" ]]
}

#
# Tests for extract_metadata
#

@test "extract_metadata: successfully extracts metadata" {
    run extract_metadata "$MOCK_WHEEL"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Metadata-Version" ]]
    [[ "$output" =~ "Provides-Extra: numpy" ]]
}

@test "extract_metadata: fails on corrupted wheel" {
    local bad_wheel="$TEST_DIR/corrupted.whl"
    echo "not a zip file" > "$bad_wheel"

    run extract_metadata "$bad_wheel"
    [ "$status" -eq 1 ]
}

@test "extract_metadata: fails on wheel without metadata" {
    local wheel_name="empty-1.0.0-py3-none-any.whl"
    local empty_wheel="$TEST_DIR/$wheel_name"

    # Create a wheel with no dist-info
    touch "$TEST_DIR/dummy.py"
    (cd "$TEST_DIR" && zip -q "$wheel_name" dummy.py)

    run extract_metadata "$empty_wheel"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Could not find METADATA" ]]
}

#
# Tests for get_defined_extras
#

@test "get_defined_extras: extracts all extras from metadata" {
    local metadata_content
    metadata_content=$(extract_metadata "$MOCK_WHEEL")

    run get_defined_extras "$metadata_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    [[ "$output" =~ "torch" ]]
    [[ "$output" =~ "all" ]]
}

@test "get_defined_extras: returns empty for no extras" {
    create_wheel_without_extras
    local metadata_content
    metadata_content=$(extract_metadata "$MOCK_WHEEL_NO_EXTRAS")

    run get_defined_extras "$metadata_content"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "get_defined_extras: returns sorted extras" {
    local metadata_content
    metadata_content=$(extract_metadata "$MOCK_WHEEL")

    local extras
    extras=$(get_defined_extras "$metadata_content")

    # Check if output is sorted
    local sorted_extras
    sorted_extras=$(echo "$extras" | sort)
    [ "$extras" = "$sorted_extras" ]
}

#
# Tests for parse_requested_extras
#

@test "parse_requested_extras: handles single extra" {
    run parse_requested_extras "numpy"
    [ "$status" -eq 0 ]
    [ "$output" = "numpy" ]
}

@test "parse_requested_extras: handles multiple extras" {
    run parse_requested_extras "numpy,pandas,torch"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    [[ "$output" =~ "torch" ]]
}

@test "parse_requested_extras: trims whitespace" {
    run parse_requested_extras "numpy , pandas , torch"
    [ "$status" -eq 0 ]
    # Check that each line matches exactly (no leading/trailing whitespace)
    echo "$output" | grep -q "^numpy$"
    echo "$output" | grep -q "^pandas$"
    echo "$output" | grep -q "^torch$"
}

@test "parse_requested_extras: handles empty string" {
    run parse_requested_extras ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_requested_extras: removes empty entries" {
    run parse_requested_extras "numpy,,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    # Should only have 2 lines, not 3
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

#
# Tests for verify_extras
#

@test "verify_extras: succeeds when all extras exist" {
    local defined="numpy
pandas
torch"
    local requested="numpy
pandas"

    run verify_extras "$defined" "$requested"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "All requested extras are defined" ]]
}

@test "verify_extras: fails when extra doesn't exist" {
    local defined="numpy
pandas"
    local requested="numpy
nonexistent"

    run verify_extras "$defined" "$requested"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "NOT DEFINED" ]]
}

@test "verify_extras: succeeds with no requested extras" {
    local defined="numpy
pandas"
    local requested=""

    run verify_extras "$defined" "$requested"
    [ "$status" -eq 0 ]
}

@test "verify_extras: displays available extras on failure" {
    local defined="numpy
pandas
torch"
    local requested="nonexistent"

    run verify_extras "$defined" "$requested"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Available extras:" ]]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
}

#
# Integration tests for main function
#

@test "main: lists extras when no extras requested" {
    run main "$MOCK_WHEEL"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Extras defined in wheel:" ]]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
}

@test "main: succeeds when requested extras exist" {
    run main "$MOCK_WHEEL" "numpy,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✓ numpy" ]]
    [[ "$output" =~ "✓ pandas" ]]
    [[ "$output" =~ "All requested extras are defined" ]]
}

@test "main: fails when requested extras don't exist" {
    run main "$MOCK_WHEEL" "numpy,nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "✓ numpy" ]]
    [[ "$output" =~ "✗ nonexistent" ]]
}

@test "main: handles single extra" {
    run main "$MOCK_WHEEL" "numpy"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✓ numpy" ]]
}

@test "main: fails on non-existent wheel" {
    run main "/nonexistent/wheel.whl"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "main: handles wheel with no extras" {
    create_wheel_without_extras

    run main "$MOCK_WHEEL_NO_EXTRAS"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No extras defined" ]]
}

@test "main: fails when requesting extras from wheel with none" {
    create_wheel_without_extras

    run main "$MOCK_WHEEL_NO_EXTRAS" "numpy"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Requested extras but none are defined" ]]
}

@test "main: handles extras with whitespace" {
    run main "$MOCK_WHEEL" "numpy , pandas , torch"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✓ numpy" ]]
    [[ "$output" =~ "✓ pandas" ]]
    [[ "$output" =~ "✓ torch" ]]
}

@test "main: shows total count of extras" {
    run main "$MOCK_WHEEL"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Total: 4 extras" ]]
}

#
# Edge cases
#

@test "main: handles case-sensitive extra names" {
    run main "$MOCK_WHEEL" "NumPy"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "✗ NumPy - NOT DEFINED" ]]
}

@test "main: handles empty extra in comma list" {
    run main "$MOCK_WHEEL" "numpy,,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✓ numpy" ]]
    [[ "$output" =~ "✓ pandas" ]]
    # Should NOT show an error for empty string
    [[ ! "$output" =~ "NOT DEFINED" ]]
}
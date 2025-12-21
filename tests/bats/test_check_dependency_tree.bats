#!/usr/bin/env bats

# Test suite for check_dependency_tree.sh
#
# Setup requirements:
#   - bats-core must be installed
#   - Tests will modify PATH to inject mock uv command

# Setup and teardown
setup() {
    # Path to the script being tested
    SCRIPT="scripts/check_dependency_tree.sh"

    # Create a temporary directory for test outputs
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Disable colors for consistent test output
    export NO_COLOR=1

    # Create mock uv command that will be found first in PATH
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"

    cat > "$MOCK_BIN_DIR/uv" << 'EOF'
#!/usr/bin/env bash
# Mock uv command for testing
if [ "$1" = "pip" ] && [ "$2" = "tree" ]; then
    if [ -f "$TEST_TEMP_DIR/uv_output.txt" ]; then
        cat "$TEST_TEMP_DIR/uv_output.txt"
    else
        echo "Error: No mock output configured" >&2
        exit 1
    fi
else
    echo "Mock uv: unsupported command $*" >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/uv"

    # Prepend mock bin directory to PATH so our mock is found first
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    # Clean up temporary directory
    if [ -n "${TEST_TEMP_DIR:-}" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper to create mock uv output
create_mock_uv_output() {
    local content="$1"
    echo "$content" > "$TEST_TEMP_DIR/uv_output.txt"
}

###########################################
# Argument Validation Tests
###########################################

@test "exits with code 2 when no arguments provided" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "ERROR: Missing required arguments"
}

@test "shows usage message when no arguments provided" {
    run "$SCRIPT"
    echo "$output" | grep -q "Usage:"
    echo "$output" | grep -q "Examples:"
}

@test "accepts package name only" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
}

@test "accepts package name with dependencies" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "requests,flask"
    [ "$status" -eq 0 ]
}

###########################################
# Package Validation Tests
###########################################

@test "validates package with simple version format" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "First line matches pattern"
}

@test "validates package with complex version format" {
    create_mock_uv_output "mypackage v1.2.3.4rc5"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "First line matches pattern"
}

@test "fails when package format is incorrect" {
    create_mock_uv_output "mypackage 1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "ERROR: First line does not match expected pattern"
}

@test "fails when package name doesn't match" {
    create_mock_uv_output "wrongpackage v1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 1 ]
}

###########################################
# Dependency Checking Tests
###########################################

@test "finds single dependency" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: requests"
}

@test "finds multiple dependencies" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
├── flask v2.0.0
└── numpy v1.21.0"

    run "$SCRIPT" mypackage "requests,flask,numpy"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: requests"
    echo "$output" | grep -q "Found: flask"
    echo "$output" | grep -q "Found: numpy"
}

@test "detects missing dependency" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests,flask"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Missing: flask"
}

@test "handles dependencies with spaces in comma-separated list" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "requests, flask"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: requests"
    echo "$output" | grep -q "Found: flask"
}

@test "handles case-insensitive dependency matching" {
    create_mock_uv_output "mypackage v1.0.0
├── Requests v2.28.0
└── Flask v2.0.0"

    run "$SCRIPT" mypackage "requests,flask"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: requests"
    echo "$output" | grep -q "Found: flask"
}

@test "handles last dependency with └── prefix" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "flask"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: flask"
}

###########################################
# Output Format Tests
###########################################

@test "displays dependency tree" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage
    echo "$output" | grep -q "Dependency tree for: mypackage"
    echo "$output" | grep -q "mypackage v1.0.0"
}

@test "displays summary with found count" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "requests,flask"
    echo "$output" | grep -q "Summary:"
    echo "$output" | grep -q "Found: 2"
    echo "$output" | grep -q "Missing: 0"
}

@test "displays summary with missing count" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests,flask,numpy"
    echo "$output" | grep -q "Summary:"
    echo "$output" | grep -q "Found: 1"
    echo "$output" | grep -q "Missing: 2"
}

@test "shows success message when all dependencies found" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests"
    echo "$output" | grep -q "All dependencies found!"
}

@test "lists missing dependencies" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "flask,numpy"
    echo "$output" | grep -q "Missing dependencies:"
    echo "$output" | grep -q "flask"
    echo "$output" | grep -q "numpy"
}

@test "shows info message when no dependencies specified" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage
    echo "$output" | grep -q "No dependencies specified to check"
    echo "$output" | grep -q "Package validation complete!"
}

###########################################
# Edge Cases
###########################################

@test "handles empty dependency string" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage ""
    [ "$status" -eq 0 ]
}

@test "handles package with hyphenated name" {
    create_mock_uv_output "my-package v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" my-package "requests"
    [ "$status" -eq 0 ]
}

@test "handles dependency with hyphenated name" {
    create_mock_uv_output "mypackage v1.0.0
├── my-dep v1.0.0"

    run "$SCRIPT" mypackage "my-dep"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: my-dep"
}

@test "handles version with pre-release tags" {
    create_mock_uv_output "mypackage v1.0.0rc1
├── requests v2.28.0b2"

    run "$SCRIPT" mypackage "requests"
    [ "$status" -eq 0 ]
}

@test "handles single digit version" {
    create_mock_uv_output "mypackage v1"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
}

@test "handles version with dev suffix" {
    create_mock_uv_output "mypackage v1.0.0dev5"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
}

@test "handles package with underscore name" {
    create_mock_uv_output "my_package v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" my_package "requests"
    [ "$status" -eq 0 ]
}

###########################################
# Multiple Missing Dependencies
###########################################

@test "reports multiple missing dependencies correctly" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests,flask,numpy,pandas"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Found: 1"
    echo "$output" | grep -q "Missing: 3"
}

@test "handles all dependencies missing" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage "flask,numpy,pandas"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Found: 0"
    echo "$output" | grep -q "Missing: 3"
}

###########################################
# Exit Code Tests
###########################################

@test "exits with 0 when validation passes" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests"
    [ "$status" -eq 0 ]
}

@test "exits with 1 when dependencies missing" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage "requests"
    [ "$status" -eq 1 ]
}

@test "exits with 1 when package format invalid" {
    create_mock_uv_output "mypackage 1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 1 ]
}

@test "exits with 2 when arguments invalid" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "exits with 0 for package only validation" {
    create_mock_uv_output "mypackage v1.0.0"

    run "$SCRIPT" mypackage
    [ "$status" -eq 0 ]
}

###########################################
# Complex Dependency Trees
###########################################

@test "handles nested dependencies in tree" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
│   ├── charset-normalizer v2.0.0
│   └── urllib3 v1.26.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "requests,flask"
    [ "$status" -eq 0 ]
}

@test "only checks first-level dependencies" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
│   └── urllib3 v1.26.0
└── flask v2.0.0"

    # urllib3 is nested, not first-level
    run "$SCRIPT" mypackage "urllib3"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Missing: urllib3"
}

###########################################
# Whitespace Handling
###########################################

@test "handles extra spaces around commas" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "  requests  ,  flask  "
    [ "$status" -eq 0 ]
}

@test "handles tabs in dependency list" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "$(printf 'requests\t')"
    [ "$status" -eq 0 ]
}

###########################################
# Error Handling
###########################################

@test "handles uv command failure gracefully" {
    # Don't create mock output - let uv fail
    rm -f "$TEST_TEMP_DIR/uv_output.txt"

    run "$SCRIPT" nonexistent
    [ "$status" -ne 0 ]
}

@test "shows package name in output" {
    create_mock_uv_output "testpkg v2.0.0"

    run "$SCRIPT" testpkg
    echo "$output" | grep -q "testpkg"
}

###########################################
# Additional Edge Cases
###########################################

@test "handles dependency names that are substrings of each other" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── requests-mock v1.9.0"

    run "$SCRIPT" mypackage "requests"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Found: requests"
}

@test "handles multiple commas in dependency list" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0
└── flask v2.0.0"

    run "$SCRIPT" mypackage "requests,,flask"
    [ "$status" -eq 0 ]
}

@test "handles trailing comma in dependency list" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage "requests,"
    [ "$status" -eq 0 ]
}

@test "handles leading comma in dependency list" {
    create_mock_uv_output "mypackage v1.0.0
├── requests v2.28.0"

    run "$SCRIPT" mypackage ",requests"
    [ "$status" -eq 0 ]
}
#!/usr/bin/env bats
#
# BATS tests for verify_sdist_extras.sh
#
# Installation:
#   # On macOS
#   brew install bats-core
#
#   # On Ubuntu/Debian
#   sudo apt-get install bats
#
# Usage:
#   bats test_verify_sdist_extras.bats
#

# Setup - runs before each test
setup() {
    # Source the script to test functions
    source scripts/verify_sdist_extras.sh

    # Create a test directory
    TEST_DIR="$(mktemp -d)"

    # Create mock sdist files
    create_mock_sdist_pyproject
    create_mock_sdist_setup_cfg
}

# Teardown - runs after each test
teardown() {
    # Clean up test directory
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

#
# Helper function to create a mock sdist with pyproject.toml
#
create_mock_sdist_pyproject() {
    local sdist_name="test_package-1.0.0"
    MOCK_SDIST_PYPROJECT="$TEST_DIR/${sdist_name}.tar.gz"

    # Create package directory structure
    mkdir -p "$TEST_DIR/$sdist_name"

    # Create pyproject.toml with extras
    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[build-system]
requires = ["setuptools>=45", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "test-package"
version = "1.0.0"
description = "A test package"

[project.optional-dependencies]
numpy = ["numpy>=1.20.0"]
pandas = ["pandas>=1.3.0"]
torch = ["torch>=1.9.0"]
all = ["numpy>=1.20.0", "pandas>=1.3.0", "torch>=1.9.0"]
EOF

    # Create the tarball
    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")
}

#
# Helper function to create a mock sdist with setup.cfg
#
create_mock_sdist_setup_cfg() {
    local sdist_name="test_package_cfg-1.0.0"
    MOCK_SDIST_SETUP_CFG="$TEST_DIR/${sdist_name}.tar.gz"

    mkdir -p "$TEST_DIR/$sdist_name"

    # Create setup.cfg with extras
    cat > "$TEST_DIR/$sdist_name/setup.cfg" << 'EOF'
[metadata]
name = test-package-cfg
version = 1.0.0
description = A test package with setup.cfg

[options]
packages = find:
python_requires = >=3.7

[options.extras_require]
numpy = numpy>=1.20.0
pandas = pandas>=1.3.0
torch = torch>=1.9.0
all =
    numpy>=1.20.0
    pandas>=1.3.0
    torch>=1.9.0
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")
}

#
# Helper function to create a sdist with no extras
#
create_sdist_without_extras() {
    local sdist_name="no_extras-1.0.0"
    MOCK_SDIST_NO_EXTRAS="$TEST_DIR/${sdist_name}.tar.gz"

    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[build-system]
requires = ["setuptools>=45"]
build-backend = "setuptools.build_meta"

[project]
name = "no-extras"
version = "1.0.0"
description = "A package without extras"
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")
}

#
# Helper function to create a sdist with poetry-style extras
#
create_sdist_poetry_style() {
    local sdist_name="poetry_package-1.0.0"
    MOCK_SDIST_POETRY="$TEST_DIR/${sdist_name}.tar.gz"

    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[tool.poetry]
name = "poetry-package"
version = "1.0.0"
description = "A poetry package"

[tool.poetry.dependencies]
python = "^3.8"

[tool.poetry.extras]
numpy = ["numpy"]
pandas = ["pandas"]
dev = ["pytest", "black"]
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")
}

#
# Tests for validate_sdist_file
#

@test "validate_sdist_file: accepts valid sdist file" {
    run validate_sdist_file "$MOCK_SDIST_PYPROJECT"
    [ "$status" -eq 0 ]
}

@test "validate_sdist_file: rejects non-existent file" {
    run validate_sdist_file "/nonexistent/file.tar.gz"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "validate_sdist_file: rejects non-tar.gz file" {
    local non_sdist="$TEST_DIR/not_an_sdist.txt"
    touch "$non_sdist"

    run validate_sdist_file "$non_sdist"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a tar.gz sdist" ]]
}

@test "validate_sdist_file: handles symbolic links" {
    local link="$TEST_DIR/sdist_link.tar.gz"
    ln -s "$MOCK_SDIST_PYPROJECT" "$link"

    run validate_sdist_file "$link"
    [ "$status" -eq 0 ]
}

#
# Tests for find_config_file
#

@test "find_config_file: finds pyproject.toml" {
    run find_config_file "$MOCK_SDIST_PYPROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pyproject.toml" ]]
}

@test "find_config_file: finds setup.cfg" {
    run find_config_file "$MOCK_SDIST_SETUP_CFG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "setup.cfg" ]]
}

@test "find_config_file: fails when no config found" {
    local sdist_name="no_config-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"
    touch "$TEST_DIR/$sdist_name/README.md"
    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    run find_config_file "$TEST_DIR/${sdist_name}.tar.gz"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Could not find" ]]
}

@test "find_config_file: returns path and type separated by pipe" {
    local result
    result=$(find_config_file "$MOCK_SDIST_PYPROJECT")

    [[ "$result" =~ \|pyproject\.toml$ ]]
}

#
# Tests for extract_config_content
#

@test "extract_config_content: successfully extracts pyproject.toml" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_PYPROJECT" | cut -d'|' -f1)

    run extract_config_content "$MOCK_SDIST_PYPROJECT" "$config_path"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[project]" ]]
    [[ "$output" =~ "[project.optional-dependencies]" ]]
}

@test "extract_config_content: successfully extracts setup.cfg" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_SETUP_CFG" | cut -d'|' -f1)

    run extract_config_content "$MOCK_SDIST_SETUP_CFG" "$config_path"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[metadata]" ]]
    [[ "$output" =~ "[options.extras_require]" ]]
}

@test "extract_config_content: fails on corrupted sdist" {
    local bad_sdist="$TEST_DIR/corrupted.tar.gz"
    echo "not a tar file" > "$bad_sdist"

    run extract_config_content "$bad_sdist" "fake/path.toml"
    [ "$status" -eq 1 ]
}

@test "extract_config_content: fails on non-existent path in sdist" {
    run extract_config_content "$MOCK_SDIST_PYPROJECT" "nonexistent/file.toml"
    [ "$status" -eq 1 ]
}

#
# Tests for parse_pyproject_extras
#

@test "parse_pyproject_extras: extracts extras from pyproject.toml content" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_PYPROJECT" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_PYPROJECT" "$config_path")

    run parse_pyproject_extras "$config_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    [[ "$output" =~ "torch" ]]
    [[ "$output" =~ "all" ]]
}

@test "parse_pyproject_extras: handles poetry-style extras" {
    create_sdist_poetry_style
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_POETRY" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_POETRY" "$config_path")

    run parse_pyproject_extras "$config_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    [[ "$output" =~ "dev" ]]
}

@test "parse_pyproject_extras: returns empty for no extras" {
    create_sdist_without_extras
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_NO_EXTRAS" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_NO_EXTRAS" "$config_path")

    run parse_pyproject_extras "$config_content"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_pyproject_extras: returns sorted extras" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_PYPROJECT" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_PYPROJECT" "$config_path")

    local extras
    extras=$(parse_pyproject_extras "$config_content")

    # Check if output is sorted
    local sorted_extras
    sorted_extras=$(echo "$extras" | sort)
    [ "$extras" = "$sorted_extras" ]
}

@test "parse_pyproject_extras: handles extras with hyphens and underscores" {
    local sdist_name="special_extras-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[project]
name = "special-extras"

[project.optional-dependencies]
test-extra = ["pytest"]
test_extra = ["pytest"]
dev-tools = ["black"]
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    local config_path
    config_path=$(find_config_file "$TEST_DIR/${sdist_name}.tar.gz" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$TEST_DIR/${sdist_name}.tar.gz" "$config_path")

    run parse_pyproject_extras "$config_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test-extra" ]]
    [[ "$output" =~ "test_extra" ]]
    [[ "$output" =~ "dev-tools" ]]
}

#
# Tests for parse_setup_cfg_extras
#

@test "parse_setup_cfg_extras: extracts extras from setup.cfg content" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_SETUP_CFG" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_SETUP_CFG" "$config_path")

    run parse_setup_cfg_extras "$config_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
    [[ "$output" =~ "torch" ]]
    [[ "$output" =~ "all" ]]
}

@test "parse_setup_cfg_extras: returns sorted extras" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_SETUP_CFG" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_SETUP_CFG" "$config_path")

    local extras
    extras=$(parse_setup_cfg_extras "$config_content")

    # Check if output is sorted
    local sorted_extras
    sorted_extras=$(echo "$extras" | sort)
    [ "$extras" = "$sorted_extras" ]
}

@test "parse_setup_cfg_extras: handles multi-line extras" {
    local sdist_name="multiline-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/setup.cfg" << 'EOF'
[options.extras_require]
dev =
    pytest>=6.0
    black>=21.0
    flake8>=3.9
test = pytest>=6.0
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    local config_path
    config_path=$(find_config_file "$TEST_DIR/${sdist_name}.tar.gz" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$TEST_DIR/${sdist_name}.tar.gz" "$config_path")

    run parse_setup_cfg_extras "$config_content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "dev" ]]
    [[ "$output" =~ "test" ]]
}

#
# Tests for get_defined_extras
#

@test "get_defined_extras: works with pyproject.toml" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_PYPROJECT" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_PYPROJECT" "$config_path")

    run get_defined_extras "$config_content" "pyproject.toml"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
}

@test "get_defined_extras: works with setup.cfg" {
    local config_path
    config_path=$(find_config_file "$MOCK_SDIST_SETUP_CFG" | cut -d'|' -f1)
    local config_content
    config_content=$(extract_config_content "$MOCK_SDIST_SETUP_CFG" "$config_path")

    run get_defined_extras "$config_content" "setup.cfg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "numpy" ]]
}

@test "get_defined_extras: fails with unknown config type" {
    local config_content="some content"

    run get_defined_extras "$config_content" "unknown.ini"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown config type" ]]
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
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "parse_requested_extras: preserves case" {
    local input="NumPy,PANDAS,torch"

    run parse_requested_extras "$input"

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "NumPy" ]
    [ "${lines[1]}" = "PANDAS" ]
    [ "${lines[2]}" = "torch" ]
}

@test "parse_requested_extras: handles long extra names" {
    local long_extra="very_long_extra_name_that_might_cause_issues_with_parsing"
    run parse_requested_extras "$long_extra"
    [ "$status" -eq 0 ]
    [ "$output" = "$long_extra" ]
}

@test "parse_requested_extras: handles extras with hyphens and underscores" {
    run parse_requested_extras "test-extra,test_extra,test.extra"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test-extra" ]]
    [[ "$output" =~ "test_extra" ]]
    [[ "$output" =~ "test.extra" ]]
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

@test "main: lists extras from pyproject.toml when no extras requested" {
    run main "$MOCK_SDIST_PYPROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Extras defined in sdist" ]]
    [[ "$output" =~ "pyproject.toml" ]]
    [[ "$output" =~ "numpy" ]]
    [[ "$output" =~ "pandas" ]]
}

@test "main: lists extras from setup.cfg when no extras requested" {
    run main "$MOCK_SDIST_SETUP_CFG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Extras defined in sdist" ]]
    [[ "$output" =~ "setup.cfg" ]]
    [[ "$output" =~ "numpy" ]]
}

@test "main: succeeds when requested extras exist (pyproject.toml)" {
    run main "$MOCK_SDIST_PYPROJECT" "numpy,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ ✓.*pandas ]]
    [[ "$output" =~ "All requested extras are defined" ]]
}

@test "main: succeeds when requested extras exist (setup.cfg)" {
    run main "$MOCK_SDIST_SETUP_CFG" "numpy,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ ✓.*pandas ]]
}

@test "main: fails when requested extras don't exist" {
    run main "$MOCK_SDIST_PYPROJECT" "numpy,nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ ✗.*nonexistent ]]
}

@test "main: handles single extra" {
    run main "$MOCK_SDIST_PYPROJECT" "numpy"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ "All requested extras are defined" ]]
}

@test "main: fails on non-existent sdist" {
    run main "/nonexistent/sdist.tar.gz"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "main: handles sdist with no extras" {
    create_sdist_without_extras

    run main "$MOCK_SDIST_NO_EXTRAS"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No extras defined" ]]
}

@test "main: fails when requesting extras from sdist with none" {
    create_sdist_without_extras

    run main "$MOCK_SDIST_NO_EXTRAS" "numpy"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Requested extras but none are defined" ]]
}

@test "main: handles extras with whitespace" {
    run main "$MOCK_SDIST_PYPROJECT" "numpy , pandas , torch"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ ✓.*pandas ]]
    [[ "$output" =~ ✓.*torch ]]
}

@test "main: shows total count of extras" {
    run main "$MOCK_SDIST_PYPROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Total: 4 extras" ]]
}

@test "main: shows config file type" {
    run main "$MOCK_SDIST_PYPROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found config: pyproject.toml" ]]

    run main "$MOCK_SDIST_SETUP_CFG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found config: setup.cfg" ]]
}

@test "main: performs efficiently with many extras" {
    local sdist_name="many_extras-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"

    {
        echo "[project]"
        echo "name = \"many-extras\""
        echo ""
        echo "[project.optional-dependencies]"
        for i in {1..50}; do
            echo "extra$i = [\"dep$i\"]"
        done
    } > "$TEST_DIR/$sdist_name/pyproject.toml"

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    local many_sdist="$TEST_DIR/${sdist_name}.tar.gz"
    run main "$many_sdist" "extra1,extra25,extra50"
    [ "$status" -eq 0 ]
}

#
# Edge cases
#

@test "main: handles case-sensitive extra names" {
    run main "$MOCK_SDIST_PYPROJECT" "NumPy"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "NumPy - NOT DEFINED" ]]
}

@test "main: handles empty extra in comma list" {
    run main "$MOCK_SDIST_PYPROJECT" "numpy,,pandas"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ✓.*numpy ]]
    [[ "$output" =~ ✓.*pandas ]]
    [[ ! "$output" =~ "NOT DEFINED" ]]
}

@test "main: prefers pyproject.toml over setup.cfg" {
    # Create an sdist with both files
    local sdist_name="both_configs-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[project.optional-dependencies]
pyproject_extra = ["numpy"]
EOF

    cat > "$TEST_DIR/$sdist_name/setup.cfg" << 'EOF'
[options.extras_require]
setup_cfg_extra = numpy
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    run main "$TEST_DIR/${sdist_name}.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found config: pyproject.toml" ]]
    [[ "$output" =~ "pyproject_extra" ]]
    [[ ! "$output" =~ "setup_cfg_extra" ]]
}

@test "main: handles nested directory structure" {
    local sdist_name="nested-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name/src/package"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[project.optional-dependencies]
nested = ["dep"]
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    run main "$TEST_DIR/${sdist_name}.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "nested" ]]
}

@test "main: handles extras with numeric prefixes" {
    local sdist_name="numeric-1.0.0"
    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[project.optional-dependencies]
3d-graphics = ["three"]
2d-plotting = ["matplotlib"]
EOF

    (cd "$TEST_DIR" && tar -czf "${sdist_name}.tar.gz" "$sdist_name")

    run main "$TEST_DIR/${sdist_name}.tar.gz" "3d-graphics,2d-plotting"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "3d-graphics" ]]
    [[ "$output" =~ "2d-plotting" ]]
}

@test "find_config_file: handles sdist without top-level directory" {
    # Some sdists might not have a top-level directory
    local sdist_name="flat_structure"
    mkdir -p "$TEST_DIR/$sdist_name"

    cat > "$TEST_DIR/$sdist_name/pyproject.toml" << 'EOF'
[project.optional-dependencies]
flat = ["dep"]
EOF

    # Create tarball with files at root level
    (cd "$TEST_DIR/$sdist_name" && tar -czf "../${sdist_name}.tar.gz" pyproject.toml)

    run find_config_file "$TEST_DIR/${sdist_name}.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pyproject.toml" ]]
}
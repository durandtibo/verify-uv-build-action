#!/usr/bin/env bats

# Setup function runs before each test
setup() {
	# Create a temporary directory for test files
	TEST_DIR="$(mktemp -d)"

	# Path to the script being tested
	SCRIPT="scripts/check_metadata.sh"

	# Create a mock uv command
	MOCK_UV="$TEST_DIR/bin/uv"
	mkdir -p "$TEST_DIR/bin"
	cat > "$MOCK_UV" << 'EOF'
#!/usr/bin/env bash
# Mock uv command for testing

if [ "$2" = "show" ]; then
	case "$3" in
		"myproject")
			cat << 'METADATA'
Name: myproject
Version: 1.0.0
Summary: A test project
Home-page: https://example.com
Author: Test Author
License: MIT
Location: /path/to/myproject
Requires: coola, numpy, pandas
Required-by:
METADATA
			;;
		"simple-package")
			cat << 'METADATA'
Name: simple-package
Version: 2.0.0
Summary: A simple package
Requires:
METADATA
			;;
		"nonexistent")
			echo "Error: Package 'nonexistent' not found" >&2
			exit 1
			;;
		*)
			echo "Error: Package '$3' not found" >&2
			exit 1
			;;
	esac
fi
EOF
	chmod +x "$MOCK_UV"

	# Prepend mock directory to PATH so our mock uv is found first
	export PATH="$TEST_DIR/bin:$PATH"
}

# Teardown function runs after each test
teardown() {
	# Clean up temporary directory
	rm -rf "$TEST_DIR"
}

# Test: No arguments provided
@test "fails when no package name is provided" {
	run bash "$SCRIPT"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Error: Package name is required" ]]
	[[ "$output" =~ "Usage:" ]]
}

# Test: Package name only (success)
@test "succeeds with valid package name only" {
	run bash "$SCRIPT" myproject
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Name: myproject" ]]
	[[ "$output" =~ "✅ Package name 'myproject' verified" ]]
	[[ "$output" =~ "🎉 All metadata validation checks passed" ]]
}

# Test: Package name with single dependency
@test "succeeds with valid package name and single dependency" {
	run bash "$SCRIPT" myproject coola
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Package name 'myproject' verified" ]]
	[[ "$output" =~ "✅ Required dependency 'coola' found" ]]
	[[ "$output" =~ "🎉 All metadata validation checks passed" ]]
}

# Test: Package name with multiple dependencies
@test "succeeds with valid package name and multiple dependencies" {
	run bash "$SCRIPT" myproject "coola,numpy,pandas"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Package name 'myproject' verified" ]]
	[[ "$output" =~ "✅ Required dependency 'coola' found" ]]
	[[ "$output" =~ "✅ Required dependency 'numpy' found" ]]
	[[ "$output" =~ "✅ Required dependency 'pandas' found" ]]
	[[ "$output" =~ "🎉 All metadata validation checks passed" ]]
}

# Test: Package name with dependencies containing spaces
@test "succeeds with dependencies containing spaces" {
	run bash "$SCRIPT" myproject "coola, numpy, pandas"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Required dependency 'coola' found" ]]
	[[ "$output" =~ "✅ Required dependency 'numpy' found" ]]
	[[ "$output" =~ "✅ Required dependency 'pandas' found" ]]
}

# Test: Nonexistent package
@test "fails when package does not exist" {
	run bash "$SCRIPT" nonexistent
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Error: Package 'nonexistent' not found" ]]
}

# Test: Package with no dependencies specified
@test "succeeds for package with no dependencies when none required" {
	run bash "$SCRIPT" simple-package
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Package name 'simple-package' verified" ]]
	[[ "$output" =~ "🎉 All metadata validation checks passed" ]]
}

# Test: Required dependency not found in metadata
@test "fails when required dependency is missing" {
	run bash "$SCRIPT" simple-package "missing-dep"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "❌ Error: Required dependency 'missing-dep' not found" ]]
}

# Test: One of multiple dependencies missing
@test "fails when one of multiple dependencies is missing" {
	run bash "$SCRIPT" myproject "coola,missing-dep,numpy"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "✅ Required dependency 'coola' found" ]]
	[[ "$output" =~ "❌ Error: Required dependency 'missing-dep' not found" ]]
}

# Test: Empty dependency string
@test "succeeds with empty dependency string" {
	run bash "$SCRIPT" myproject ""
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Package name 'myproject' verified" ]]
	[[ "$output" =~ "🎉 All metadata validation checks passed" ]]
}

# Test: Metadata output is displayed
@test "displays package metadata" {
	run bash "$SCRIPT" myproject
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Name: myproject" ]]
	[[ "$output" =~ "Version: 1.0.0" ]]
	[[ "$output" =~ "Summary: A test project" ]]
}

# Test: Wrong package name in metadata (edge case)
@test "fails when metadata doesn't contain expected package name" {
	# Create a special mock that returns wrong package name
	cat > "$TEST_DIR/bin/uv" << 'EOF'
#!/usr/bin/env bash
if [ "$2" = "show" ]; then
	cat << 'METADATA'
Name: different-package
Version: 1.0.0
METADATA
fi
EOF
	chmod +x "$TEST_DIR/bin/uv"

	run bash "$SCRIPT" myproject
	[ "$status" -eq 1 ]
	[[ "$output" =~ "❌ Error: Package name 'myproject' not found in metadata" ]]
}

# Test: Single dependency as second argument (not comma-separated)
@test "succeeds with single dependency as separate argument" {
	run bash "$SCRIPT" myproject coola
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Required dependency 'coola' found" ]]
}
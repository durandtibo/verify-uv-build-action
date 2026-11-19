#!/usr/bin/env bats

# Tests of tests/check_action_case.sh, the assertions shared by the local and the
# released run of the action in ci-action.yaml.

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/../check_action_case.sh"
	DIST="${BATS_TEST_TMPDIR}/dist"
	mkdir -p "${DIST}"
	touch "${DIST}/myproject-0.1.0-py3-none-any.whl" "${DIST}/myproject-0.1.0.tar.gz"
	export WHEEL_PATH="${DIST}/myproject-0.1.0-py3-none-any.whl"
	export SDIST_PATH="${DIST}/myproject-0.1.0.tar.gz"
	export DIST_DIR="${DIST}"
	export VERSION="0.1.0"
}

@test "success is expected and got, outputs are valid" {
	EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "failure is expected and got" {
	EXPECT=failure OUTCOME=failure run "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "the outputs are not asserted after an expected failure" {
	EXPECT=failure OUTCOME=failure EXPECT_OUTPUTS=true WHEEL_PATH="" run "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "the outputs are not asserted when they are not expected" {
	EXPECT=success OUTCOME=success EXPECT_OUTPUTS=false WHEEL_PATH="" run "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "a failure that was expected to succeed fails" {
	EXPECT=success OUTCOME=failure run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Expected the action to end with 'success' but got 'failure'"* ]]
}

@test "a success that was expected to fail fails" {
	EXPECT=failure OUTCOME=success run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Expected the action to end with 'failure' but got 'success'"* ]]
}

@test "a missing wheel fails" {
	rm "${WHEEL_PATH}"
	EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"wheel-path"* ]]
}

@test "an empty sdist-path fails" {
	SDIST_PATH="" EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"sdist-path"* ]]
}

@test "a dist-dir that does not hold the wheel fails" {
	mkdir "${BATS_TEST_TMPDIR}/other"
	DIST_DIR="${BATS_TEST_TMPDIR}/other" EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"dist-dir"* ]]
}

@test "a version that is not in the wheel name fails" {
	VERSION="9.9.9" EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"version"* ]]
}

@test "an empty version fails" {
	VERSION="" EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true run "${SCRIPT}"
	[ "$status" -eq 1 ]
}

@test "an invalid EXPECT is a usage error" {
	EXPECT=maybe OUTCOME=success run "${SCRIPT}"
	[ "$status" -eq 2 ]
}

@test "a missing OUTCOME is a usage error" {
	EXPECT=success run "${SCRIPT}"
	[ "$status" -eq 2 ]
}

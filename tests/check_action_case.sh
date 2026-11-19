#!/usr/bin/env bash

# check_action_case.sh - Assert the result of one run of the action in ci-action.yaml
#
# Description:
#   CI helper shared by the run of the local action (uses: ./) and the run of the
#   released action, so the two cannot drift apart. It asserts that the outcome of
#   the action is the expected one and, when the action succeeded and its outputs
#   are expected, that they have the right value or format.
#
# Usage:
#   EXPECT=success OUTCOME=success EXPECT_OUTPUTS=true WHEEL_PATH=... \
#     tests/check_action_case.sh
#
# Environment variables:
#   EXPECT          - Expected outcome: success or failure (required)
#   OUTCOME         - Outcome of the action step: success or failure (required)
#   EXPECT_OUTPUTS  - true when the outputs are asserted (the released action may not
#                     have them yet); default false
#   WHEEL_PATH      - Output wheel-path
#   SDIST_PATH      - Output sdist-path
#   DIST_DIR        - Output dist-dir
#   VERSION         - Output version
#
# Exit Codes:
#   0 - The action ended as expected and the outputs are valid
#   1 - A check failed
#   2 - Invalid usage (missing or invalid EXPECT or OUTCOME)

set -euo pipefail

# check_outcome: assert that OUTCOME is EXPECT.
check_outcome() {
	if [ "${OUTCOME}" != "${EXPECT}" ]; then
		echo "❌ Expected the action to end with '${EXPECT}' but got '${OUTCOME}'" >&2
		return 1
	fi
	echo "✅ The action ended with '${OUTCOME}' as expected"
}

# check_outputs: assert the value or the format of every output.
check_outputs() {
	local wheel="${WHEEL_PATH:-}" sdist="${SDIST_PATH:-}" dist_dir="${DIST_DIR:-}" version="${VERSION:-}"
	local failures=0
	[ -f "${wheel}" ] && [[ "${wheel}" == *.whl ]] || {
		echo "❌ Expected wheel-path to be an existing .whl file, got '${wheel}'" >&2
		failures=$((failures + 1))
	}
	[ -f "${sdist}" ] && [[ "${sdist}" == *.tar.gz ]] || {
		echo "❌ Expected sdist-path to be an existing .tar.gz file, got '${sdist}'" >&2
		failures=$((failures + 1))
	}
	[ -d "${dist_dir}" ] && [ "$(dirname "${wheel}")" = "${dist_dir}" ] && [ "$(dirname "${sdist}")" = "${dist_dir}" ] || {
		echo "❌ Expected dist-dir '${dist_dir}' to hold the wheel and the sdist" >&2
		failures=$((failures + 1))
	}
	[[ "${version}" =~ ^[0-9]+(\.[0-9]+)*([.+-]?[0-9A-Za-z]+)*$ ]] || {
		echo "❌ Expected version to look like a version, got '${version}'" >&2
		failures=$((failures + 1))
	}
	[[ "$(basename "${wheel}")" == *"-${version}-"* ]] || {
		echo "❌ Expected the wheel '${wheel}' to contain the version '${version}'" >&2
		failures=$((failures + 1))
	}
	[ "${failures}" -eq 0 ] || return 1
	echo "✅ The outputs are valid (version ${version})"
}

main() {
	case "${EXPECT:-}" in
	success | failure) ;;
	*)
		echo "❌ EXPECT must be success or failure, got '${EXPECT:-}'" >&2
		return 2
		;;
	esac
	case "${OUTCOME:-}" in
	success | failure) ;;
	*)
		echo "❌ OUTCOME must be success or failure, got '${OUTCOME:-}'" >&2
		return 2
		;;
	esac
	check_outcome || return 1
	if [ "${EXPECT}" = "success" ] && [ "${EXPECT_OUTPUTS:-false}" = "true" ]; then
		check_outputs || return 1
	fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi

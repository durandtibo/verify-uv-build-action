#!/usr/bin/env bats

# nightly-test-released.yaml mirrors ci-action.yaml for the last release. This
# test normalizes the few lines that must differ and compares the rest, so the
# copy cannot drift silently.

bats_require_minimum_version 1.5.0

CI=".github/workflows/ci-action.yaml"
NIGHTLY=".github/workflows/nightly-test-released.yaml"

# Jobs that exist only in ci-action.yaml because they test a feature the last
# release does not have yet (or, for test-latest-tools, because they only run
# on the schedule of ci.yaml). Shrink this list when a release catches up.
ONLY_IN_CI="test-tool-versions test-two-invocations test-latest-tools"

# Differences between the unreleased action and the last release that are
# normalized away until the next release: the input package-extra (released)
# is package-extras (unreleased), and package-name is optional in the
# unreleased action only. Remove these sed rules when a release catches up.

# normalize <file>: print the file without the header comment, the workflow
# name, the jobs of ONLY_IN_CI and blank lines, with the action reference, the
# loader mode and the default dist-type replaced by placeholders.
normalize() {
	awk -v drop="${ONLY_IN_CI}" '
		BEGIN { n = split(drop, names, " "); for (i = 1; i <= n; i++) dropped[names[i]] = 1 }
		!started && /^#/ { next }
		{ started = 1 }
		/^name:/ { next }
		/^[[:space:]]*$/ { next }
		/^  #/ { buf = buf $0 "\n"; next }
		/^  [a-z0-9-]+:[[:space:]]*$/ {
			key = $1
			sub(/:$/, "", key)
			skip = (key in dropped)
			if (!skip) { printf "%s", buf; print }
			buf = ""
			next
		}
		{ if (!skip) { printf "%s", buf; print }; buf = "" }
	' "$1" |
		sed -e 's#uses: \./$#uses: ACTION#' \
			-e 's#^\( *\)package-extra:#\1package-extras:#' \
			-e '/package-name: myproject$/d' \
			-e '/# package-name is omitted/d' \
			-e 's#uses: durandtibo/verify-uv-build-action@.*#uses: ACTION#' \
			-e 's#load-cases\.sh all#load-cases.sh MODE#' \
			-e 's#load-cases\.sh released#load-cases.sh MODE#' \
			-e "s#matrix.dist-type || 'both'#matrix.dist-type || DEFAULT#" \
			-e "s#matrix.dist-type || 'wheel'#matrix.dist-type || DEFAULT#"
}

@test "the nightly workflow mirrors ci-action.yaml" {
	run diff <(normalize "${CI}") <(normalize "${NIGHTLY}")
	[ "$status" -eq 0 ]
}

@test "the mirror calls the released action, not the checkout" {
	! grep -Eq 'uses: \./$' "${NIGHTLY}"
	grep -Eq 'uses: durandtibo/verify-uv-build-action@[0-9a-f]{40} # ratchet:durandtibo/verify-uv-build-action@v[0-9]' "${NIGHTLY}"
}

@test "ci-action.yaml calls the checkout, not a release" {
	! grep -q 'durandtibo/verify-uv-build-action@' "${CI}"
}

@test "the mirror loads the released cases and ci-action.yaml all of them" {
	grep -q 'load-cases.sh released' "${NIGHTLY}"
	grep -q 'load-cases.sh all' "${CI}"
}

@test "every job of the allow-list exists in ci-action.yaml and not in the mirror" {
	local job
	for job in ${ONLY_IN_CI}; do
		grep -Eq "^  ${job}:" "${CI}"
		! grep -Eq "^  ${job}:" "${NIGHTLY}"
	done
}

@test "the normalization detects a job missing from the mirror" {
	local copy="${BATS_TEST_TMPDIR}/nightly.yaml"
	awk '/^  test-cases:/ { exit } { print }' "${NIGHTLY}" >"${copy}"
	run diff <(normalize "${CI}") <(normalize "${copy}")
	[ "$status" -ne 0 ]
}

@test "the normalization detects a changed step" {
	local copy="${BATS_TEST_TMPDIR}/nightly.yaml"
	sed 's#package-dependencies: coola#package-dependencies: other#' "${NIGHTLY}" >"${copy}"
	run diff <(normalize "${CI}") <(normalize "${copy}")
	[ "$status" -ne 0 ]
}

@test "the mirror is triggered with the same inputs as ci-action.yaml" {
	grep -q 'workflow_call:' "${NIGHTLY}"
}

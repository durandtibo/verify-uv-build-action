#!/usr/bin/env bats

# Tests of tests/check_export.sh, which compares `git archive` with the files the action needs.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SCRIPT="${REPO_ROOT}/tests/check_export.sh"
	TMP_REPO="${BATS_TEST_TMPDIR}/repo"
}

# Create a throwaway git repository with the expected files and the given .gitattributes content.
make_repo() {
	mkdir -p "${TMP_REPO}/scripts"
	cd "${TMP_REPO}"
	git init -q
	git config user.email t@example.com
	git config user.name t
	touch LICENSE action.yaml scripts/check_dist.sh scripts/check_install.sh \
		scripts/check_types.sh scripts/lib.sh scripts/requirements.txt scripts/verify.sh
	printf '%s' "$1" >.gitattributes
	git add -A
	git commit -q -m init
}

@test "passes on the repository" {
	cd "${REPO_ROOT}"
	run "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"scripts/verify.sh"* ]]
}

@test "passes when only the needed files are exported" {
	make_repo $'/.gitattributes export-ignore\n'
	run "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "fails when a needed file is not exported" {
	make_repo $'/scripts/lib.sh export-ignore\n'
	run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"❌"* ]]
	[[ "$output" == *"scripts/lib.sh"* ]]
}

@test "fails when an unneeded file is exported" {
	make_repo ''
	run "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" == *".gitattributes"* ]]
}

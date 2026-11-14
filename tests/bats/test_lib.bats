#!/usr/bin/env bats


bats_require_minimum_version 1.5.0
setup() {
	# shellcheck source=scripts/lib.sh
	source "scripts/lib.sh"
}

@test "normalize_name lowercases and replaces separators" {
	run normalize_name "Foo_Bar.baz"
	[ "$status" -eq 0 ]
	[ "$output" = "foo-bar-baz" ]
}

@test "normalize_name collapses runs of separators" {
	run normalize_name "a-_.b"
	[ "$output" = "a-b" ]
}

@test "normalize_name leaves a normalized name unchanged" {
	run normalize_name "my-pkg"
	[ "$output" = "my-pkg" ]
}

@test "split_csv trims spaces and normalizes items" {
	run split_csv " Foo_Bar , baz "
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "foo-bar" ]
	[ "${lines[1]}" = "baz" ]
	[ "${#lines[@]}" -eq 2 ]
}

@test "split_csv drops empty items and trailing comma" {
	run split_csv "a,,b,"
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "a" ]
	[ "${lines[1]}" = "b" ]
}

@test "split_csv prints nothing for an empty string" {
	run split_csv ""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "split_csv prints nothing for only separators and spaces" {
	run split_csv " , ,"
	[ -z "$output" ]
}

@test "log_ok prints a check mark on stdout" {
	run log_ok "fine"
	[ "$output" = "✅ fine" ]
}

@test "log_error prints a cross on stderr" {
	unset GITHUB_ACTIONS REPORT_FILE
	run --separate-stderr log_error "broken"
	[ -z "$output" ]
	[ "$stderr" = "❌ broken" ]
}

@test "die logs the error and exits with 1" {
	run --separate-stderr die "fatal"
	[ "$status" -eq 1 ]
	[ "$stderr" = "❌ fatal" ]
}

@test "group_start and group_end print workflow commands" {
	run group_start "Title"
	[ "$output" = "::group::Title" ]
	run group_end
	[ "$output" = "::endgroup::" ]
}

@test "sourcing the library has no output" {
	run bash -c "source scripts/lib.sh"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "default_module_name replaces hyphens and dots with underscores" {
	run default_module_name "my-pkg.sub"
	[ "$output" = "my_pkg_sub" ]
}

@test "log_error prints no annotation outside GitHub Actions (G11)" {
	unset GITHUB_ACTIONS
	run --separate-stderr log_error "boom"
	[ "$stderr" = "❌ boom" ]
	[ -z "$output" ]
}

@test "log_error prints an annotation under GitHub Actions (G11)" {
	GITHUB_ACTIONS=true run --separate-stderr log_error "boom"
	[ "$stderr" = "❌ boom" ]
	[ "$output" = "::error::boom" ]
}

@test "is_dotted_identifier accepts module paths" {
	run is_dotted_identifier "a"
	[ "$status" -eq 0 ]
	run is_dotted_identifier "my_pkg.sub_1.x"
	[ "$status" -eq 0 ]
	run is_dotted_identifier "_private"
	[ "$status" -eq 0 ]
}

@test "is_dotted_identifier rejects regex and shell metacharacters (G5)" {
	local value
	for value in "" "a+b" "a(b" "a b" "1a" "a..b" ".a" "a." "a-b" 'a;b' 'a$b'; do
		run is_dotted_identifier "$value"
		[ "$status" -ne 0 ]
	done
}

@test "is_version_spec accepts latest and versions" {
	local value
	for value in latest 1.2.3 1.1.414 7.0.0 2.0rc1 1.0.post1 1!2.0 1.0+local; do
		run is_version_spec "$value"
		[ "$status" -eq 0 ]
	done
}

@test "is_version_spec rejects options and free text (G5)" {
	local value
	for value in "" "--index-url=x" "1.0 --foo" "twine==1" "v1" "1.0;rm" "latest "; do
		run is_version_spec "$value"
		[ "$status" -ne 0 ]
	done
}

@test "log_error appends to REPORT_FILE when it is set" {
	REPORT_FILE="${BATS_TEST_TMPDIR}/report"
	log_error "boom" 2>/dev/null
	log_error "bang" 2>/dev/null
	[ "$(cat "${BATS_TEST_TMPDIR}/report")" = "$(printf 'error|boom\nerror|bang')" ]
}

@test "log_error writes no report when REPORT_FILE is unset" {
	unset REPORT_FILE
	run log_error "boom"
	[ "$status" -eq 0 ]
}

@test "action_default prints the default of an input of action.yaml" {
	[ "$(action_default dist-type)" = "both" ]
	[ "$(action_default project-path)" = "." ]
	[ "$(action_default check-types)" = "true" ]
}

@test "action_default prints an empty default and nothing for an unknown input" {
	[ -z "$(action_default module-name)" ]
	[ -z "$(action_default nope)" ]
}

@test "tool_pin prints the pinned version of a tool" {
	[[ "$(tool_pin twine)" =~ ^[0-9][0-9.]*$ ]]
	[[ "$(tool_pin pyright)" =~ ^[0-9][0-9.]*$ ]]
	[ -z "$(tool_pin nope)" ]
}

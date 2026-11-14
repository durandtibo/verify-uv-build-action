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

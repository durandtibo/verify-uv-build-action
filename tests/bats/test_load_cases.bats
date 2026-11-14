#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="scripts/load-cases.sh"
	FILE="$BATS_TEST_TMPDIR/cases.json"
	cat >"$FILE" <<'JSON'
[
  {"name": "a", "expect": "failure", "released": true},
  {"name": "b", "expect": "success"},
  {"name": "c", "expect": "success", "released": true, "skip": "later"}
]
JSON
}

@test "all returns every row that is not skipped" {
	run bash "$SCRIPT" all "$FILE"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r 'map(.name) | join(",")')" = "a,b" ]
}

@test "released returns only the flagged rows" {
	run bash "$SCRIPT" released "$FILE"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r 'map(.name) | join(",")')" = "a" ]
}

@test "output is a single line of JSON" {
	run bash "$SCRIPT" all "$FILE"
	[ "${#lines[@]}" -eq 1 ]
}

@test "unknown mode exits 2" {
	run -2 bash "$SCRIPT" nope "$FILE"
	[[ "$output" == *"Usage"* ]]
}

@test "missing mode exits 2" {
	run -2 bash "$SCRIPT"
}

@test "missing file exits 2" {
	run -2 bash "$SCRIPT" all "$BATS_TEST_TMPDIR/absent.json"
	[[ "$output" == *"not found"* ]]
}

@test "every row of tests/cases.json has a name and a valid expect" {
	run jq -e 'all(.[]; (.name | type == "string") and (.expect == "success" or .expect == "failure"))' tests/cases.json
	[ "$status" -eq 0 ]
}

@test "row names of tests/cases.json are unique" {
	run jq -e '(map(.name) | length) == (map(.name) | unique | length)' tests/cases.json
	[ "$status" -eq 0 ]
}

@test "default file loads and skipped rows are excluded" {
	run bash "$SCRIPT" all
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq 'any(.[]; has("skip"))')" = "false" ]
	[ "$(echo "$output" | jq 'length')" -gt 0 ]
	[[ "$output" == *"version is the placeholder"* ]]
}

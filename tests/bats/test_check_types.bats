#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="scripts/check_types.sh"
	WORK="$(mktemp -d)"
	mkdir -p "${WORK}/bin"
	# Fake uvx: records its arguments, exits with $UVX_STATUS (default 0).
	cat >"${WORK}/bin/uvx" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >"${WORK}/uvx_args"
echo "${PYTHONPATH:-}" >"${WORK}/uvx_pythonpath"
exit "${UVX_STATUS:-0}"
FAKE
	# Fake interpreter of the environment under test.
	mkdir -p "${WORK}/venv/bin"
	cat >"${WORK}/venv/bin/python" <<'FAKE'
#!/usr/bin/env bash
echo "/fake/site-packages"
FAKE
	chmod +x "${WORK}/bin/uvx" "${WORK}/venv/bin/python"
	export WORK
	export PATH="${WORK}/bin:${PATH}"
}

# Run <function> [args] from the sourced library.
call() {
	bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "${SCRIPT}" "$@"
}

teardown() {
	rm -rf "${WORK}"
}

@test "module name defaults from the package name (regression G10)" {
	run call check_types "${WORK}/venv" my-pkg.x "" 1.2.3
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes my_pkg_x"* ]]
}

@test "an explicit module name wins over the package name" {
	run call check_types "${WORK}/venv" my-pkg other_mod 1.2.3
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes other_mod"* ]]
}

@test "an empty module name falls back to the default" {
	run call check_types "${WORK}/venv" my-pkg "" 1.2.3
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes my_pkg"* ]]
}

@test "succeeds when pyright succeeds" {
	run call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Type hints validated for mypkg" ]]
}

@test "passes the pinned version and module to uvx" {
	run call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$(cat "${WORK}/uvx_args")" = "--no-config pyright@1.2.3 --verifytypes mypkg --ignoreexternal" ]
}

@test "exposes the site-packages of the environment through PYTHONPATH" {
	run call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$(cat "${WORK}/uvx_pythonpath")" = "/fake/site-packages" ]
}

@test "fails when the environment interpreter does not work" {
	rm "${WORK}/venv/bin/python"
	run --separate-stderr call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "cannot query the environment" ]]
}

@test "fails with exit 1 and a cross line when pyright fails" {
	UVX_STATUS=1 run --separate-stderr call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "❌ type completeness check failed for mypkg" ]]
}

@test "fails when uvx cannot run (no silent skip)" {
	UVX_STATUS=127 run call check_types "${WORK}/venv" mypkg "" 1.2.3
	[ "$status" -eq 1 ]
}


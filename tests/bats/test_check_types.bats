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
	export PYRIGHT_VERSION="1.2.3"
	export VIRTUAL_ENV="${WORK}/venv"
}

teardown() {
	rm -rf "${WORK}"
}

@test "exits with code 2 when no package name is provided" {
	run --separate-stderr bash "${SCRIPT}"
	[ "$status" -eq 2 ]
	[[ "$stderr" =~ "package_name" ]]
	[[ "$stderr" =~ "Usage:" ]]
}

@test "exits with code 2 with more than two arguments" {
	run -2 bash "${SCRIPT}" mypkg mypkg extra
}

@test "module name defaults from the package name (regression G10)" {
	run bash "${SCRIPT}" my-pkg.x
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes my_pkg_x"* ]]
}

@test "an explicit module name wins over the package name" {
	run bash "${SCRIPT}" my-pkg other_mod
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes other_mod"* ]]
}

@test "an empty module name falls back to the default" {
	run bash "${SCRIPT}" my-pkg ""
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/uvx_args")" == *"--verifytypes my_pkg"* ]]
}

@test "an invalid module name exits with code 2" {
	run --separate-stderr bash "${SCRIPT}" mypkg 'a b'
	[ "$status" -eq 2 ]
	[[ "$stderr" =~ "dotted identifier" ]]
}

@test "exits with code 2 when PYRIGHT_VERSION is missing" {
	unset PYRIGHT_VERSION
	run --separate-stderr bash "${SCRIPT}" mypkg
	[ "$status" -eq 2 ]
	[[ "$stderr" =~ "PYRIGHT_VERSION is required" ]]
}

@test "exits with code 2 when VIRTUAL_ENV is missing" {
	unset VIRTUAL_ENV
	run --separate-stderr bash "${SCRIPT}" mypkg
	[ "$status" -eq 2 ]
	[[ "$stderr" =~ "VIRTUAL_ENV is required" ]]
}

@test "succeeds when pyright succeeds" {
	run bash "${SCRIPT}" mypkg
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅ Type hints validated for mypkg" ]]
}

@test "passes the pinned version and module to uvx" {
	run bash "${SCRIPT}" mypkg
	[ "$(cat "${WORK}/uvx_args")" = "--no-config pyright@1.2.3 --verifytypes mypkg --ignoreexternal" ]
}

@test "exposes the site-packages of the environment through PYTHONPATH" {
	run bash "${SCRIPT}" mypkg
	[ "$(cat "${WORK}/uvx_pythonpath")" = "/fake/site-packages" ]
}

@test "fails when the environment interpreter does not work" {
	rm "${WORK}/venv/bin/python"
	run --separate-stderr bash "${SCRIPT}" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "cannot query the environment" ]]
}

@test "fails with exit 1 and a cross line when pyright fails" {
	UVX_STATUS=1 run --separate-stderr bash "${SCRIPT}" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "❌ type completeness check failed for mypkg" ]]
}

@test "fails when uvx cannot run (no silent skip)" {
	UVX_STATUS=127 run bash "${SCRIPT}" mypkg
	[ "$status" -eq 1 ]
}

@test "check_types is available when the script is sourced" {
	run bash -c "source '${SCRIPT}'; check_types direct_pkg"
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/uvx_args")" =~ "--verifytypes direct_pkg" ]]
}

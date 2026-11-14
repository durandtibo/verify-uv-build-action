#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="scripts/check_install.sh"
	WORK="$(mktemp -d)"
	mkdir -p "${WORK}/bin"
	export SHOW_FILE="${WORK}/show.txt"
	export LOCATION="/venv/lib/python3.13/site-packages/mypkg/__init__.py"
	# Fake uv: `uv pip show` prints $SHOW_FILE, fails if it does not exist.
	cat >"${WORK}/bin/uv" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"${WORK}/uv_args"
if [ "$2" = "check" ]; then
	[ -z "${CHECK_ERROR:-}" ] || { echo "${CHECK_ERROR}" >&2; exit 1; }
	exit 0
fi
[ -f "${SHOW_FILE}" ] || { echo "warning: Package(s) not found" >&2; exit 1; }
cat "${SHOW_FILE}"
FAKE
	# Fake python: records the module argument, prints $LOCATION or fails.
	mkdir -p "${WORK}/venv/bin"
	cat >"${WORK}/venv/bin/python" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >"${WORK}/python_args"
if [ -n "${IMPORT_ERROR:-}" ]; then
	echo "Traceback..." >&2
	echo "${IMPORT_ERROR}" >&2
	exit 1
fi
echo "${LOCATION}"
FAKE
	chmod +x "${WORK}/bin/uv" "${WORK}/venv/bin/python"
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

# show <name> <version> <requires>
show() {
	printf 'Name: %s\nVersion: %s\nLocation: /venv\nRequires: %s\nRequired-by:\n' "$1" "$2" "$3" >"${SHOW_FILE}"
}

@test "ok" {
	show mypkg 1.0 "coola, numpy"
	run call check_install "${WORK}/venv" mypkg mypkg "coola,numpy"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅" ]]
}

@test "ok without dependencies" {
	show mypkg 1.0 ""
	run call check_install "${WORK}/venv" mypkg
	[ "$status" -eq 0 ]
}

@test "name with underscore vs hyphen passes (F8)" {
	show my_pkg 1.0 ""
	run call check_install "${WORK}/venv" my-pkg my_pkg
	[ "$status" -eq 0 ]
}

@test "wrong installed name fails" {
	show other 1.0 ""
	run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected mypkg, got other" ]]
}

@test "package not installed fails" {
	rm -f "${SHOW_FILE}"
	run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "package not installed" ]]
}

@test "local version passes (F8)" {
	show mypkg "1.0+local" ""
	run call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 0 ]
}

@test "post and dev version passes (F8)" {
	show mypkg "1.0.post1.dev2" ""
	run call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 0 ]
}

@test "version 0.0.0 fails" {
	show mypkg 0.0.0 ""
	run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "invalid installed version" ]]
}

@test "expected version matches" {
	show mypkg 1.2.3 ""
	run call check_install "${WORK}/venv" mypkg mypkg "" 1.2.3
	[ "$status" -eq 0 ]
}

@test "expected version mismatch fails" {
	show mypkg 1.2.3 ""
	run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg "" 1.2.4
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected 1.2.4, got 1.2.3" ]]
}

@test "missing dependency fails" {
	show mypkg 1.0 "coola"
	run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg "coola,numpy"
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected numpy" ]]
}

@test "dependency with underscore vs hyphen passes" {
	show mypkg 1.0 "typing-extensions"
	run call check_install "${WORK}/venv" mypkg mypkg "typing_extensions"
	[ "$status" -eq 0 ]
}

@test "dependency name is a prefix of an installed one fails" {
	show mypkg 1.0 "numpy-extra"
	run call check_install "${WORK}/venv" mypkg mypkg "numpy"
	[ "$status" -eq 1 ]
}

@test "dependency name is not used as a regex" {
	show mypkg 1.0 "numpy"
	run call check_install "${WORK}/venv" mypkg mypkg "nu.py"
	[ "$status" -eq 1 ]
}

@test "dependency list with spaces and trailing comma passes" {
	show mypkg 1.0 "a, b"
	run call check_install "${WORK}/venv" mypkg mypkg " a , b ,"
	[ "$status" -eq 0 ]
}

@test "module imported from outside site-packages fails (F1)" {
	show mypkg 1.0 ""
	LOCATION="/checkout/mypkg/__init__.py" run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "not imported from site-packages" ]]
}

@test "import error fails" {
	show mypkg 1.0 ""
	IMPORT_ERROR="ModuleNotFoundError: No module named 'mypkg'" run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "cannot import mypkg" ]]
	[[ "$stderr" =~ "ModuleNotFoundError" ]]
}

@test "module is passed as an argument, not interpolated" {
	show mypkg 1.0 ""
	run call check_install "${WORK}/venv" mypkg 'a; import os'
	grep -Fq -- "a; import os" "${WORK}/python_args"
	[[ "$(cat "${WORK}/python_args")" != *"-c"*"a; import os"*"import importlib"* ]]
}

@test "default module name is derived from the package name" {
	show my-pkg.x 1.0 ""
	run call check_install "${WORK}/venv" my-pkg.x
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/python_args")" == *" my_pkg_x" ]]
}

@test "all failures are reported in one run" {
	show other 0.0.0 ""
	LOCATION="/src/mypkg/__init__.py" run --separate-stderr call check_install "${WORK}/venv" mypkg mypkg numpy
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "wrong installed package name" ]]
	[[ "$stderr" =~ "invalid installed version" ]]
	[[ "$stderr" =~ "dependency not installed" ]]
	[[ "$stderr" =~ "not imported from site-packages" ]]
}

@test "the import runs in isolated mode (regression G9)" {
	show mypkg 1.0 ""
	run call check_install "${WORK}/venv" mypkg
	[[ "$(cat "${WORK}/python_args")" == "-I "* ]]
}

@test "uv pip show targets the venv and ignores the project configuration" {
	show mypkg 1.0 ""
	run call check_install "${WORK}/venv" mypkg
	grep -Fxq "pip show --no-config --python ${WORK}/venv mypkg" "${WORK}/uv_args"
	grep -Fxq "pip check --no-config --python ${WORK}/venv" "${WORK}/uv_args"
}

@test "uv pip check failing fails the check, with its output" {
	show mypkg 1.0 ""
	CHECK_ERROR="mypkg 1.0 requires foo>=2, but 1.0 is installed" run --separate-stderr call check_install "${WORK}/venv" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "broken dependencies" ]]
	[[ "$stderr" =~ "requires foo>=2" ]]
}

@test "uv pip check failure is reported with the other failures" {
	show other 1.0 ""
	CHECK_ERROR="broken" run --separate-stderr call check_install "${WORK}/venv" mypkg
	[[ "$stderr" =~ "broken dependencies" ]]
	[[ "$stderr" =~ "wrong installed package name" ]]
}

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
[ -f "${SHOW_FILE}" ] || { echo "warning: Package(s) not found" >&2; exit 1; }
cat "${SHOW_FILE}"
FAKE
	# Fake python: records the module argument, prints $LOCATION or fails.
	cat >"${WORK}/bin/python" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >"${WORK}/python_args"
if [ -n "${IMPORT_ERROR:-}" ]; then
	echo "Traceback..." >&2
	echo "${IMPORT_ERROR}" >&2
	exit 1
fi
echo "${LOCATION}"
FAKE
	chmod +x "${WORK}/bin/uv" "${WORK}/bin/python"
	export WORK
	export PATH="${WORK}/bin:${PATH}"
}

teardown() {
	rm -rf "${WORK}"
}

# show <name> <version> <requires>
show() {
	printf 'Name: %s\nVersion: %s\nLocation: /venv\nRequires: %s\nRequired-by:\n' "$1" "$2" "$3" >"${SHOW_FILE}"
}

@test "usage error without arguments exits 2" {
	run bash "${SCRIPT}"
	[ "$status" -eq 2 ]
	[[ "$output" =~ "Usage:" ]]
}

@test "ok" {
	show mypkg 1.0 "coola, numpy"
	run bash "${SCRIPT}" mypkg mypkg "coola,numpy"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅" ]]
}

@test "ok without dependencies" {
	show mypkg 1.0 ""
	run bash "${SCRIPT}" mypkg
	[ "$status" -eq 0 ]
}

@test "name with underscore vs hyphen passes (F8)" {
	show my_pkg 1.0 ""
	run bash "${SCRIPT}" my-pkg my_pkg
	[ "$status" -eq 0 ]
}

@test "wrong installed name fails" {
	show other 1.0 ""
	run --separate-stderr bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected mypkg, got other" ]]
}

@test "package not installed fails" {
	rm -f "${SHOW_FILE}"
	run --separate-stderr bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "package not installed" ]]
}

@test "local version passes (F8)" {
	show mypkg "1.0+local" ""
	run bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 0 ]
}

@test "post and dev version passes (F8)" {
	show mypkg "1.0.post1.dev2" ""
	run bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 0 ]
}

@test "version 0.0.0 fails" {
	show mypkg 0.0.0 ""
	run --separate-stderr bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "invalid installed version" ]]
}

@test "expected version matches" {
	show mypkg 1.2.3 ""
	run bash "${SCRIPT}" mypkg mypkg "" 1.2.3
	[ "$status" -eq 0 ]
}

@test "expected version mismatch fails" {
	show mypkg 1.2.3 ""
	run --separate-stderr bash "${SCRIPT}" mypkg mypkg "" 1.2.4
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected 1.2.4, got 1.2.3" ]]
}

@test "missing dependency fails" {
	show mypkg 1.0 "coola"
	run --separate-stderr bash "${SCRIPT}" mypkg mypkg "coola,numpy"
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected numpy" ]]
}

@test "dependency with underscore vs hyphen passes" {
	show mypkg 1.0 "typing-extensions"
	run bash "${SCRIPT}" mypkg mypkg "typing_extensions"
	[ "$status" -eq 0 ]
}

@test "dependency name is a prefix of an installed one fails" {
	show mypkg 1.0 "numpy-extra"
	run bash "${SCRIPT}" mypkg mypkg "numpy"
	[ "$status" -eq 1 ]
}

@test "dependency name is not used as a regex" {
	show mypkg 1.0 "numpy"
	run bash "${SCRIPT}" mypkg mypkg "nu.py"
	[ "$status" -eq 1 ]
}

@test "dependency list with spaces and trailing comma passes" {
	show mypkg 1.0 "a, b"
	run bash "${SCRIPT}" mypkg mypkg " a , b ,"
	[ "$status" -eq 0 ]
}

@test "module imported from outside site-packages fails (F1)" {
	show mypkg 1.0 ""
	LOCATION="/checkout/mypkg/__init__.py" run --separate-stderr bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "not imported from site-packages" ]]
}

@test "import error fails" {
	show mypkg 1.0 ""
	IMPORT_ERROR="ModuleNotFoundError: No module named 'mypkg'" run --separate-stderr bash "${SCRIPT}" mypkg mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "cannot import mypkg" ]]
	[[ "$stderr" =~ "ModuleNotFoundError" ]]
}

@test "module is passed as an argument, not interpolated" {
	show mypkg 1.0 ""
	run bash "${SCRIPT}" mypkg 'a; import os'
	grep -Fq -- "a; import os" "${WORK}/python_args"
	[[ "$(cat "${WORK}/python_args")" != *"-c"*"a; import os"*"import importlib"* ]]
}

@test "default module name is derived from the package name" {
	show my-pkg.x 1.0 ""
	run bash "${SCRIPT}" my-pkg.x
	[ "$status" -eq 0 ]
	[[ "$(cat "${WORK}/python_args")" == *" my_pkg_x" ]]
}

@test "all failures are reported in one run" {
	show other 0.0.0 ""
	LOCATION="/src/mypkg/__init__.py" run --separate-stderr bash "${SCRIPT}" mypkg mypkg numpy
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "wrong installed package name" ]]
	[[ "$stderr" =~ "invalid installed version" ]]
	[[ "$stderr" =~ "dependency not installed" ]]
	[[ "$stderr" =~ "not imported from site-packages" ]]
}

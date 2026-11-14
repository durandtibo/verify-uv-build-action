#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="scripts/check_dist.sh"
	WORK="$(mktemp -d)"
}

# Run <function> [args] from the sourced library.
call() {
	bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "${SCRIPT}" "$@"
}

teardown() {
	rm -rf "${WORK}"
}

# make_wheel <name> <version> <module_path_for_py_typed|-> [extra ...]
# Builds ${WORK}/<name>-<version>-py3-none-any.whl and prints its path.
make_wheel() {
	local name="$1" version="$2" typed="$3"
	shift 3
	local root="${WORK}/wheel_src"
	local dist_info="${root}/${name}-${version}.dist-info"
	local file="${WORK}/${name}-${version}-py3-none-any.whl"
	rm -rf "${root}"
	mkdir -p "${dist_info}"
	{
		echo "Metadata-Version: 2.4"
		echo "Name: ${name}"
		echo "Version: ${version}"
		for extra in "$@"; do echo "Provides-Extra: ${extra}"; done
		echo ""
		echo "Name: not-a-header"
	} >"${dist_info}/METADATA"
	if [ "${typed}" != "-" ]; then
		mkdir -p "${root}/${typed}"
		touch "${root}/${typed}/py.typed"
	fi
	(cd "${root}" && zip -qr "${file}" .)
	echo "${file}"
}

# make_sdist <name> <version> <py.typed dir relative to root|-> [extra ...]
# Use name "NOPKGINFO" in $PKGINFO=0 to skip PKG-INFO.
make_sdist() {
	local name="$1" version="$2" typed="$3"
	shift 3
	local top="${name}-${version}"
	local root="${WORK}/sdist_src"
	local file="${WORK}/${top}.tar.gz"
	rm -rf "${root}"
	mkdir -p "${root}/${top}"
	if [ "${PKGINFO:-1}" = "1" ]; then
		{
			echo "Metadata-Version: 2.4"
			echo "Name: ${name}"
			echo "Version: ${version}"
			for extra in "$@"; do echo "Provides-Extra: ${extra}"; done
		} >"${root}/${top}/PKG-INFO"
	fi
	if [ "${typed}" != "-" ]; then
		mkdir -p "${root}/${top}/${typed}"
		touch "${root}/${top}/${typed}/py.typed"
	fi
	touch "${root}/${top}/pyproject.toml"
	tar -czf "${file}" -C "${root}" "${top}"
	echo "${file}"
}

@test "wheel ok" {
	f="$(make_wheel mypkg 1.0 mypkg numpy)"
	run call check_dist "$f" mypkg mypkg numpy
	[ "$status" -eq 0 ]
	[[ "$output" =~ "✅" ]]
}

@test "sdist ok" {
	f="$(make_sdist mypkg 1.0 src/mypkg numpy)"
	run call check_dist "$f" mypkg mypkg numpy
	[ "$status" -eq 0 ]
}

@test "wheel with wrong name fails" {
	f="$(make_wheel other 1.0 other)"
	run --separate-stderr call check_dist "$f" mypkg other
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "❌ wrong package name" ]]
	[[ "$stderr" =~ "expected mypkg, got other" ]]
}

@test "sdist with wrong name fails" {
	f="$(make_sdist other 1.0 other)"
	run --separate-stderr call check_dist "$f" mypkg other
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "wrong package name" ]]
}

@test "package name is compared in normalized form" {
	f="$(make_wheel my_pkg 1.0 my_pkg)"
	run call check_dist "$f" My.Pkg my_pkg
	[ "$status" -eq 0 ]
}

@test "wheel version 0.0.0 fails" {
	f="$(make_wheel mypkg 0.0.0 mypkg)"
	run --separate-stderr call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "invalid version" ]]
}

@test "sdist version 0.0.0 fails" {
	f="$(make_sdist mypkg 0.0.0 mypkg)"
	run --separate-stderr call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
}

@test "wheel with missing extra fails" {
	f="$(make_wheel mypkg 1.0 mypkg numpy)"
	run --separate-stderr call check_dist "$f" mypkg mypkg "numpy,torch"
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected torch" ]]
}

@test "sdist with missing extra fails" {
	f="$(make_sdist mypkg 1.0 mypkg numpy)"
	run --separate-stderr call check_dist "$f" mypkg mypkg torch
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "extra not defined" ]]
}

@test "extra with different case and separator passes" {
	f="$(make_wheel mypkg 1.0 mypkg foo-bar)"
	run call check_dist "$f" mypkg mypkg "Foo_Bar"
	[ "$status" -eq 0 ]
}

@test "extra name is not used as a regex" {
	f="$(make_wheel mypkg 1.0 mypkg numpy)"
	run call check_dist "$f" mypkg mypkg "nu.py"
	[ "$status" -eq 1 ]
}

@test "empty extras list passes" {
	f="$(make_wheel mypkg 1.0 mypkg)"
	run call check_dist "$f" mypkg mypkg ""
	[ "$status" -eq 0 ]
}

@test "extras list with spaces and trailing comma passes" {
	f="$(make_wheel mypkg 1.0 mypkg a b)"
	run call check_dist "$f" mypkg mypkg " a , b ,"
	[ "$status" -eq 0 ]
}

@test "wheel without py.typed fails" {
	f="$(make_wheel mypkg 1.0 -)"
	run --separate-stderr call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "expected mypkg/py.typed" ]]
}

@test "py.typed in an unrelated directory fails (F5)" {
	f="$(make_wheel mypkg 1.0 tests/other)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
}

@test "wheel with py.typed only under tests/ fails (regression G4)" {
	f="$(make_wheel mypkg 1.0 tests/mypkg)"
	run --separate-stderr call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "py.typed marker missing" ]]
}

@test "sdist without py.typed passes: only the wheel is checked (regression G4)" {
	f="$(make_sdist mypkg 1.0 -)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 0 ]
}

@test "sdist with py.typed under tests/ does not matter (regression G4)" {
	f="$(make_sdist mypkg 1.0 tests/mypkg)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 0 ]
}

@test "read_version prints the version of a wheel" {
	f="$(make_wheel mypkg 1.2.3 -)"
	run bash -c "source '${SCRIPT}'; read_version '$f'"
	[ "$status" -eq 0 ]
	[ "$output" = "1.2.3" ]
}

@test "read_version prints the version of an sdist" {
	f="$(make_sdist mypkg 4.5.6 -)"
	run bash -c "source '${SCRIPT}'; read_version '$f'"
	[ "$output" = "4.5.6" ]
}

@test "read_version fails on a missing archive" {
	run bash -c "source '${SCRIPT}'; read_version '${WORK}/nope.whl'"
	[ "$status" -ne 0 ]
}

@test "py.typed of a longer module name does not match" {
	f="$(make_wheel mypkg 1.0 not_mypkg)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
}

@test "sdist py.typed in flat layout passes" {
	f="$(make_sdist mypkg 1.0 mypkg)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 0 ]
}

@test "dotted module name means a sub-package" {
	f="$(make_wheel mypkg 1.0 a/b)"
	run call check_dist "$f" mypkg a.b
	[ "$status" -eq 0 ]
}

@test "default module name replaces hyphens and dots" {
	f="$(make_wheel my-pkg.x 1.0 my_pkg_x)"
	run call check_dist "$f" my-pkg.x
	[ "$status" -eq 0 ]
}

@test "check_types false skips the py.typed marker" {
	f="$(make_wheel mypkg 1.0 -)"
	run call check_dist "$f" mypkg mypkg "" false
	[ "$status" -eq 0 ]
}

@test "all failures are reported in one run" {
	f="$(make_wheel other 0.0.0 -)"
	run --separate-stderr call check_dist "$f" mypkg mypkg torch
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "wrong package name" ]]
	[[ "$stderr" =~ "invalid version" ]]
	[[ "$stderr" =~ "extra not defined" ]]
	[[ "$stderr" =~ "py.typed marker missing" ]]
}

@test "missing file fails" {
	run --separate-stderr call check_dist "${WORK}/nope.whl" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "archive not found" ]]
}

@test "wrong extension fails" {
	touch "${WORK}/file.zip"
	run --separate-stderr call check_dist "${WORK}/file.zip" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "unsupported archive type" ]]
}

@test "sdist without PKG-INFO fails" {
	PKGINFO=0 f="$(PKGINFO=0 make_sdist mypkg 1.0 mypkg)"
	run --separate-stderr call check_dist "$f" mypkg
	[ "$status" -eq 1 ]
	[[ "$stderr" =~ "core metadata file not found" ]]
}

@test "headers after the first blank line are ignored" {
	f="$(make_wheel mypkg 1.0 mypkg)"
	run call check_dist "$f" mypkg
	[ "$status" -eq 0 ]
}

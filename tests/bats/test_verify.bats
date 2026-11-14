#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The real lib.sh, check_dist.sh and verify.sh run from a copy of scripts/ in
# which check_install.sh and check_types.sh define stub functions that record
# how they are called. uv and uvx are mocked on PATH: `uv build` writes small archives.

setup() {
	WORK="$(mktemp -d)"
	WORK="$(cd "${WORK}" && pwd -P)"
	mkdir -p "${WORK}/bin" "${WORK}/runner" "${WORK}/proj" "${WORK}/scripts"
	cp scripts/lib.sh scripts/check_dist.sh scripts/verify.sh "${WORK}/scripts/"
	touch "${WORK}/proj/pyproject.toml"

	for name in check_install check_types; do
		cat >"${WORK}/scripts/${name}.sh" <<STUB
${name}() {
	echo "args=\$*" >>"\${CALLS}/${name}"
	return "\${STUB_STATUS:-0}"
}
STUB
	done

	cat >"${WORK}/bin/uv" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
build)
	echo "$*" >>"${CALLS}/uv_build"
	out=""
	while [ $# -gt 0 ]; do
		[ "$1" = "--out-dir" ] && out="$2"
		shift
	done
	mkdir -p "${out}"
	for i in $(seq 1 "${WHEELS:-1}"); do
		bash "${MKARCHIVE}" wheel "${out}" "${WHEEL_VERSION:-1.0}" "$i"
	done
	for i in $(seq 1 "${SDISTS:-1}"); do
		bash "${MKARCHIVE}" sdist "${out}" "${SDIST_VERSION:-1.0}" "$i"
	done
	;;
venv)
	echo "cwd=${PWD} args=$*" >>"${CALLS}/uv_venv"
	mkdir -p "$2/bin"
	;;
pip)
	echo "args=$*" >>"${CALLS}/uv_install"
	;;
esac
exit "${UV_STATUS:-0}"
FAKE
	cat >"${WORK}/bin/uvx" <<'FAKE'
#!/usr/bin/env bash
echo "cwd=${PWD} args=$*" >>"${CALLS}/uvx"
exit "${UVX_STATUS:-0}"
FAKE
	cat >"${WORK}/mkarchive.sh" <<'FAKE'
#!/usr/bin/env bash
# mkarchive.sh <wheel|sdist> <out dir> <version> <index>
kind="$1" out="$2" version="$3" index="$4"
src="$(mktemp -d)"
suffix=""
[ "${index}" = "1" ] || suffix="${index}"
if [ "${kind}" = "wheel" ]; then
	mkdir -p "${src}/myproject${suffix}-${version}.dist-info" "${src}/myproject"
	touch "${src}/myproject/py.typed"
	printf 'Metadata-Version: 2.4\nName: myproject\nVersion: %s\nProvides-Extra: all\n' "${version}" \
		>"${src}/myproject${suffix}-${version}.dist-info/METADATA"
	(cd "${src}" && zip -qr "${out}/myproject${suffix}-${version}-py3-none-any.whl" .)
else
	top="myproject${suffix}-${version}"
	mkdir -p "${src}/${top}"
	printf 'Metadata-Version: 2.4\nName: myproject\nVersion: %s\nProvides-Extra: all\n' "${version}" \
		>"${src}/${top}/PKG-INFO"
	tar -czf "${out}/${top}.tar.gz" -C "${src}" "${top}"
fi
rm -rf "${src}"
FAKE
	chmod +x "${WORK}/bin/uv" "${WORK}/bin/uvx"

	export CALLS="${WORK}/calls"
	mkdir -p "${CALLS}"
	export MKARCHIVE="${WORK}/mkarchive.sh"
	export PATH="${WORK}/bin:${PATH}"
	export PACKAGE_NAME="myproject"
	export PROJECT_PATH="${WORK}/proj"
	export RUNNER_TEMP="${WORK}/runner"
	unset GITHUB_OUTPUT GITHUB_ACTIONS MODULE_NAME PACKAGE_EXTRA PACKAGE_DEPENDENCIES \
		DIST_TYPE TWINE_VERSION PYRIGHT_VERSION CHECK_TYPES
	VERIFY="${WORK}/scripts/verify.sh"
}

teardown() {
	rm -rf "${WORK}"
}

count() {
	if [ -f "${CALLS}/$1" ]; then wc -l <"${CALLS}/$1" | tr -d ' '; else echo 0; fi
}

@test "succeeds with the defaults and a clean project" {
	run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"All checks passed"* ]]
}

@test "all invalid inputs are reported together with exit 2" {
	PACKAGE_NAME="my project" MODULE_NAME="a+b" DIST_TYPE=tar CHECK_TYPES=maybe \
		PROJECT_PATH="${WORK}/nope" TWINE_VERSION="--bad" PYRIGHT_VERSION="x y" \
		run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"package-name"* ]]
	[[ "$stderr" == *"module-name"* ]]
	[[ "$stderr" == *"dist-type"* ]]
	[[ "$stderr" == *"check-types"* ]]
	[[ "$stderr" == *"project-path"* ]]
	[[ "$stderr" == *"twine-version"* ]]
	[[ "$stderr" == *"pyright-version"* ]]
	[ "$(count uv_build)" -eq 0 ]
}

@test "missing package name exits 2" {
	unset PACKAGE_NAME
	run -2 bash "${VERIFY}"
}

@test "latest is a valid tool version" {
	TWINE_VERSION=latest PYRIGHT_VERSION=latest run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	grep -Fq "twine@latest" "${CALLS}/uvx"
}

@test "build runs with --no-sources on the project path" {
	run bash "${VERIFY}"
	grep -Fq -- "build ${WORK}/proj --no-config --no-sources --out-dir" "${CALLS}/uv_build"
}

@test "build output with no wheel fails" {
	WHEELS=0 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"exactly 1 wheel"* ]]
}

@test "build output with two wheels fails" {
	WHEELS=2 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"exactly 1 wheel"* ]]
}

@test "build output with no sdist fails" {
	SDISTS=0 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"exactly 1 sdist"* ]]
}

@test "a failing build fails" {
	UV_STATUS=1 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"uv build failed"* ]]
}

@test "outputs hold the paths and the version of the wheel" {
	GITHUB_OUTPUT="${WORK}/out" WHEEL_VERSION=2.3.4 SDIST_VERSION=2.3.4 run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	grep -q '^version=2.3.4$' "${WORK}/out"
	wheel="$(sed -n 's/^wheel-path=//p' "${WORK}/out")"
	sdist="$(sed -n 's/^sdist-path=//p' "${WORK}/out")"
	[ -f "${wheel}" ]
	[ -f "${sdist}" ]
}

@test "outputs are written even when a later check fails" {
	GITHUB_OUTPUT="${WORK}/out" STUB_STATUS=1 run bash "${VERIFY}"
	[ "$status" -eq 1 ]
	grep -q '^wheel-path=' "${WORK}/out"
}

@test "local run works without GITHUB_OUTPUT" {
	run bash "${VERIFY}"
	[ "$status" -eq 0 ]
}

@test "two invocations get distinct directories and keep the first outputs (regression G1)" {
	GITHUB_OUTPUT="${WORK}/out1" run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	GITHUB_OUTPUT="${WORK}/out2" run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	wheel1="$(sed -n 's/^wheel-path=//p' "${WORK}/out1")"
	wheel2="$(sed -n 's/^wheel-path=//p' "${WORK}/out2")"
	[ "${wheel1}" != "${wheel2}" ]
	[ -f "${wheel1}" ]
	[ -f "${wheel2}" ]
}

@test "every uv call ignores the project configuration (regression H1)" {
	run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	grep -Fq -- "--no-config" "${CALLS}/uv_build"
	[ "$(count uv_venv)" -gt 0 ]
	while IFS= read -r line; do [[ "${line}" == *"--no-config"* ]]; done <"${CALLS}/uv_venv"
	[ "$(count uv_install)" -gt 0 ]
	while IFS= read -r line; do [[ "${line}" == *"--no-config"* ]]; done <"${CALLS}/uv_install"
	grep -Fq -- "--no-config" "${CALLS}/uvx"
}

@test "the install targets the venv explicitly, not through VIRTUAL_ENV (regression H1)" {
	VIRTUAL_ENV=/somewhere/else run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	while IFS= read -r line; do
		[[ "${line}" == *"--python ${WORK}/runner/verify-uv-build."*"/venv-"* ]]
	done <"${CALLS}/uv_install"
}

@test "the caller's working directory is not changed by the install" {
	cd "${WORK}/proj"
	PROJECT_PATH=. run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	grep -Fq -- "build . --no-config --no-sources" "${CALLS}/uv_build"
}

@test "dist-type both installs and checks both artifacts" {
	DIST_TYPE=both run bash "${VERIFY}"
	[ "$(count uv_install)" -eq 2 ]
	[ "$(count uv_venv)" -eq 2 ]
	[ "$(count check_install)" -eq 2 ]
}

@test "the default dist-type is both" {
	run bash "${VERIFY}"
	[ "$(count uv_install)" -eq 2 ]
}

@test "dist-type wheel installs once, from the wheel" {
	DIST_TYPE=wheel run bash "${VERIFY}"
	[ "$(count uv_install)" -eq 1 ]
	grep -Fq ".whl" "${CALLS}/uv_install"
}

@test "dist-type sdist installs once, from the sdist" {
	DIST_TYPE=sdist run bash "${VERIFY}"
	[ "$(count uv_install)" -eq 1 ]
	grep -Fq ".tar.gz" "${CALLS}/uv_install"
}

@test "extras are installed through a direct reference" {
	PACKAGE_EXTRA="all" DIST_TYPE=wheel run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	grep -Fq "myproject[all] @ file://" "${CALLS}/uv_install"
}

@test "an unknown extra fails before any install" {
	PACKAGE_EXTRA="missing" run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"extra not defined"* ]]
	[ "$(count uv_install)" -eq 0 ]
}

@test "wheel and sdist with different versions fail (regression G12)" {
	WHEEL_VERSION=1.0 SDIST_VERSION=1.1 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"different versions"* ]]
	[ "$(count uv_install)" -eq 0 ]
}

@test "the placeholder version fails" {
	WHEEL_VERSION=0.0.0 SDIST_VERSION=0.0.0 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"invalid version"* ]]
}

@test "twine runs with the requested version from the work directory" {
	TWINE_VERSION=6.2.0 run bash "${VERIFY}"
	grep -Fq "twine@6.2.0 check --strict" "${CALLS}/uvx"
	grep -Fq "cwd=${WORK}/runner/verify-uv-build." "${CALLS}/uvx"
}

@test "a twine failure exits 1 and skips the install" {
	UVX_STATUS=1 run --separate-stderr bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"twine check failed"* ]]
	[ "$(count uv_install)" -eq 0 ]
}

@test "an install failure exits 1 and skips the checks" {
	UV_STATUS=1 run bash "${VERIFY}"
	[ "$status" -eq 1 ]
}

@test "check_install receives the package, module, dependencies and wheel version" {
	MODULE_NAME=mod CHECK_TYPES=false PACKAGE_DEPENDENCIES="a,b" WHEEL_VERSION=1.5 SDIST_VERSION=1.5 DIST_TYPE=wheel run bash "${VERIFY}"
	grep -Fq "venv-wheel myproject mod a,b 1.5" "${CALLS}/check_install"
}

@test "a failing check_install exits 1 and skips the type check" {
	STUB_STATUS=1 run bash "${VERIFY}"
	[ "$status" -eq 1 ]
	[ "$(count check_types)" -eq 0 ]
}

@test "types are checked once, on the wheel, when both are installed" {
	PYRIGHT_VERSION=1.2.3 run bash "${VERIFY}"
	[ "$(count check_types)" -eq 1 ]
	grep -Fq "venv-wheel myproject  1.2.3" "${CALLS}/check_types"
}

@test "types are checked on the sdist when only the sdist is installed" {
	DIST_TYPE=sdist run bash "${VERIFY}"
	grep -Fq "venv-sdist" "${CALLS}/check_types"
}

@test "check-types false skips pyright and the py.typed marker" {
	CHECK_TYPES=false run bash "${VERIFY}"
	[ "$status" -eq 0 ]
	[ "$(count check_types)" -eq 0 ]
}

@test "sourcing the script does not run it" {
	run bash -c "source '${VERIFY}'; declare -F validate_inputs"
	[ "$status" -eq 0 ]
	[ "$output" = "validate_inputs" ]
	[ "$(count uv_build)" -eq 0 ]
}

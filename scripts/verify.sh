#!/usr/bin/env bash

# verify.sh - Build a Python package with uv and verify the wheel and sdist
#
# Description:
#   Entry point of the action, also usable locally. Phases, each in a log
#   group, in a fail-fast order:
#     1. validate the inputs (every invalid input is reported, exit 2)
#     2. build with `uv build --no-config --no-sources` into a new work directory, check
#        that there is exactly one wheel and one sdist
#     3. check the archives: check_dist.sh on both, same version in both,
#        `twine check --strict`
#     4. install each selected artifact in its own venv; every uv call uses
#        `--no-config`, so the project configuration (`[tool.uv]`, `uv.toml`)
#        is never read
#     5. check_install.sh for each venv
#     6. check_types.sh once, on the first installed artifact (if CHECK_TYPES)
#   Every invocation gets its own work directory, which is never deleted, so
#   the outputs of an earlier invocation stay valid.
#
# Usage:
#   PACKAGE_NAME=<name> [VAR=value ...] bash scripts/verify.sh
#
# Environment (the inputs of the action, in upper case with "_"):
#   PACKAGE_NAME          Distribution name (required)
#   MODULE_NAME           Import name. Default: derived from PACKAGE_NAME
#   PACKAGE_EXTRA         Comma-separated extras to install and verify
#   PACKAGE_DEPENDENCIES  Comma-separated direct dependencies that must be
#                         installed
#   DIST_TYPE             wheel, sdist or both. Default: both
#   PROJECT_PATH          Directory with the pyproject.toml. Default: .
#   TWINE_VERSION         "latest" or a version. Default: 7.0.0
#   PYRIGHT_VERSION       "latest" or a version. Default: 1.1.414
#   CHECK_TYPES           true or false. Default: true
#   RUNNER_TEMP           Parent of the work directory. Default: TMPDIR or /tmp
#   GITHUB_OUTPUT         When set, wheel-path, sdist-path and version are
#                         appended to it
#
# Examples:
#   PACKAGE_NAME=mypkg bash scripts/verify.sh
#   PACKAGE_NAME=mypkg DIST_TYPE=wheel PACKAGE_EXTRA=all bash scripts/verify.sh
#
# Requirements:
#   uv (uv, uvx) in PATH, with network access
#
# Exit Codes:
#   0 - All checks passed
#   1 - A check failed
#   2 - Invalid inputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=scripts/check_dist.sh
source "${SCRIPT_DIR}/check_dist.sh"

# Fill the optional inputs that are unset or empty with their default.
apply_defaults() {
	PROJECT_PATH="${PROJECT_PATH:-.}"
	DIST_TYPE="${DIST_TYPE:-both}"
	CHECK_TYPES="${CHECK_TYPES:-true}"
	TWINE_VERSION="${TWINE_VERSION:-7.0.0}"
	PYRIGHT_VERSION="${PYRIGHT_VERSION:-1.1.414}"
	MODULE_NAME="${MODULE_NAME:-}"
	PACKAGE_EXTRA="${PACKAGE_EXTRA:-}"
	PACKAGE_DEPENDENCIES="${PACKAGE_DEPENDENCIES:-}"
}

# Check all inputs. Reports every invalid input, returns 1 if any.
validate_inputs() {
	local failures=0
	if [[ ! "${PACKAGE_NAME:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]]; then
		log_error "Input 'package-name' is not a valid distribution name (got '${PACKAGE_NAME:-}')"
		failures=$((failures + 1))
	fi
	if [ -n "${MODULE_NAME}" ] && ! is_dotted_identifier "${MODULE_NAME}"; then
		log_error "Input 'module-name' must be a dotted Python identifier (got '${MODULE_NAME}')"
		failures=$((failures + 1))
	fi
	case "${DIST_TYPE}" in
	wheel | sdist | both) ;;
	*)
		log_error "Input 'dist-type' must be 'wheel', 'sdist' or 'both' (got '${DIST_TYPE}')"
		failures=$((failures + 1))
		;;
	esac
	case "${CHECK_TYPES}" in
	true | false) ;;
	*)
		log_error "Input 'check-types' must be 'true' or 'false' (got '${CHECK_TYPES}')"
		failures=$((failures + 1))
		;;
	esac
	if [ ! -f "${PROJECT_PATH}/pyproject.toml" ]; then
		log_error "No pyproject.toml found in project-path (expected '${PROJECT_PATH}/pyproject.toml')"
		failures=$((failures + 1))
	fi
	if ! is_version_spec "${TWINE_VERSION}"; then
		log_error "Input 'twine-version' must be 'latest' or a version (got '${TWINE_VERSION}')"
		failures=$((failures + 1))
	fi
	if ! is_version_spec "${PYRIGHT_VERSION}"; then
		log_error "Input 'pyright-version' must be 'latest' or a version (got '${PYRIGHT_VERSION}')"
		failures=$((failures + 1))
	fi
	[ "${failures}" -eq 0 ] || return 1
	log_ok "Inputs are valid"
}

# Print the artifact types to install: wheel, sdist or both.
selected_types() {
	case "${DIST_TYPE}" in
	both) printf '%s\n' wheel sdist ;;
	*) printf '%s\n' "${DIST_TYPE}" ;;
	esac
}

# Build the package into ${WORK}/dist and set WHEEL_PATH, SDIST_PATH, VERSION.
build_dists() {
	local dist_dir="${WORK}/dist"
	local wheels sdists
	mkdir -p "${dist_dir}"
	echo "📦 Building package..."
	# --no-config ignores the project's [tool.uv] and uv.toml, --no-sources
	# ignores [tool.uv.sources]: the build resolves requirements like a user
	# installing from PyPI.
	if ! uv build "${PROJECT_PATH}" --no-config --no-sources --out-dir "${dist_dir}"; then
		log_error "uv build failed (expected a successful build, see output above)"
		return 1
	fi
	wheels=()
	while IFS= read -r f; do wheels+=("${f}"); done < <(find "${dist_dir}" -maxdepth 1 -name '*.whl' | sort)
	sdists=()
	while IFS= read -r f; do sdists+=("${f}"); done < <(find "${dist_dir}" -maxdepth 1 -name '*.tar.gz' | sort)
	if [ "${#wheels[@]}" -ne 1 ]; then
		log_error "Expected exactly 1 wheel in the build output (got ${#wheels[@]})"
		return 1
	fi
	if [ "${#sdists[@]}" -ne 1 ]; then
		log_error "Expected exactly 1 sdist in the build output (got ${#sdists[@]})"
		return 1
	fi
	WHEEL_PATH="${wheels[0]}"
	SDIST_PATH="${sdists[0]}"
	if ! VERSION="$(read_version "${WHEEL_PATH}")"; then
		log_error "No Version found in the wheel metadata (expected a Version header in ${WHEEL_PATH})"
		return 1
	fi
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		{
			echo "wheel-path=${WHEEL_PATH}"
			echo "sdist-path=${SDIST_PATH}"
			echo "version=${VERSION}"
		} >>"${GITHUB_OUTPUT}"
	fi
	log_ok "Built ${WHEEL_PATH##*/} and ${SDIST_PATH##*/}"
}

# Check the metadata of both archives, that they agree, and run twine.
check_archives() {
	local status=0 sdist_version
	bash "${SCRIPT_DIR}/check_dist.sh" "${WHEEL_PATH}" "${PACKAGE_NAME}" "${MODULE_NAME}" \
		"${PACKAGE_EXTRA}" "${CHECK_TYPES}" || status=1
	# The wheel is built from the sdist: the marker is only checked in the wheel.
	bash "${SCRIPT_DIR}/check_dist.sh" "${SDIST_PATH}" "${PACKAGE_NAME}" "${MODULE_NAME}" \
		"${PACKAGE_EXTRA}" false || status=1
	if sdist_version="$(read_version "${SDIST_PATH}")" && [ "${sdist_version}" != "${VERSION}" ]; then
		log_error "wheel and sdist have different versions (expected ${VERSION}, got ${sdist_version} in ${SDIST_PATH##*/})"
		status=1
	fi
	[ "${status}" -eq 0 ] || return 1
	echo "🔍 Running twine check..."
	if ! (cd "${WORK}" && uvx --no-config "twine@${TWINE_VERSION}" check --strict "${WHEEL_PATH}" "${SDIST_PATH}"); then
		log_error "twine check failed (expected no error or warning, see output above)"
		return 1
	fi
	log_ok "Artifact checks passed"
}

# Install one artifact in its own venv. --no-config makes uv ignore the
# project configuration whatever the working directory.
install_dist() {
	local type="$1"
	local venv="${WORK}/venv-${type}"
	local target extras
	case "${type}" in
	wheel) target="${WHEEL_PATH}" ;;
	*) target="${SDIST_PATH}" ;;
	esac
	extras="${PACKAGE_EXTRA// /}"
	if [ -n "${extras}" ]; then
		# A direct reference, because "<absolute path>[extra]" is not parsed by uv.
		target="${PACKAGE_NAME}[${extras}] @ file://${target}"
	fi
	echo "📦 Installing ${target}"
	if ! (uv venv --no-config "${venv}" && uv pip install --no-config --python "${venv}" "${target}"); then
		log_error "Installation of the ${type} failed (expected ${target} to install, see output above)"
		return 1
	fi
	log_ok "${type} installed"
}

# Run check_install.sh on the venv of one artifact, outside the checkout so
# that the source tree cannot be imported instead of the installed package.
check_installed() {
	local type="$1"
	local venv="${WORK}/venv-${type}"
	echo "🔍 Checking the installed ${type}"
	(cd "${WORK}" && VIRTUAL_ENV="${venv}" PATH="${venv}/bin:${PATH}" \
		bash "${SCRIPT_DIR}/check_install.sh" "${PACKAGE_NAME}" "${MODULE_NAME}" \
		"${PACKAGE_DEPENDENCIES}" "${VERSION}")
}

check_types_installed() {
	local type="$1"
	(cd "${WORK}" && VIRTUAL_ENV="${WORK}/venv-${type}" PYRIGHT_VERSION="${PYRIGHT_VERSION}" \
		bash "${SCRIPT_DIR}/check_types.sh" "${PACKAGE_NAME}" "${MODULE_NAME}")
}

# Run "<function> <type>" for each selected type, report all failures.
for_each_type() {
	local func="$1" type status=0
	while IFS= read -r type; do
		"${func}" "${type}" || status=1
	done < <(selected_types)
	return "${status}"
}

# Run a phase inside a log group. Usage: run_phase <title> <function> [args]
run_phase() {
	local title="$1" status=0
	shift
	group_start "${title}"
	"$@" || status=1
	group_end
	return "${status}"
}

run_checks() {
	local first
	first="$(selected_types | sed -n 1p)"
	run_phase "Build" build_dists || return 1
	run_phase "Check archives" check_archives || return 1
	run_phase "Install" for_each_type install_dist || return 1
	run_phase "Check install" for_each_type check_installed || return 1
	if [ "${CHECK_TYPES}" = "true" ]; then
		run_phase "Check types" check_types_installed "${first}" || return 1
	fi
	log_ok "All checks passed"
}

main() {
	apply_defaults
	validate_inputs || exit 2
	WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/verify-uv-build.XXXXXX")"
	run_checks || exit 1
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi

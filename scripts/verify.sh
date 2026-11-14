#!/usr/bin/env bash

# verify.sh - Build a Python package with uv and verify the wheel and sdist
#
# Description:
#   Entry point of the action, also usable locally. The check_*.sh scripts
#   are libraries sourced here, not commands. Phases, each in a log
#   group, in a fail-fast order:
#     1. validate the inputs (every invalid input is reported, exit 2)
#     2. build with `uv build --no-config --no-sources` into a new work directory, check
#        that there is exactly one wheel and one sdist
#     3. check the archives: check_dist on both, same version in both,
#        `twine check --strict`
#     4. install each selected artifact in its own venv; every uv call uses
#        `--no-config`, so the project configuration (`[tool.uv]`, `uv.toml`)
#        is never read
#     5. check_install for each venv
#     6. check_types once, on the first installed artifact (if CHECK_TYPES)
#   Every invocation gets its own work directory, which is never deleted, so
#   the outputs of an earlier invocation stay valid.
#   Every phase appends its result, and lib.sh appends every error, to
#   <work directory>/report. An EXIT trap renders the job summary from it, so
#   the summary states the verdict, the failed phase and the reason even when
#   the run failed. The outputs are written right after the build, so they
#   exist even when a later phase fails.
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
#   DIST_TYPE             wheel, sdist or both. Default: see action.yaml
#   PROJECT_PATH          Directory with the pyproject.toml. Default: see action.yaml
#   TWINE_VERSION         "latest" or a version. Default: the pin of
#                         scripts/requirements.txt
#   PYRIGHT_VERSION       Same

#   CHECK_TYPES           true or false. Default: true
#   RUNNER_TEMP           Parent of the work directory. Default: TMPDIR or /tmp
#   GITHUB_OUTPUT         When set, wheel-path, sdist-path and version are
#                         appended to it
#   GITHUB_STEP_SUMMARY   When set, the verdict, a table of the phases and the
#                         content of the archives are appended to it
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
# shellcheck source=scripts/check_install.sh
source "${SCRIPT_DIR}/check_install.sh"
# shellcheck source=scripts/check_types.sh
source "${SCRIPT_DIR}/check_types.sh"

# Fill the optional inputs that are unset or empty with their default: the
# default of action.yaml, or for the tools the pin of requirements.txt.
apply_defaults() {
	PROJECT_PATH="${PROJECT_PATH:-$(action_default project-path)}"
	DIST_TYPE="${DIST_TYPE:-$(action_default dist-type)}"
	CHECK_TYPES="${CHECK_TYPES:-$(action_default check-types)}"
	TWINE_VERSION="${TWINE_VERSION:-$(tool_pin twine)}"
	PYRIGHT_VERSION="${PYRIGHT_VERSION:-$(tool_pin pyright)}"
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
	check_dist "${WHEEL_PATH}" "${PACKAGE_NAME}" "${MODULE_NAME}" \
		"${PACKAGE_EXTRA}" "${CHECK_TYPES}" || status=1
	# The wheel is built from the sdist: the marker is only checked in the wheel.
	check_dist "${SDIST_PATH}" "${PACKAGE_NAME}" "${MODULE_NAME}" \
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

# Check the installed package of one artifact. The import runs in isolated
# mode, so the source tree of the checkout cannot be imported instead.
check_installed() {
	local type="$1"
	echo "🔍 Checking the installed ${type}"
	check_install "${WORK}/venv-${type}" "${PACKAGE_NAME}" "${MODULE_NAME}" \
		"${PACKAGE_DEPENDENCIES}" "${VERSION}"
}

check_types_installed() {
	check_types "${WORK}/venv-$1" "${PACKAGE_NAME}" "${MODULE_NAME}" "${PYRIGHT_VERSION}"
}

# Run "<function> <type>" for each selected type, report all failures.
for_each_type() {
	local func="$1" type status=0
	while IFS= read -r type; do
		"${func}" "${type}" || status=1
	done < <(selected_types)
	return "${status}"
}

# The phases, in order. The summary lists them all.
PHASES=("Validate" "Build" "Check archives" "Install" "Check install" "Check types")

# Record the result of a phase in the report: record_phase <ok|failed> <title>
record_phase() {
	echo "${1}|${2}" >>"${REPORT_FILE}"
}

# Run a phase inside a log group and record its result.
# Usage: run_phase <title> <function> [args]
run_phase() {
	local title="$1" status=0
	shift
	group_start "${title}"
	"$@" || status=1
	group_end
	if [ "${status}" -eq 0 ]; then
		record_phase ok "${title}"
	else
		record_phase failed "${title}"
	fi
	return "${status}"
}

# Print the markdown cell of a phase: ✅, ❌ or skipped.
phase_result() {
	if grep -Fxq "ok|$1" "${REPORT_FILE}"; then
		echo "✅"
	elif grep -Fxq "failed|$1" "${REPORT_FILE}"; then
		echo "❌"
	else
		echo "skipped"
	fi
}

# Append the verdict, the failed phase, the reasons, a table of the phases and
# the content of the archives to the job summary. Usage: write_summary <exit code>
write_summary() {
	local code="$1" failed phase file
	[ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -f "${REPORT_FILE:-}" ] || return 0
	failed="$(sed -n 's/^failed|//p' "${REPORT_FILE}" | sed -n 1p)"
	{
		if [ "${code}" -eq 0 ]; then
			echo "## ✅ Verify uv build: passed"
		elif [ -n "${failed}" ]; then
			echo "## ❌ Verify uv build: failed in \"${failed}\""
		else
			echo "## ❌ Verify uv build: failed"
		fi
		echo
		sed -n 's/^error|/- ❌ /p' "${REPORT_FILE}"
		echo
		echo "| Phase | Result |"
		echo "| ----- | ------ |"
		for phase in "${PHASES[@]}"; do
			echo "| ${phase} | $(phase_result "${phase}") |"
		done
		for file in "${WHEEL_PATH:-}" "${SDIST_PATH:-}"; do
			[ -n "${file}" ] && [ -f "${file}" ] || continue
			echo
			echo "<details><summary>Content of ${file##*/}</summary>"
			echo
			echo '```text'
			list_archive "${file}" || true
			echo '```'
			echo "</details>"
		done
	} >>"${GITHUB_STEP_SUMMARY}"
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
	WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/verify-uv-build.XXXXXX")"
	REPORT_FILE="${WORK}/report"
	: >"${REPORT_FILE}"
	trap 'write_summary "$?"' EXIT
	if ! validate_inputs; then
		record_phase failed Validate
		exit 2
	fi
	record_phase ok Validate
	run_checks || exit 1
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi

#!/usr/bin/env bash

# check_install.sh - Verify an installed package and that it imports
#
# Description:
#   Runs `uv pip show` once for the package installed in a virtual environment
#   and `uv pip check` on the environment, and checks:
#     - the installed name matches <package_name> (PEP 503 normalized)
#     - the installed version is set, is not 0.0.0, and (if given) equals
#       <expected_version>
#     - `uv pip check` finds no missing or conflicting dependency
#     - every requested dependency is listed in `Requires` (normalized)
#     - the module imports, and its location is inside site-packages
#   The module is passed to Python as an argument, never interpolated into
#   source, and imported with `python -I` (isolated mode: neither the working
#   directory nor the environment variables are used), so a source tree in the
#   checkout cannot hide a broken package. All failures are reported before the
#   function returns.
#
# Library sourced by verify.sh, not a command. Its functions trust their
# caller: the inputs are validated once, in verify.sh.
#
# Functions:
#   check_install <venv> <package_name> [module_name] [dependencies] [expected_version]
#       venv              Environment where the package is installed
#       package_name      Distribution name
#       module_name       Import name. Default: package_name with "-" and "."
#                         replaced by "_"
#       dependencies      Comma-separated direct dependencies that must be
#                         installed. Default: none
#       expected_version  Version the installed package must have. Default: any
#
# Requirements:
#   - uv available in PATH
#
# Return Codes:
#   0 - All checks passed
#   1 - A check failed

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Print the value of a `uv pip show` field.
show_field() {
	sed -n "s/^$2:[[:space:]]*//p" <<<"$1" | sed -n 1p
}

# Print the location of the imported module, or fail with the import error.
import_location() {
	"$1/bin/python" -I -c '
import importlib
import sys

module = importlib.import_module(sys.argv[1])
path = getattr(module, "__file__", None) or list(module.__path__)[0]
print(path)
' "$2"
}

check_install() {
	local venv="$1"
	local package_name="$2"
	local module_name="${3:-}"
	local dependencies="${4:-}"
	local expected_version="${5:-}"
	local failures=0
	local info name version requires dep location check_output

	[ -n "${module_name}" ] || module_name="$(default_module_name "${package_name}")"

	if ! info="$(uv pip show --no-config --python "${venv}" "${package_name}")"; then
		log_error "package not installed (expected ${package_name}, got nothing from uv pip show)"
		return 1
	fi
	echo "${info}"
	if ! check_output="$(uv pip check --no-config --python "${venv}" 2>&1)"; then
		log_error "the environment has broken dependencies (expected uv pip check to pass, got: $(tr '\n' ' ' <<<"${check_output}"))"
		failures=$((failures + 1))
	fi

	name="$(show_field "${info}" "Name")"
	if [ "$(normalize_name "${name}")" != "$(normalize_name "${package_name}")" ]; then
		log_error "wrong installed package name (expected ${package_name}, got ${name:-<none>})"
		failures=$((failures + 1))
	fi

	version="$(show_field "${info}" "Version")"
	if [ -z "${version}" ] || [ "${version}" = "0.0.0" ]; then
		log_error "invalid installed version (expected a real version, got ${version:-<none>})"
		failures=$((failures + 1))
	elif [ -n "${expected_version}" ] && [ "${version}" != "${expected_version}" ]; then
		log_error "wrong installed version (expected ${expected_version}, got ${version})"
		failures=$((failures + 1))
	fi

	requires="$(show_field "${info}" "Requires" | tr ',' '\n' | while IFS= read -r dep; do
		dep="${dep#"${dep%%[![:space:]]*}"}"
		dep="${dep%"${dep##*[![:space:]]}"}"
		[ -z "${dep}" ] || {
			normalize_name "${dep}"
			echo
		}
	done)"
	while IFS= read -r dep; do
		[ -n "${dep}" ] || continue
		if ! grep -Fxq -- "${dep}" <<<"${requires}"; then
			log_error "dependency not installed (expected ${dep}, got: $(tr '\n' ' ' <<<"${requires}"))"
			failures=$((failures + 1))
		fi
	done < <(split_csv "${dependencies}")

	if ! location="$(import_location "${venv}" "${module_name}" 2>&1)"; then
		log_error "cannot import ${module_name} (expected a successful import, got: $(tail -n 1 <<<"${location}"))"
		failures=$((failures + 1))
	else
		case "${location}" in
		*/site-packages/* | */dist-packages/*) echo "📍 ${module_name} imported from ${location}" ;;
		*)
			log_error "${module_name} not imported from site-packages (expected a path inside site-packages, got ${location})"
			failures=$((failures + 1))
			;;
		esac
	fi

	if [ "${failures}" -gt 0 ]; then
		return 1
	fi
	log_ok "${package_name} ${version} is installed and importable"
}

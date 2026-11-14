#!/usr/bin/env bash

# check_types.sh - Verify package type completeness with pyright
#
# Description:
#   Runs `pyright --verifytypes` on an installed package through `uvx`, so
#   pyright is neither installed in the environment under test nor skipped
#   when it cannot run. The interpreter of the active environment is used
#   to resolve the package: its site-packages directory is passed through
#   PYTHONPATH, because `--pythonpath` is ignored by `--verifytypes` when
#   pyright is run through uvx. Run it from a directory that is not the
#   project checkout.
#
# Usage:
#   PYRIGHT_VERSION=<version> VIRTUAL_ENV=<venv> ./check_types.sh <package_name> [module_name]
#
# Arguments:
#   package_name - Distribution name (required)
#   module_name  - Import name of the package to check. Default: package_name
#                  with "-" and "." replaced by "_"
#
# Environment:
#   PYRIGHT_VERSION - pyright version run through uvx (required)
#   VIRTUAL_ENV     - environment where the package is installed (required)
#
# Examples:
#   PYRIGHT_VERSION=1.1.414 VIRTUAL_ENV=/tmp/venv ./check_types.sh my-package my_package
#
# Requirements:
#   - uv (uvx) available in PATH, with network access to fetch pyright
#
# Exit Codes:
#   0 - Type checking passed
#   1 - Type checking failed or pyright could not run
#   2 - Invalid arguments or environment

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
	echo "Usage: PYRIGHT_VERSION=<version> VIRTUAL_ENV=<venv> $0 <package_name> [module_name]" >&2
}

check_types() {
	local module_name="$1"
	local python="${VIRTUAL_ENV}/bin/python"
	local site_packages

	if ! site_packages="$("${python}" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"; then
		log_error "cannot query the environment (expected a working interpreter, got ${python})"
		return 1
	fi

	echo "🔍 Verifying type completeness for module: ${module_name}"
	echo "$ PYTHONPATH=${site_packages} uvx --no-config pyright@${PYRIGHT_VERSION} --verifytypes ${module_name} --ignoreexternal"
	# --ignoreexternal: do not report issues in external dependencies
	if ! PYTHONPATH="${site_packages}" uvx --no-config "pyright@${PYRIGHT_VERSION}" \
		--verifytypes "${module_name}" --ignoreexternal; then
		log_error "type completeness check failed for ${module_name} (expected pyright exit 0, got a failure; see output above)"
		return 1
	fi
	log_ok "Type hints validated for ${module_name}"
}

main() {
	if [ $# -lt 1 ] || [ $# -gt 2 ] || [ -z "$1" ]; then
		echo "Error: <package_name> [module_name] expected" >&2
		usage
		exit 2
	fi
	if [ -z "${PYRIGHT_VERSION:-}" ]; then
		echo "Error: PYRIGHT_VERSION is required" >&2
		usage
		exit 2
	fi
	if [ -z "${VIRTUAL_ENV:-}" ]; then
		echo "Error: VIRTUAL_ENV is required" >&2
		usage
		exit 2
	fi
	local module_name="${2:-}"
	[ -n "${module_name}" ] || module_name="$(default_module_name "$1")"
	if ! is_dotted_identifier "${module_name}"; then
		echo "Error: module_name must be a dotted identifier (got '${module_name}')" >&2
		usage
		exit 2
	fi
	check_types "${module_name}" || exit 1
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi

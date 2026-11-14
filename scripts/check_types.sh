#!/usr/bin/env bash

# check_types.sh - Verify package type completeness with pyright
#
# Description:
#   Runs `pyright --verifytypes` on an installed package through `uvx`, so
#   pyright is neither installed in the environment under test nor skipped
#   when it cannot run. The interpreter of the environment is used
#   to resolve the package: its site-packages directory is passed through
#   PYTHONPATH, because `--pythonpath` is ignored by `--verifytypes` when
#   pyright is run through uvx.
#
# Library sourced by verify.sh, not a command. Its functions trust their
# caller: the inputs are validated once, in verify.sh.
#
# Functions:
#   check_types <venv> <package_name> <module_name> <pyright_version>
#       venv             Environment where the package is installed
#       package_name     Distribution name, used for the default module name
#       module_name      Import name of the package to check. Empty: package_name
#                        with "-" and "." replaced by "_"
#       pyright_version  pyright version run through uvx
#
# Requirements:
#   - uv (uvx) available in PATH, with network access to fetch pyright
#
# Return Codes:
#   0 - Type checking passed
#   1 - Type checking failed or pyright could not run

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_types() {
	local venv="$1"
	local package_name="$2"
	local module_name="${3:-}"
	local pyright_version="$4"
	local python="${venv}/bin/python"
	local site_packages

	[ -n "${module_name}" ] || module_name="$(default_module_name "${package_name}")"

	if ! site_packages="$("${python}" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"; then
		log_error "cannot query the environment (expected a working interpreter, got ${python})"
		return 1
	fi

	echo "🔍 Verifying type completeness for module: ${module_name}"
	echo "$ PYTHONPATH=${site_packages} uvx --no-config pyright@${pyright_version} --verifytypes ${module_name} --ignoreexternal"
	# --ignoreexternal: do not report issues in external dependencies
	if ! PYTHONPATH="${site_packages}" uvx --no-config "pyright@${pyright_version}" \
		--verifytypes "${module_name}" --ignoreexternal; then
		log_error "type completeness check failed for ${module_name} (expected pyright exit 0, got a failure; see output above)"
		return 1
	fi
	log_ok "Type hints validated for ${module_name}"
}

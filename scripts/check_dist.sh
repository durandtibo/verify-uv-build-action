#!/usr/bin/env bash

# check_dist.sh - Verify a built wheel or sdist before installing it
#
# Description:
#   Reads the core metadata of one archive (`*.dist-info/METADATA` in a wheel,
#   the root `PKG-INFO` in an sdist) and checks:
#     - the distribution name matches <package_name> (PEP 503 normalized)
#     - the version is not the placeholder 0.0.0
#     - every requested extra is declared in `Provides-Extra` (PEP 685
#       normalized)
#     - the `<module path>/py.typed` marker is present in a wheel (if
#       check_types is true). It is not checked in an sdist: the wheel is
#       built from the sdist, so a wheel with the marker proves the sdist
#       ships it
#   All failures are reported before the script exits.
#
# Library sourced by verify.sh, not a command. Its functions trust their
# caller: the inputs are validated once, in verify.sh.
#
# Functions:
#   check_dist <archive> <package_name> [module_name] [extras] [check_types]
#       Verify one archive and print one error line per failed check. Returns
#       1 if any check failed. module_name defaults to package_name with "-"
#       and "." replaced by "_" (a dot means a sub-package: a.b -> a/b/py.typed).
#       extras is a comma-separated list. check_types is "true" (default) or
#       "false": whether py.typed is required in a wheel (ignored for an sdist)
#   read_field <archive> <Header> - print a header of the core metadata
#   read_version <archive> - print the Version of the core metadata
#
# Return Codes:
#   0 - All checks passed
#   1 - A check failed, or the archive is missing or unreadable

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Print the paths of all entries of the archive, one per line.
list_archive() {
	case "$1" in
	*.whl) unzip -Z1 "$1" ;;
	*.tar.gz) tar -tzf "$1" ;;
	esac
}

# Print the core metadata file of the archive.
read_metadata() {
	local archive="$1"
	local entries
	local path
	entries="$(list_archive "${archive}")"
	case "${archive}" in
	*.whl)
		path="$(grep -E '^[^/]+\.dist-info/METADATA$' <<<"${entries}" | sed -n 1p || true)"
		[ -n "${path}" ] || return 1
		unzip -p "${archive}" "${path}"
		;;
	*.tar.gz)
		path="$(grep -E '^[^/]+/PKG-INFO$' <<<"${entries}" | sed -n 1p || true)"
		[ -n "${path}" ] || return 1
		tar -xzOf "${archive}" "${path}"
		;;
	esac
}

# Print the value of a core metadata header (headers end at the first blank line).
# Usage: metadata_values <metadata> <Header-Name>
metadata_values() {
	awk -v key="$2" '
		/^$/ { exit }
		index($0, key ": ") == 1 { print substr($0, length(key) + 3) }
	' <<<"$1"
}

# Check whether the wheel contains <module path>/py.typed.
has_py_typed() {
	local archive="$1"
	local module_path="${2//.//}"
	local entries
	# Capture first: `grep -q` in a pipe can trigger SIGPIPE under pipefail
	entries="$(list_archive "${archive}")"
	grep -Eq "^${module_path}/py\.typed\$" <<<"${entries}"
}

# Print the first value of a core metadata header of the archive, fail if the
# metadata cannot be read or the header is missing.
# Usage: read_field <archive> <Header-Name>
read_field() {
	local metadata value
	metadata="$(read_metadata "$1")" || return 1
	value="$(metadata_values "${metadata}" "$2" | sed -n 1p)"
	[ -n "${value}" ] || return 1
	echo "${value}"
}

# Print the version of the archive, fail if it cannot be read.
read_version() {
	read_field "$1" Version
}

# Verify an archive. Prints one error line per failed check, returns 1 if any.
check_dist() {
	local archive="$1"
	local package_name="$2"
	local module_name="${3:-}"
	local extras="${4:-}"
	local check_types="${5:-true}"
	local failures=0
	local metadata name version extra
	local declared

	[ -n "${module_name}" ] || module_name="$(default_module_name "${package_name}")"

	if [ ! -f "${archive}" ]; then
		log_error "archive not found: ${archive}"
		return 1
	fi
	case "${archive}" in
	*.whl | *.tar.gz) ;;
	*)
		log_error "unsupported archive type (expected .whl or .tar.gz, got ${archive})"
		return 1
		;;
	esac

	if ! metadata="$(read_metadata "${archive}")"; then
		log_error "core metadata file not found in ${archive} (expected *.dist-info/METADATA or PKG-INFO)"
		return 1
	fi

	name="$(metadata_values "${metadata}" "Name" | sed -n 1p)"
	if [ "$(normalize_name "${name}")" != "$(normalize_name "${package_name}")" ]; then
		log_error "wrong package name in ${archive} (expected ${package_name}, got ${name:-<none>})"
		failures=$((failures + 1))
	fi

	version="$(metadata_values "${metadata}" "Version" | sed -n 1p)"
	if [ -z "${version}" ] || [ "${version}" = "0.0.0" ]; then
		log_error "invalid version in ${archive} (expected a real version, got ${version:-<none>})"
		failures=$((failures + 1))
	fi

	declared="$(metadata_values "${metadata}" "Provides-Extra" | while IFS= read -r extra; do
		normalize_name "${extra}"
		echo
	done)"
	while IFS= read -r extra; do
		[ -n "${extra}" ] || continue
		if ! grep -Fxq -- "${extra}" <<<"${declared}"; then
			log_error "extra not defined in ${archive} (expected ${extra}, got: $(tr '\n' ' ' <<<"${declared}"))"
			failures=$((failures + 1))
		fi
	done < <(split_csv "${extras}")

	if [ "${check_types}" = "true" ] && [ "${archive}" = "${archive%.whl}.whl" ] && ! has_py_typed "${archive}" "${module_name}"; then
		log_error "py.typed marker missing in ${archive} (expected ${module_name//.//}/py.typed)"
		failures=$((failures + 1))
	fi

	if [ "${failures}" -gt 0 ]; then
		return 1
	fi
	log_ok "${archive##*/}: name ${name}, version ${version}"
}

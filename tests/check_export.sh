#!/usr/bin/env bash

# check_export.sh - Check the files exported by git archive
#
# Description:
#   Checks that the files shipped to the consumers of the action (`git archive`, which applies
#   the export-ignore rules of .gitattributes) are exactly the files the action needs at
#   runtime. `uses: ./` runs the whole checkout, so a file marked export-ignore by mistake
#   would pass the action tests and break the release. When the action starts using a new
#   file, add it to EXPECTED below and un-ignore it in .gitattributes.
#
# Usage:
#   tests/check_export.sh
#   make check-export
#
# Run it from the root of the repository. It checks the files of HEAD (commit the change
# first).
#
# Exit Codes:
#   0 - The exported files are the expected ones
#   1 - The exported files differ from the expected ones

set -euo pipefail

EXPECTED="LICENSE
action.yaml
scripts/
scripts/check_dist.sh
scripts/check_install.sh
scripts/check_types.sh
scripts/lib.sh
scripts/requirements.txt
scripts/verify.sh"

actual="$(git archive --worktree-attributes HEAD | tar t | LC_ALL=C sort)"
expected="$(printf '%s\n' "$EXPECTED" | LC_ALL=C sort)"

if [ "$actual" != "$expected" ]; then
	echo "❌ The exported files differ from the files the action needs (see tests/check_export.sh)" >&2
	diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
	exit 1
fi
echo "✅ The exported files are the expected ones:"
printf '%s\n' "$actual"

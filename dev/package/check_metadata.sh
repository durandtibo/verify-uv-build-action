#!/usr/bin/env bash

set -euo pipefail

METADATA=$(uv pip show myproject)

echo "$METADATA"

echo "$METADATA" | grep -q "Name: myproject"
echo "$METADATA" | grep -q "Requires: coola"

#!/usr/bin/env bash

# check_type.sh - Validate package type hints
#
# Description:
#   Verifies that the package includes proper type hints by running pyright
#   on a simple import test. This ensures the package is properly typed and
#   the py.typed marker is working correctly.
#
# Usage:
#   ./check_type.sh
#
# Requirements:
#   - pyright must be installed
#   - Package must be installed in the current environment
#   - Package must include py.typed marker file
#
# Exit Codes:
#   0 - Type hints validation passed
#   1 - Type hints validation failed

set -euo pipefail

PYRIGHT_DIR=tmp/pyright_check
mkdir -p $PYRIGHT_DIR

# Ensure cleanup on exit, even on error
cleanup() {
  rm -rf "$PYRIGHT_DIR"
}
trap cleanup EXIT

# Create pyright test file
cat >$PYRIGHT_DIR/check_pyright_import.py <<'EOF'
import myproject

myproject.__version__
EOF

# Check that pyright recognizes the package as typed
pyright $PYRIGHT_DIR

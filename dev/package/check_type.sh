#!/usr/bin/env bash

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

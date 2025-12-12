# verify-uv-build-action

[![CI](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml)
[![Nightly Tests](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/nightly-tests.yaml/badge.svg)](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/nightly-tests.yaml)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://github.com/durandtibo/verify-uv-build-action/blob/main/LICENSE)

A GitHub Action to build Python packages with [uv](https://github.com/astral-sh/uv)
and comprehensively verify their quality, metadata, and installability.

## Features

- 🚀 **Fast builds** with uv package manager
- 📦 **Dual format support** - test both wheel and sdist distributions
- ✅ **Type checking** - verify py.typed markers and type hints with pyright
- 🔍 **Metadata validation** - check package metadata with twine
- 🌲 **Dependency verification** - validate dependency tree structure
- 📚 **Import testing** - ensure package is importable and has valid version
- 🎯 **Custom checks** - run project-specific validation scripts
- 🔧 **Flexible** - optional scripts for project-specific needs

## Usage

### Basic Example

```yaml
name: Build and Verify

on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: durandtibo/verify-uv-build-action@v0.0.3
        with:
          package-name: mypackage
```

### Advanced Example with Matrix

```yaml
name: Build and Verify

on: [push, pull_request]

jobs:
  verify:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        dist-type: [wheel, sdist]
        python-version: ["3.10", "3.11", "3.12", "3.13"]
    steps:
      - uses: actions/checkout@v6
      - uses: durandtibo/verify-uv-build-action@v0.0.3
        with:
          package-name: mypackage
          dist-type: ${{ matrix.dist-type }}
          python-version: ${{ matrix.python-version }}
          package-extra: all
```

## Inputs

| Input            | Required | Default | Description                                            |
| ---------------- | -------- | ------- | ------------------------------------------------------ |
| `package-name`   | Yes      | -       | The name of the package to verify                      |
| `package-extra`  | No       | `""`    | Optional package extras to install (e.g., `dev, test`) |
| `dist-type`      | No       | `wheel` | Distribution type to test: `wheel` or `sdist`          |
| `python-version` | No       | `3.13`  | Python version to use for testing                      |

## What Does This Action Do?

This action performs a comprehensive verification of your Python package build:

1. **Build Validation**: Builds the package using `uv build`
2. **Type Marker Check**: Verifies `py.typed` marker exists (for typed packages)
3. **Package Installation**: Installs the built distribution
4. **Metadata Validation**: Runs `twine check` on distributions
5. **Import Test**: Verifies the package can be imported
6. **Version Check**: Ensures version is not the placeholder "0.0.0"
7. **Type Hints Check**: Validates type hints with pyright (if configured)
8. **Custom Checks**: Runs project-specific validation scripts (if provided)

## Optional Custom Checks

The action supports optional project-specific validation scripts in the
`dev/package/` directory. These scripts are automatically detected and run if
present:

### `dev/package/check_metadata.sh`

Validate package metadata beyond what twine checks. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

METADATA=$(uv pip show mypackage)
echo "$METADATA" | grep -q "Name: mypackage"
echo "$METADATA" | grep -q "Requires: dependency-name"
```

### `dev/package/check_dependency_tree.sh`

Verify the dependency tree structure matches expectations. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

OUTPUT=$(uv pip tree --package mypackage --show-version-specifiers)
echo "$OUTPUT"

# Validate dependency structure
echo "$OUTPUT" | grep -q "mypackage"
echo "$OUTPUT" | grep -q "└── dependency"
```

### `dev/package/check_type.sh`

Validate type hints with pyright. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

PYRIGHT_DIR=tmp/pyright_check
mkdir -p $PYRIGHT_DIR

trap "rm -rf $PYRIGHT_DIR" EXIT

cat >$PYRIGHT_DIR/check_import.py <<EOF
import mypackage
mypackage.__version__
EOF

pyright $PYRIGHT_DIR
```

### `dev/package/custom_checks.sh`

Run any additional project-specific checks. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

python tests/custom_package_checks.py
```

All scripts should:

- Be executable (`chmod +x script.sh`)
- Use proper error handling (`set -euo pipefail`)
- Exit with non-zero status on failure
- Print clear error messages

## Requirements

- Your project must have a `pyproject.toml` compatible with uv
- For type checking: include a `py.typed` marker file in your package
- Optional scripts should be in `dev/package/` directory

## Troubleshooting

### "Error: input 'dist-type' must be 'wheel' or 'sdist'"

Ensure the `dist-type` input is exactly `wheel` or `sdist` (case-sensitive).

### "py.typed not found"

Add a `py.typed` file to your package source directory (e.g., `src/mypackage/py.typed`)
if your package includes type hints.

### Custom script not running

Verify:

- Script exists in `dev/package/` directory
- Script is executable (`chmod +x script.sh`)
- Script name matches exactly (e.g., `check_metadata.sh`)

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines.

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the BSD 3-Clause License - see the
[LICENSE](LICENSE) file for details.

## Acknowledgments

Built with [uv](https://github.com/astral-sh/uv) by Astral.

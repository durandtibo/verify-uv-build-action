# verify-uv-build-action

[![CI](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://github.com/durandtibo/verify-uv-build-action/blob/main/LICENSE)

A GitHub Action that builds a Python project with [uv](https://github.com/astral-sh/uv) and
verifies that the **published artifacts** (the wheel and the sdist) are correct and usable. It
checks the built files and a clean install, never the source tree.

## What is verified

| Check                                                               | Wheel | Sdist | Install |
| ------------------------------------------------------------------- | :---: | :---: | :-----: |
| Exactly one wheel and one sdist are built (`uv build --no-sources`) |  ✅   |  ✅   |         |
| Distribution name matches `package-name` (normalized)               |  ✅   |  ✅   |   ✅    |
| Version is not the placeholder `0.0.0`                              |  ✅   |  ✅   |   ✅    |
| Installed version equals the built wheel version                    |       |       |   ✅    |
| Every `package-extra` is in `Provides-Extra`                        |  ✅   |  ✅   |         |
| `<module>/py.typed` is present in the wheel (if `check-types`)      |  ✅   |       |         |
| `twine check --strict`                                              |  ✅   |  ✅   |         |
| Every `package-dependencies` entry is installed                     |       |       |   ✅    |
| The module imports from `site-packages`, run outside the checkout   |       |       |   ✅    |
| Type completeness with `pyright --verifytypes` (if `check-types`)   |       |       |   ✅    |

Checks run in a fail-fast order: input validation, archive checks (milliseconds), install, then
checks that need an environment. A check that cannot run is a failure, never a skip. Artifacts and
the virtual environment live in `$RUNNER_TEMP`: the workspace is not modified and no environment
variable is exported to later steps. Only Linux and macOS runners are supported.

## Quick start

```yaml
name: Verify build

on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: durandtibo/verify-uv-build-action@v0.1.0
        with:
          package-name: mypackage
```

Releases are immutable exact version tags. There are no floating tags such as `v0` or `latest`.
For a stronger guarantee, pin the commit SHA of the release:
`durandtibo/verify-uv-build-action@<sha> # v0.1.0`.

### Matrix example

```yaml
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
      - uses: durandtibo/verify-uv-build-action@v0.1.0
        with:
          package-name: mypackage
          dist-type: ${{ matrix.dist-type }}
          python-version: ${{ matrix.python-version }}
          package-extra: all
          package-dependencies: numpy
```

### Monorepo example

```yaml
- uses: durandtibo/verify-uv-build-action@v0.1.0
  with:
    package-name: subpackage
    project-path: packages/subpackage
```

### Use the outputs

```yaml
- id: verify
  uses: durandtibo/verify-uv-build-action@v0.1.0
  with:
    package-name: mypackage
- run: echo "Built ${{ steps.verify.outputs.version }} at ${{ steps.verify.outputs.wheel-path }}"
```

## Inputs

| Input                  | Required | Default   | Description                                                                                    |
| ---------------------- | -------- | --------- | ---------------------------------------------------------------------------------------------- |
| `package-name`         | Yes      | -         | The name of the package to verify (distribution name on PyPI)                                  |
| `module-name`          | No       | `""`      | The name used in import statements (defaults to package-name with `-` and `.` replaced by `_`) |
| `package-extra`        | No       | `""`      | Extras to install and verify, comma-separated (e.g., `dev,test`)                               |
| `package-dependencies` | No       | `""`      | Comma-separated direct dependencies that must be installed                                     |
| `dist-type`            | No       | `wheel`   | Artifact that is installed and tested: `wheel` or `sdist`. Both are always built and inspected |
| `python-version`       | No       | `3.13`    | Python version to use for testing                                                              |
| `project-path`         | No       | `.`       | Directory containing `pyproject.toml` (monorepos)                                              |
| `twine-version`        | No       | `7.0.0`   | Version of twine used by `twine check`                                                         |
| `pyright-version`      | No       | `1.1.414` | Version of pyright used by `pyright --verifytypes`                                             |
| `check-types`          | No       | `true`    | Check the `py.typed` marker and type completeness. Set `false` for untyped packages            |

## Outputs

| Output       | Description                           |
| ------------ | ------------------------------------- |
| `wheel-path` | Absolute path of the built wheel      |
| `sdist-path` | Absolute path of the built sdist      |
| `version`    | Version from the built wheel metadata |

## Requirements

- A `pyproject.toml` compatible with `uv build`. The build uses `--no-sources`: it ignores
  `[tool.uv.sources]`, so the project must build the way a user installing from PyPI gets it.
- For type checking: a `<module>/py.typed` marker in the package, or `check-types: false`.

## Troubleshooting

Each failure prints one `❌` line that says what was expected and what was found. Details are in
the collapsed log groups.

| Message starts with                       | Cause and fix                                                                         |
| ----------------------------------------- | ------------------------------------------------------------------------------------- |
| `Input 'dist-type' must be`               | Use exactly `wheel` or `sdist`.                                                       |
| `Input 'check-types' must be`             | Use exactly `true` or `false`.                                                        |
| `No pyproject.toml found in project-path` | Fix `project-path`, it must contain `pyproject.toml`.                                 |
| `Input 'package-name' is not a valid`     | Use the distribution name, for example `my-package`.                                  |
| `Expected exactly 1 wheel` / `1 sdist`    | The build produced no artifact or several. Check the build backend configuration.     |
| `wrong package name`                      | `package-name` differs from the `Name` in the metadata (compared in normalized form). |
| `invalid version`                         | The metadata version is missing or `0.0.0`. Fix the version source of the build.      |
| `extra not defined`                       | A requested `package-extra` is not in `Provides-Extra`. Fix the extra or the input.   |
| `py.typed marker missing`                 | Add `<module>/py.typed` to the package, or set `check-types: false`.                  |
| `core metadata file not found`            | The archive has no `METADATA` or `PKG-INFO`. It is invalid for PyPI.                  |
| `twine check failed`                      | Fix the metadata warnings (for example a missing `readme`).                           |
| `dependency not installed`                | A `package-dependencies` entry is not in the installed `Requires`.                    |
| `cannot import`                           | The installed package does not import. Check the packaged files.                      |
| `not imported from site-packages`         | The module was imported from somewhere else than the installed package.               |
| `type completeness check failed`          | Fix the type annotations reported by pyright, or set `check-types: false`.            |

## Migration from 0.0.x

`v0.1.0` has breaking changes.

| Change                                                                      | Migration                                                   |
| --------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `verify-wheel-extra` and `verify-sdist-extra` are removed                   | Delete them. Remove the extra from `package-extra` instead. |
| `module.__version__` is no longer required; the metadata version is checked | None.                                                       |
| twine and pyright failures fail the job; they were silently skipped before  | Fix the cause, or set `check-types: false` for pyright.     |
| `dist/` is no longer used or written in the workspace                       | Use the `wheel-path` and `sdist-path` outputs.              |
| `WHEEL_PATH`, `SDIST_PATH` and `MODULE_NAME` are no longer exported         | Use the outputs.                                            |
| `.venv` is no longer created in the workspace                               | Create your own environment.                                |
| Names are compared in normalized form; the `uv pip tree` check is removed   | None.                                                       |
| `py.typed` must be at `<module>/py.typed`, not anywhere in the archive      | Move the marker into the package.                           |
| The build uses `uv build --no-sources`                                      | Make the build work without `[tool.uv.sources]`.            |
| `twine check --strict`                                                      | Fix the metadata warnings.                                  |

## Run the checks locally

The scripts work on a wheel or an sdist you built yourself:

```bash
uv build --out-dir /tmp/dist
bash scripts/check_dist.sh /tmp/dist/mypackage-1.0-py3-none-any.whl mypackage mypackage "all" true
bash scripts/check_dist.sh /tmp/dist/mypackage-1.0.tar.gz mypackage mypackage "all" true
```

`check_install.sh` and `check_types.sh` need the package installed in the active environment, and
must run outside the checkout. See the header comment of each script.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines.

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the BSD 3-Clause License - see the
[LICENSE](LICENSE) file for details.

# verify-uv-build-action

[![CI](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/durandtibo/verify-uv-build-action/actions/workflows/ci.yaml)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://github.com/durandtibo/verify-uv-build-action/blob/main/LICENSE)

A GitHub Action that builds a Python project with [uv](https://github.com/astral-sh/uv) and
verifies that the **published artifacts** (the wheel and the sdist) are correct and usable. It
checks the built files and a clean install, never the source tree.

## What is verified

| Check                                                                           | Wheel | Sdist | Install |
| ------------------------------------------------------------------------------- | :---: | :---: | :-----: |
| Exactly one wheel and one sdist are built (`uv build --no-config --no-sources`) |  ✅   |  ✅   |         |
| Distribution name matches `package-name` (normalized)                           |  ✅   |  ✅   |   ✅    |
| Version is not the placeholder `0.0.0`                                          |  ✅   |  ✅   |   ✅    |
| Installed version equals the built wheel version                                |       |       |   ✅    |
| Every `package-extra` is in `Provides-Extra`                                    |  ✅   |  ✅   |         |
| `<module>/py.typed` is present in the wheel (if `check-types`)                  |  ✅   |       |         |
| Wheel and sdist have the same version                                           |  ✅   |  ✅   |         |
| `twine check --strict`                                                          |  ✅   |  ✅   |         |
| Every `package-dependencies` entry is installed                                 |       |       |   ✅    |
| The module imports from `site-packages`, run outside the checkout               |       |       |   ✅    |
| Type completeness with `pyright --verifytypes` (if `check-types`)               |       |       |   ✅    |

Checks run in a fail-fast order: input validation, archive checks (milliseconds), install, then
checks that need an environment. By default (`dist-type: both`) the wheel and the sdist are each
installed in their own environment; the build and the install pass `--no-config`, so the project's
`[tool.uv]` and `uv.toml` are not read (set `UV_INDEX_URL` or another `UV_*` variable in the job
environment if the install needs a custom index). A check that cannot run is a failure, never a
skip. Artifacts and the virtual environments live in `$RUNNER_TEMP`: the workspace is not modified
and no environment variable is exported to later steps. Only Linux and macOS runners are supported.

## Phases

`scripts/verify.sh` runs six phases, each in a collapsed log group, and stops at the first phase
that fails. Every failure of a phase is reported before it stops.

| #   | Phase          | What it does                                                                                |
| --- | -------------- | ------------------------------------------------------------------------------------------- |
| 1   | Validate       | Checks every input (exit 2 with all errors).                                                |
| 2   | Build          | `uv build --no-config --no-sources` into a new directory, one wheel and one sdist expected. |
| 3   | Check archives | Metadata of both archives, same version, `twine check --strict`.                            |
| 4   | Install        | Installs the wheel and/or the sdist (`dist-type`) in a venv outside the workspace.          |
| 5   | Check install  | Name, version, dependencies and import of each installed artifact.                          |
| 6   | Check types    | `pyright --verifytypes` on the first installed artifact (if `check-types`).                 |

The job summary states the verdict, the failed phase and the reason, a table of the phases and the
content of the archives, also when a check failed. The outputs are written right after the build.

## Quick start

```yaml
name: Verify build

on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # only needed when the version comes from VCS tags
      - uses: durandtibo/verify-uv-build-action@v0.1.0
        with:
          package-name: mypackage
```

Projects that derive the version from VCS tags (`hatch-vcs`, `setuptools-scm`) need
`fetch-depth: 0`: with the default shallow checkout they build a development version. Only the
`0.0.0` placeholder is detected as an invalid version.

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
        python-version: ["3.10", "3.11", "3.12", "3.13"]
    steps:
      - uses: actions/checkout@v7
      - uses: durandtibo/verify-uv-build-action@v0.1.0
        with:
          package-name: mypackage
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
| `dist-type`            | No       | `both`    | Artifact that is installed and tested: `wheel`, `sdist` or `both`. Both are always built       |
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

- A `pyproject.toml` compatible with `uv build`. The build uses `--no-config --no-sources`: it ignores
  `[tool.uv]`, `uv.toml` and `[tool.uv.sources]`, so the project must build the way a user
  installing from PyPI gets it.
- For type checking: a `<module>/py.typed` marker in the package, or `check-types: false`.

## Troubleshooting

Each failure prints one `❌` line that says what was expected and what was found. Details are in
the collapsed log groups.

| Message starts with                                     | Cause and fix                                                                          |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `Input 'dist-type' must be`                             | Use exactly `wheel`, `sdist` or `both`.                                                |
| `Input 'module-name' must be`                           | Use a dotted Python identifier, for example `my_package.sub`.                          |
| `Input 'twine-version' must be`                         | Use `latest` or a version such as `7.0.0` (same for `pyright-version`).                |
| `Input 'check-types' must be`                           | Use exactly `true` or `false`.                                                         |
| `No pyproject.toml found in project-path`               | Fix `project-path`, it must contain `pyproject.toml`.                                  |
| `Input 'package-name' is not a valid`                   | Use the distribution name, for example `my-package`.                                   |
| `uv build failed`                                       | The build failed, see the output of `uv build` above the message.                      |
| `Expected exactly 1 wheel` / `1 sdist`                  | The build produced no artifact or several. Check the build backend configuration.      |
| `wrong package name`                                    | `package-name` differs from the `Name` in the metadata (compared in normalized form).  |
| `wheel and sdist have different versions`               | Fix the version source so that both artifacts report the same version.                 |
| `invalid version`                                       | The metadata version is missing or `0.0.0`. Fix the version source of the build.       |
| `extra not defined`                                     | A requested `package-extra` is not in `Provides-Extra`. Fix the extra or the input.    |
| `py.typed marker missing`                               | Add `<module>/py.typed` to the package, or set `check-types: false`.                   |
| `core metadata file not found`                          | The archive has no `METADATA` or `PKG-INFO`. It is invalid for PyPI.                   |
| `twine check failed`                                    | Fix the metadata warnings (for example a missing `readme`).                            |
| `Installation of the`                                   | The artifact does not install. Check its dependencies, or set a `UV_*` index variable. |
| `package not installed`                                 | The install succeeded but the package is not in the environment. Check `package-name`. |
| `wrong installed package name`                          | The installed name differs from `package-name`.                                        |
| `wrong installed version` / `invalid installed version` | The installed version differs from the built wheel, or is invalid.                     |
| `dependency not installed`                              | A `package-dependencies` entry is not in the installed `Requires`.                     |
| `cannot import`                                         | The installed package does not import. Check the packaged files.                       |
| `not imported from site-packages`                       | The module was imported from somewhere else than the installed package.                |
| `type completeness check failed`                        | Fix the type annotations reported by pyright, or set `check-types: false`.             |

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
| `dist-type` defaults to `both` instead of `wheel`                           | Set `dist-type: wheel` for the old behaviour.               |
| The install ignores the project's `[tool.uv]` and `uv.toml`                 | Set `UV_INDEX_URL` (or another `UV_*` variable).            |
| `module-name`, `twine-version` and `pyright-version` are validated          | Fix a malformed value.                                      |
| Wheel and sdist must have the same version                                  | Fix the version source of the build.                        |
| `py.typed` is checked in the wheel only                                     | None.                                                       |
| The build uses `uv build --no-config --no-sources`                          | Make the build work without `[tool.uv.sources]`.            |
| `twine check --strict`                                                      | Fix the metadata warnings.                                  |

## Run the checks locally

The action runs one script, which you can run on your project the same way:

```bash
PACKAGE_NAME=mypackage bash scripts/verify.sh
```

The inputs are environment variables with the input names in upper case with `_` (`MODULE_NAME`,
`PACKAGE_EXTRA`, `DIST_TYPE`, `PROJECT_PATH`, ...). See the header comment of the script. Files are
written in a new directory under `$TMPDIR`.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines.

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the BSD 3-Clause License - see the
[LICENSE](LICENSE) file for details.

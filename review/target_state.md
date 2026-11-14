# verify-uv-build-action: target state

Status: proposal. Nothing in this document is implemented yet. Breaking changes are accepted.
Basis: review of `action.yaml`, `scripts/*.sh`, `tests/bats/`, `README.md`, `CLAUDE.md` and the
workflows at commit `b54e7c9`.

## 1. Properties of the action

These are the properties the action must have. Every design choice in section 3 is justified
against one of them. They extend the rules already in `CLAUDE.md` and `README.md`.

| #   | Property                | Definition                                                                                                                                                                                              |
| --- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | Purpose                 | Build a Python project with `uv build`, then verify that the **published artifacts** (wheel and sdist) are correct and usable. It checks artifacts, not the source tree.                                 |
| P2  | Faithful                | What is verified is what users get. Checks run on the built files and on a clean install, never on the checkout (no `src/` on `sys.path`, no stale `dist/`, no `.venv` in the repo).                    |
| P3  | Fail loudly             | A check that cannot run is a failure, never a skip. No `2>/dev/null` around installs, no "tool not available, skipping". Opt-outs are explicit inputs.                                                  |
| P4  | Minimal configuration   | Only `package-name` is required. Defaults are right for a standard `uv` project. Every input changes behaviour in a way that cannot be inferred. No input exists to toggle a check that is always cheap. |
| P5  | Fast                    | One build, one install, tools run through `uvx` (cached, isolated). No tool is installed into the environment under test. Cheap archive checks run before the install.                                  |
| P6  | Simple to maintain      | Few steps in `action.yaml`, three scripts plus one shared library, each small and unit tested. No logic duplicated between wheel and sdist.                                                              |
| P7  | Safe                    | Inputs reach scripts only through `env:` and are never interpolated into shell or Python source. Third-party actions are pinned to SHAs. Least-privilege permissions.                                    |
| P8  | Portable                | Works on `ubuntu`, `macos` and `windows` runners with bash (Git Bash on Windows), and on GNU and BSD tools. Scripts also run locally.                                                                    |
| P9  | Non-polluting           | Leaves no state for later steps of the caller's job: no `WHEEL_PATH`-style env vars, no `.venv`, no extra files in the workspace. Results are exposed through step outputs.                              |
| P10 | Actionable diagnostics  | One `❌` line says what failed and what was expected, with the observed value. Details (file listings, metadata) are in collapsed log groups.                                                           |
| P11 | Stable, versioned       | Inputs and outputs are a public API. Releases are immutable exact tags. Breaking changes are announced in the release notes and the README.                                                              |
| P12 | Dogfooded               | The repository's CI runs the unreleased action on a Python/OS matrix and checks that each failure mode really fails. The nightly run exercises the latest release.                                      |

## 2. Review of the current state

### 2.1 What is good and stays

- Composite action, no Docker, no Node: nothing to compile or release but the YAML.
- `uv build` builds the sdist first and then the wheel from that sdist. This already validates that
  the sdist is complete.
- Inputs go through `env:`. Helper scripts are called through `$GITHUB_ACTION_PATH`. Third-party
  actions are pinned.
- Scripts are sourceable and tested with bats. CI covers a Python/OS matrix and failure cases.
- Workflow layout (`ci-*`, `lib-*`, `bot-*`, `security-*`) is clear and follows the documented rules.

### 2.2 Problems

Severity: **H** = a check can pass when it should fail (or the reverse), **M** = fragile or
misleading, **L** = maintenance cost.

| ID  | Sev | Problem                                                                                                                                                                                                                                                                  | Where                                       |
| --- | --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| F1  | H   | Import, version and pyright checks run from the checkout directory. `python -c` puts the cwd on `sys.path`, so with a flat layout the **source tree** is imported and the test passes even if the wheel is broken (violates P2).                                          | `action.yaml` "Verify package import"       |
| F2  | H   | `uv build` writes to `./dist`. Stale artifacts from a previous build stay there, and `wheels[0]` / `sdists[0]` picks the first one alphabetically, which may be an old version. `twine check dist/*` also checks the stale files.                                          | "Find distribution paths", "twine"          |
| F3  | H   | `twine` and `pyright` are skipped with a warning if `uv pip install` fails (the error is discarded with `2>/dev/null`). A network blip silently turns the checks off (violates P3).                                                                                       | "Install and run twine check", "type hints" |
| F4  | H   | The version check requires `module.__version__`. Many valid packages do not define it (they use `importlib.metadata` only), so they fail for a reason unrelated to packaging. The `0.0.0` check belongs on the metadata version, which is what is published.            | "Verify package import and version"         |
| F5  | M   | `py.typed` is matched with `grep 'py\.typed$'` anywhere in the archive (tests, vendored packages, docs). It must be `<module path>/py.typed`.                                                                                                                              | two `py.typed` steps                        |
| F6  | M   | `$MODULE_NAME` is interpolated into Python source (`python -c "import $MODULE_NAME; ..."`). It comes from an input (violates P7). It should be passed as `argv`/env.                                                                                                       | same step                                   |
| F7  | M   | `activate-environment: true` creates `.venv` in the workspace, and `WHEEL_PATH`, `SDIST_PATH`, `MODULE_NAME` are written to `$GITHUB_ENV`, visible to all later steps of the caller (violates P9).                                                                          | `action.yaml`                               |
| F8  | M   | Name comparison is inconsistent. `check_metadata.sh` normalizes the package name (PEP 503) but not the dependency names. `check_dependency_tree.sh` normalizes neither: `package-name: my_pkg` fails against `my-pkg v1.0`, and the version regex rejects `1.0+local`, `1.0.post1.dev2`. | `check_*.sh`                                |
| F9  | M   | `check_metadata.sh` and `check_dependency_tree.sh` both verify that direct dependencies are installed. Two scripts, two `uv` calls, two regexes, two error formats, one property.                                                                                          | `scripts/`                                  |
| F10 | M   | `verify_*_extras.sh`: `grep -q "^${extra}$"` uses the extra as a regex; `grep -c '^' \|\| echo 0` double-prints; extra names are case-sensitive although PEP 685 normalizes them (`Foo_Bar` = `foo-bar`); usage exits `1` while the other scripts use `2`.                |                                             |
| F11 | M   | An sdist already contains `PKG-INFO` with `Provides-Extra:` (core metadata). `verify_sdist_extras.sh` (433 lines) re-implements a TOML and `setup.cfg` parser in awk instead. It cannot handle `dynamic` extras or a build backend that generates them.                   | `verify_sdist_extras.sh`                    |
| F12 | L   | `verify_wheel_extras.sh` and `verify_sdist_extras.sh` duplicate `usage`, `parse_requested_extras`, `display_extras`, `verify_extras`, colour codes (737 lines, 1189 lines of tests). Raw ANSI codes are printed in CI logs. `verify_wheel` uses `#!/bin/bash`.              |                                             |
| F13 | L   | `verify-wheel-extra` and `verify-sdist-extra` are toggles for checks that cost milliseconds and that no valid project needs to disable. They exist for one reason: a test (`incorrect-extra-skip`). When `package-extra` is empty there is nothing to verify anyway.     | `action.yaml`, README                       |
| F14 | L   | The README is out of date: the feature list promises "optional scripts for project-specific needs" (no such input), the steps list omits the extras, dependency and tree checks, and the examples use `@v0.0.7` while `CLAUDE.md` documents releases like `v1.9`.          | `README.md`                                 |
| F15 | L   | `tests/package_checks.py` is not run by anything and is not an input of the action. It is dead code, referenced only by `CLAUDE.md`.                                                                                                                                      | `tests/package_checks.py`                   |
| F16 | L   | `ci-action.yaml` repeats a 25-line block four times for the "must fail" cases. Adding a failure case means copy-paste.                                                                                                                                                    | `ci-action.yaml`                            |
| F17 | L   | No way to build a project that is not at the repository root (monorepo). No outputs. The `dist-type` matrix is the only way to test both artifacts, and it rebuilds each time.                                                                                           | `action.yaml`                               |
| F18 | L   | 14 steps, most of them 5 to 10 lines of shell. Each repeats `set -euo pipefail` and its own banners. The flow is hard to read.                                                                                                                                           | `action.yaml`                               |

## 3. Target state

### 3.1 Inputs (public API, v1)

| Input               | Required | Default | Change vs current                                                                                                                                         |
| ------------------- | -------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package-name`      | yes      | -       | Unchanged. Compared in PEP 503 normalized form everywhere.                                                                                                |
| `module-name`       | no       | derived | Unchanged semantics: default is `package-name` with `-` and `.` replaced by `_`. Dots in a given module name mean a sub-package (`a.b` -> `a/b/py.typed`). |
| `package-extra`     | no       | `""`    | Unchanged. Comma-separated list is accepted (`a,b`), each name normalized (PEP 685).                                                                      |
| `package-dependencies` | no    | `""`    | Unchanged. Comma-separated direct dependencies that must be installed. Normalized names.                                                                  |
| `dist-type`         | no       | `wheel` | Unchanged. Selects the artifact that is **installed** and tested. Both artifacts are always built and inspected.                                          |
| `python-version`    | no       | `3.13`  | Unchanged.                                                                                                                                                |
| `project-path`      | no       | `.`     | **New.** Directory containing `pyproject.toml` (monorepos). Passed to `uv build`. Fixes F17.                                                              |
| `check-types`       | no       | `true`  | **New.** Runs the `py.typed` marker check and `pyright --verifytypes`. Set `false` for projects that are intentionally untyped. Replaces mandatory typing. |

Removed: `verify-wheel-extra`, `verify-sdist-extra` (F13). Extras are always verified, in both
artifacts, when `package-extra` is set. Nothing to verify when it is empty.

Rationale for `check-types`: today an untyped package cannot use the action at all, because the
`py.typed` check cannot be disabled. One boolean fixes that. It is the only quality gate that is
legitimately optional.

### 3.2 Outputs (new, P9)

| Output       | Content                                                    |
| ------------ | ---------------------------------------------------------- |
| `wheel-path` | Absolute path of the built wheel.                          |
| `sdist-path` | Absolute path of the built sdist.                          |
| `version`    | Version from the built wheel metadata (e.g. for a release job). |

### 3.3 Pipeline

Seven steps instead of fourteen. Every step starts with `set -euo pipefail` and passes inputs
through `env:`. Artifacts go to `$RUNNER_TEMP/verify-uv-build/{dist,venv}` so the workspace stays
clean (P9) and stale files cannot exist (F2).

| #   | Step              | What it does                                                                                                                                                                                                                      | Fails when                                                          |
| --- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| 1   | Validate inputs   | `dist-type` in `{wheel, sdist}`, `check-types` in `{true, false}`, `project-path/pyproject.toml` exists, `package-name` is a valid distribution name.                                                                              | any invalid input                                                   |
| 2   | Set up uv         | `astral-sh/setup-uv` with `python-version`, **without** `activate-environment`. Cache on.                                                                                                                                          | setup failure                                                       |
| 3   | Build             | `uv build "$PROJECT_PATH" --out-dir "$RUNNER_TEMP/.../dist"` into a fresh directory. Exactly one wheel and one sdist must exist. Sets outputs.                                                                                      | build error, 0 or >1 wheel/sdist                                    |
| 4   | Check artifacts   | `check_dist.sh`, on **both** archives, before any install: name matches `package-name`, version is not `0.0.0`, `<module>/py.typed` present (if `check-types`), every requested extra is in `Provides-Extra`, `uvx twine check --strict`. | any mismatch (each reported)                                        |
| 5   | Install           | `uv venv` in `$RUNNER_TEMP`, then `uv pip install "<selected artifact>[extras]"` with `VIRTUAL_ENV` exported for the following steps of the action only (set in each step's `env:`, not `$GITHUB_ENV`).                            | install error                                                       |
| 6   | Check install     | `check_install.sh`, run from `$RUNNER_TEMP` (F1): distribution is installed, normalized name and version match the wheel metadata, each `package-dependencies` entry is in the installed `Requires`, module imports and file comes from `site-packages`. | not installed, missing dependency, import error, import from source |
| 7   | Check types       | Only if `check-types`: `uvx pyright --pythonpath "$VIRTUAL_ENV/bin/python" --verifytypes "$MODULE" --ignoreexternal`, run from `$RUNNER_TEMP`. Not installed into the venv.                                                       | type completeness errors, pyright cannot run (P3)                   |
| +   | Show artifacts    | `if: always()`. Collapsed `::group::` listing of the wheel and sdist contents.                                                                                                                                                    | never                                                               |

Order is fail-fast: input errors, then cheap archive checks (milliseconds), then install, then
checks that need an environment. The dependency tree script disappears (see 3.4).

Behaviour decisions:

- **Version check uses metadata, not `__version__`** (F4). `0.0.0` is rejected from the wheel
  `METADATA`. The module is only required to import.
- **Isolation** (F1). Steps 6 and 7 run with `working-directory: $RUNNER_TEMP`, and step 6 asserts
  `module.__file__` lies under the venv. A flat-layout project that accidentally imports itself
  from the checkout now fails.
- **No silent skip** (F3). `twine` and `pyright` run through `uvx`. A network failure is a failure.
- **Tool versions**: unpinned (latest) for `twine` and `pyright`. This tool exists to catch
  problems with current ecosystem rules, and `uvx` caches them. Trade-off: an upstream release can
  turn CI red. Mitigation: the nightly run on `main` surfaces it before users do. If this proves
  noisy, pin both in one `env:` block at the top of `action.yaml`.
- **`--no-sources`**: not used by default. Documented as the next candidate, because it checks that
  the build does not depend on `[tool.uv.sources]`, but it breaks legitimate setups. Decision in
  section 6.

### 3.4 Scripts

Three entry points and one library, in bash, GNU/BSD portable, shellcheck and shfmt clean.
Sourceable (main guarded by `BASH_SOURCE`), one test file each (`CLAUDE.md` rules).

| Script                | Replaces                                                                   | Responsibility                                                                                                                                                                                              |
| --------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/lib.sh`      | duplicated helpers in all 5 scripts                                        | `log_ok`, `log_error` (writes `❌ ...` to stderr), `die`, `normalize_name` (PEP 503/685, via `tr`), `split_csv` (trim, drop empties, normalize), `group_start`/`group_end`. No ANSI colour codes (P10).             |
| `scripts/check_dist.sh` `<archive> <package-name> <module-name> <extras> <check-types>` | `verify_wheel_extras.sh`, `verify_sdist_extras.sh`, both `py.typed` steps | Works on one archive of either kind. Reads the core metadata file (`*.dist-info/METADATA` in a wheel, root `PKG-INFO` in an sdist) with `unzip -p` / `tar -xzOf`, then checks name, version, `Provides-Extra`, and the `py.typed` path. No temp files. |
| `scripts/check_install.sh` `<package-name> <module-name> <dependencies>` | `check_metadata.sh`, `check_dependency_tree.sh`, the inline import step     | One `uv pip show` call. Checks name, version, `Requires`, then imports the module with `python -c 'import importlib,sys; ...' "$MODULE"` (module passed as `argv`, F6) and prints its file.                  |
| `scripts/check_types.sh` `<module-name>` | `check_type.sh` (renamed for consistent plural, same job)                  | `uvx pyright --verifytypes`, with the interpreter of the active environment.                                                                                                                              |

Common contract (P10): exit `0` ok, `1` a check failed, `2` bad usage. Each failure prints a single
`❌ <what> (expected <x>, got <y>)` line. Multiple failures in one run are all reported before the
exit (collect, then exit), so one CI run shows everything to fix.

Why PKG-INFO for sdists (F11): it is the standard, backend-independent record of the extras that
will end up in the published sdist. It removes about 300 lines of TOML and `setup.cfg` parsing,
and it supports `dynamic` extras. The limitation is sdists without a `PKG-INFO` (very old
backends). In that case the script fails with a clear message, because such an sdist is invalid
for PyPI anyway.

Estimated size: about 350 lines of scripts (from 1000), about 700 lines of tests (from 2100).

### 3.5 `action.yaml` skeleton

```yaml
name: "Verify uv build"
description: "Build a Python package with uv and verify the wheel and sdist."
author: "Thibaut Durand"
branding: { icon: "check-circle", color: "blue" }

inputs:        # section 3.1
outputs:       # section 3.2

runs:
  using: composite
  steps:
    - name: Validate inputs        # step 1, env: inputs, no interpolation in run:
    - name: Set up uv              # step 2, pinned SHA with ratchet comment
    - name: Build                  # step 3, writes outputs to $GITHUB_OUTPUT
    - name: Check artifacts        # step 4, "$GITHUB_ACTION_PATH/scripts/check_dist.sh" x2
    - name: Install                # step 5
    - name: Check install          # step 6, working-directory: ${{ runner.temp }}
    - name: Check types            # step 7, if: inputs.check-types == 'true'
    - name: Show artifacts         # if: always()
```

All steps set `shell: bash`. A single `env:` mapping of `inputs.*` is repeated per step only where
it is used. The path of the build directory is derived from `runner.temp` in each step's `env:`
rather than exported.

### 3.6 Tests

Bats (unit, per script, small throwaway archives built in a temp dir, no network):

- `test_lib.bats`: `normalize_name` (`Foo_Bar.baz` -> `foo-bar-baz`), `split_csv` (spaces, empty
  items, trailing comma, empty string).
- `test_check_dist.bats`: wheel and sdist for each of: ok; wrong name; version `0.0.0`; missing
  extra; extra with different case/separator (passes); empty extras list; `py.typed` present;
  `py.typed` only in an unrelated directory (fails, regression for F5); `check-types=false` skips
  the marker; missing file; wrong extension; sdist without `PKG-INFO`.
- `test_check_install.bats`: `uv` mocked with a fake `uv` and `python` on `PATH`. Cases: ok;
  name with `_` vs `-` (regression F8); version `1.0+local` (regression F8); missing dependency;
  dependency with `_`/`-` mismatch; module imported from outside site-packages (regression F1);
  import error.
- `test_check_types.bats`: `uvx` mocked. Success; pyright failure; missing argument -> exit 2.

Integration (`ci-action.yaml`, the existing `uses: ./` approach, P12):

- `test`: Python x OS matrix, baseline (unchanged).
- `test-extra`: dist-type x every extra from `pyproject.toml` (unchanged).
- `test-failures`: **one** matrix job replaces the four copy-pasted jobs (F16). Each entry has a
  `name`, a `setup` shell snippet that breaks the fixture, and `with` inputs. A shared step runs the
  action with `continue-on-error` and asserts `outcome == 'failure'`. Cases: invalid `dist-type`,
  missing `py.typed`, unknown extra, missing dependency in `package-dependencies`, wrong
  `package-name`, stale `dist/` directory present in the checkout (must be ignored and must pass:
  regression F2), flat layout importing from source (must fail: regression F1).
- `test-no-types`: `check-types: false` with `py.typed` removed must pass.
- `test-project-path`: the fixture copied to `sub/dir`, built with `project-path`.

Fixture: keep `src/myproject/`, `pyproject.toml`. Delete `tests/package_checks.py` and
`tests/__init__.py` (F15). Fix the formatting of `module.py` (it is not covered by the repo's own
formatters, but it is the fixture). Update `CLAUDE.md` accordingly.

### 3.7 Documentation

README rewritten to match the properties and this document:

1. Title, badges, one-paragraph purpose (P1).
2. "What is verified" table: check, applies to (wheel, sdist, install), failure message.
3. Quick start: three lines, using an exact release tag with a SHA pin example (`v1.0.0`), consistent
   with `CLAUDE.md`. No floating tags.
4. Inputs and outputs tables (section 3.1, 3.2), identical to `action.yaml`.
5. Matrix example (OS x Python x dist-type) and a "monorepo" example with `project-path`.
6. Troubleshooting: one entry per `❌` message.
7. Migration from 0.x (section 4).
8. Run it locally: `bash scripts/check_dist.sh dist/x.whl ...`.

Remove the "Flexible - optional scripts" claim (F14). `CONTRIBUTING.md` keeps its content but its
test and structure sections are updated for the new scripts.

### 3.8 CI and repository

Kept as is, because it follows the documented structure and is already least-privilege with SHA
pins: `ci.yaml`, `ci-format.yaml`, `ci-shell.yaml`, `ci-verify-workflows.yaml`, `lib-*.yaml`,
`bot-*.yaml`, `security-*.yaml`, `nightly*.yaml`, `Makefile` and `.make/`.

Changes:

- `ci-action.yaml`: as in 3.6.
- `ci-shell.yaml`: add `windows-latest` to the bats matrix only if Windows support (P8) is
  confirmed. See section 6.
- `nightly-test-released.yaml`: same new job list, pointing to the latest release. Updated with each
  release as today.
- Add one `make test-shell` target (`bats tests/bats/`) and call it from `ci-shell.yaml`, so CI and
  local runs match (`CLAUDE.md`: use make targets in steps). Check whether `.make/shell.mk` already
  provides one before adding it.

## 4. Breaking changes and migration

Release as `v1.0.0` (an exact tag, no floating tag).

| Change                                                               | Who is affected                          | Migration                                                          |
| -------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------ |
| `verify-wheel-extra`, `verify-sdist-extra` removed                   | callers that set them to `false`         | Delete the inputs. Remove the extra from `package-extra` instead. |
| `py.typed` and pyright can be disabled with `check-types: false`     | none (new input, default keeps behaviour) | none                                                               |
| `module.__version__` is no longer required, metadata version is used | none, only less strict                   | none                                                               |
| `__version__ == 0.0.0` check moved to metadata                       | projects that report `0.0.0` in metadata | Fix packaging (it is a real bug)                                   |
| twine and pyright failures now fail the job                          | projects that relied on the silent skip  | Fix the cause, or set `check-types: false`                         |
| `dist/` in the workspace is no longer used or written                | callers that read `dist/` after the action | Use the `wheel-path` and `sdist-path` outputs                     |
| `WHEEL_PATH`, `SDIST_PATH`, `MODULE_NAME` no longer exported to `$GITHUB_ENV` | callers that read these variables | Use the outputs                                                    |
| `.venv` is no longer created in the workspace                        | callers that reused it                   | Create their own environment                                       |
| Dependency names compared in normalized form, `uv pip tree` check removed | none (less strict on spelling, same coverage) | none                                                           |
| Stricter `py.typed` path (`<module>/py.typed`)                       | packages that ship the marker elsewhere  | Move it into the package (required by PEP 561 anyway)             |
| `twine check --strict`                                               | packages with metadata warnings          | Fix the warnings                                                   |

## 5. Deliberately left alone

- Composite implementation (no Docker or JavaScript action).
- Building with `uv build` only. Supporting other build frontends is out of scope.
- `uv pip install` into a venv, not `uv sync`: the check is about the published artifact, not the
  lock file.
- A `dist-type` matrix input instead of installing both artifacts in one run. It keeps jobs
  parallel and failures attributable. Users who want both write a two-entry matrix.
- Dependency **versions** are not checked. Only that declared direct dependencies are installed.
- Workflow file layout and naming, Makefile and `.make/`, bot workflows, security workflows.
- No new floating tags (`CLAUDE.md`).

## 6. Open decisions

1. **`--no-sources`**: recommend adding it behind a `build-args`-style opt-in later, not in v1.0.
2. **Windows**: P8 lists it, but bash scripts on Windows have not been tested here. Recommendation:
   add `windows-latest` to the `ci-action.yaml` matrix in the first PR. If it fails for reasons
   outside the action, drop the claim from P8 and document Linux and macOS only.
3. **Tool pinning** for `twine` and `pyright` (section 3.3): recommend unpinned.
4. **Single `check_dist.sh` vs two scripts** (wheel, sdist): recommend a single script, since the
   only difference is how the metadata file is read (one `case` on the extension).

## 7. Implementation order

One branch and PR per row (`CLAUDE.md` workflow). Each PR keeps `make lint`, `make format` and
`bats tests/bats/` green. CI is not awaited locally and the action steps cannot run locally, so the
PR descriptions must say so.

| PR  | Branch                                | Content                                                                                       | Fixes                      |
| --- | ------------------------------------- | --------------------------------------------------------------------------------------------- | -------------------------- |
| 1   | `refactor/shell-lib`                  | Add `scripts/lib.sh` and tests. No behaviour change yet.                                      | groundwork for F9, F12     |
| 2   | `refactor/check-dist`                 | `check_dist.sh` replaces both `verify_*_extras.sh`. Reads PKG-INFO for sdists. Delete the old scripts and tests. | F5, F10, F11, F12          |
| 3   | `refactor/check-install`              | `check_install.sh` replaces `check_metadata.sh` and `check_dependency_tree.sh`.               | F6, F8, F9                 |
| 4   | `feat/isolated-build-and-checks`      | Rewrite `action.yaml` to the 7 steps: temp dirs, venv, outputs, `uvx`, hard failures, new inputs, removed toggles. Rename `check_type.sh` to `check_types.sh`. | F1, F2, F3, F4, F7, F13, F17, F18 |
| 5   | `test/failure-matrix`                 | Collapse failure jobs into one matrix, add regression cases, add project-path and no-types jobs. Delete `tests/package_checks.py`. | F15, F16                   |
| 6   | `docs/readme-v1`                      | README, CONTRIBUTING and `CLAUDE.md` updates, migration guide.                                | F14                        |
| 7   | `chore/release-v1`                    | Tag `v1.0.0`, bump the pin in `nightly-test-released.yaml`.                                   | P11                        |

PRs 2 and 3 can ship in the current action (script-level, same calling convention) so that the
action works at every step. PR 4 is the only one that breaks the public API.

## 8. Acceptance criteria

The target state is reached when:

- All properties P1 to P12 hold, each backed by a test or a CI job listed in 3.6.
- `action.yaml` has 7 checks steps plus the artifact listing, and no step interpolates an input.
- `scripts/` holds `lib.sh`, `check_dist.sh`, `check_install.sh`, `check_types.sh`, about 350 lines.
- Each regression case F1 to F11 has a test that fails on the old behaviour.
- The README, `action.yaml` and `CLAUDE.md` describe the same inputs and outputs.
- Verified end to end in CI: Python/OS matrix, every extra, every failure case, and the nightly
  run of the released tag.

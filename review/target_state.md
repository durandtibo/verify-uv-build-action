# verify-uv-build-action: target state

Status: proposal. Nothing in this document is implemented yet. It replaces the previous review
(G1 to G11), whose findings are all implemented on `main`.
Basis: `action.yaml`, `scripts/*.sh`, `tests/`, `README.md`, `CLAUDE.md` and `.github/workflows/*`
at `c622733` (`main`, `v0.1.0` not tagged yet).
Scope: breaking changes are accepted; the future state matters more than the current one. Windows
stays out of scope.

Verified while writing (run locally, uv 0.13.7, macOS): `bats tests/bats/` passes (148 tests);
`uv build` reads the project's `[tool.uv]` (see H1); `--no-config` fixes it for `uv build`,
`uv venv`, `uv pip install` and `uv pip show --python` (see H1); `uv pip check --python <venv>`
works on a venv outside the project. Not verified: anything that only runs on GitHub runners.

## 1. Properties of the action

Every decision in section 3 is justified against one of these. P1 to P13 are the current
properties; the wording of P2, P4, P5 and P6 is tightened and P14 is new.

| #   | Property                  | Definition                                                                                                                                                                                                                                                                                              |
| --- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | Purpose                   | Build a Python project with `uv build`, then verify that the **published artifacts** (wheel and sdist) are correct and usable: metadata, extras, typing marker, a clean install, the import, type completeness. It checks artifacts, never the source tree.                                             |
| P2  | Faithful and hermetic     | What is verified is what a user gets from `pip install <package>`. The build **and** the install ignore the checkout's uv configuration (`[tool.uv]`, `uv.toml`, `[tool.uv.sources]`) and the checkout's files (no `src/` on `sys.path`, no stale `dist/`). This is enforced by a flag, not by the cwd. |
| P3  | Fail loudly               | A check that cannot run is a failure, never a skip. No discarded errors. Opt-outs are explicit inputs.                                                                                                                                                                                                  |
| P4  | Minimal configuration     | `uses:` with no input works for a standard `uv` project. An input exists only if its effect cannot be inferred. Inputs are assertions or switches, never plumbing.                                                                                                                                      |
| P5  | Fast                      | One build, one install per verified artifact, tools through `uvx`. Cheap archive checks run before any install. Nothing is done twice. Total overhead on top of `uv build` stays in the tens of seconds with a warm cache.                                                                              |
| P6  | Simple to maintain        | One executable (`scripts/verify.sh`) plus sourced libraries. `action.yaml` only installs uv and calls it. No logic in YAML, no duplicated logic between wheel and sdist, between workflows, between local and CI runs. Fewer files and fewer lines beat more flexibility.                               |
| P7  | Safe                      | Inputs reach scripts only through `env:` and are validated before use. Third-party actions are pinned to SHAs. Least-privilege permissions. Tool versions are pinned.                                                                                                                                   |
| P8  | Portable                  | Linux and macOS runners, GNU and BSD tools, bash 3.2. The same entry point runs locally and in CI.                                                                                                                                                                                                      |
| P9  | Non-polluting, re-entrant | No exported env vars, no `.venv`, no file in the workspace. Every invocation owns a unique temporary directory, so several invocations in one job never interfere. Outputs stay valid for the whole job.                                                                                                |
| P10 | Actionable diagnostics    | One `❌` line per failure says what was expected and what was found, and shows as a GitHub annotation. Details are in collapsed log groups. **The job summary states the verdict, the failed phase and the reason**, even when the run failed.                                                          |
| P11 | Stable, versioned         | Inputs and outputs are a public API. Releases are immutable exact tags, no floating tags. Breaking changes are listed in the release notes.                                                                                                                                                             |
| P12 | Dogfooded                 | CI runs the unreleased action on a Python/OS matrix and proves that **every check fails when it should**, with the real tools. A scheduled run uses the latest upstream tools.                                                                                                                          |
| P13 | Single source of truth    | Each fact lives once: input defaults in `action.yaml` (README table enforced by a test), tool pins in one file, error messages in scripts (README troubleshooting enforced by a test), the Python/OS matrix in one workflow, check logic in `scripts/`.                                                 |
| P14 | Proportionate             | The repository's machinery (workflows, tests of tests, tables) must stay small relative to what it protects. A mechanism that exists only to keep another mechanism in sync is a candidate for deletion.                                                                                                |

## 2. Review of the current state

### 2.1 What is good and stays

- Composite action, no Docker, no Node. Fail-fast phases in collapsed log groups, outputs instead of
  exported variables, one temporary directory per invocation (G1 is fixed).
- `uv build --no-sources`, `twine check --strict`, `pyright --verifytypes` through `uvx`, all tools
  pinned.
- Exactly one place for each check (`check_dist.sh`, `check_install.sh`, `check_types.sh`), all
  failures of a phase reported together, names normalized per PEP 503/685, no `py.typed` check on
  the sdist (the wheel is built from it; confirmed in the `uv build` output: "Building wheel from
  source distribution").
- The failure cases of `ci-action.yaml` live in one table (`tests/cases.json`).
- Input validation before any work, with exit code 2.

### 2.2 Problems

Severity: **H** = a check gives a wrong answer or the user-facing contract is broken, **M** =
fragile, misleading or untested, **L** = maintenance cost or polish.

| ID  | Sev | Problem                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Where                                     |
| --- | --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| H1  | H   | The **build is not hermetic.** `uv build "${PROJECT_PATH}"` reads the project's `[tool.uv]`. Verified: with `[tool.uv] index-url = "http://127.0.0.1:9/simple"` in the project, `uv build --no-sources` fails with "Failed to resolve requirements from `build-system.requires`" (it tried to fetch `hatchling` from that index), while `uv build --no-config --no-sources` succeeds. The install is isolated only by running from `${WORK}`, which is an accident of the cwd, not a rule (violates P2).          | `verify.sh` `build_dists`, `install_dist` |
| H2  | H   | The CI case "project uv config is ignored" (`tests/cases.json`) puts the same unreachable `index-url` in the project and expects success. By H1 the build step reads it, so the case either fails or only passes through a warm uv cache. It is not a reliable proof of P2. Treat as a suspected failing or flaky test until run on a runner.                                                                                                                                                                     | `tests/cases.json`                        |
| M1  | M   | `action.yaml` still holds untested logic: the "Show artifacts" step is 20 lines of shell (`unzip -Z1`, `tar -tzf`, summary markup) with no test, against the rule "all logic in tested scripts". It also writes no verdict: on failure the summary shows the archive listing but not what failed (violates P6, P10).                                                                                                                                                                                              | `action.yaml`                             |
| M2  | M   | `check_dist.sh`, `check_install.sh` and `check_types.sh` are each a library **and** a CLI (usage, `main`, argument validation, exit code 2). `verify.sh` calls them as subprocesses (`bash check_dist.sh ...`, with `cd "${WORK}" && VIRTUAL_ENV=... PATH=...`) and also sources one of them for `read_version`. `module-name` is validated three times (verify, check_dist, check_types). About 120 lines of script and about 150 lines of bats exist only to support a CLI that nothing uses (violates P6).     | `scripts/check_*.sh`, `tests/bats/`       |
| M3  | M   | The two tool pins and every other default are written in two places: `action.yaml` and `apply_defaults` in `verify.sh` (`7.0.0`, `1.1.414`, `both`, `true`, `.`). The README table is tested against `action.yaml` only, so `verify.sh` can drift (violates P13). Nothing bumps the pins; pyright 1.1.414 is already old, and a stale pin silently changes what "type complete" means.                                                                                                                            | `action.yaml`, `verify.sh`                |
| M4  | M   | `package-name` is required although it can be read from the wheel. Every user must type a name that is already in `pyproject.toml`, and a typo is the only thing the input protects against (violates P4). Its value as an assertion is real but should be opt-in.                                                                                                                                                                                                                                                | `action.yaml`                             |
| M5  | M   | The installed environment is checked for the package only. `uv pip check` (verified to work with `--python <venv>`) detects conflicting or missing dependencies in the venv in milliseconds and is not run, so an artifact whose declared requirements conflict passes if it still imports.                                                                                                                                                                                                                       | `check_install.sh`                        |
| M6  | M   | `nightly-test-released.yaml` (142 lines) and `nightly.yaml` (29 lines) mirror `ci-action.yaml`, `tests/bats/test_workflow_mirror.bats` (89 lines) exists only to keep the two aligned, `load-cases.sh` (51 lines) plus `test_load_cases.bats` (63 lines) exist only to filter by a `released` flag, and the allow-list and the flags must be hand-edited on every release. About 370 lines maintain a copy. The scheduled run of `ci.yaml` already runs the same cases against `main` every night (violates P14). | `.github/workflows/`, `tests/`            |
| M7  | M   | The README troubleshooting table lists about 25 message prefixes by hand. Nothing checks that a prefix still exists in the scripts, so it rots silently; the "Migration from 0.0.x" table (14 rows) will stay in the README for ever (violates P13, P14).                                                                                                                                                                                                                                                         | `README.md`                               |
| L1  | L   | `setup-uv` is called with its default cache behaviour. Whether the cache is saved (and with what key when the project has no `uv.lock`) is an undocumented side effect of the action: either P5 (pyright and twine downloads are cached) or P9 (the job writes to the repository's cache budget) is decided by accident. Not verified on a runner.                                                                                                                                                                | `action.yaml`                             |
| L2  | L   | Outputs give two file paths but not the directory. Publishing needs `dist/*`-style globs; users build `dirname "$wheel-path"` themselves.                                                                                                                                                                                                                                                                                                                                                                         | `action.yaml`                             |
| L3  | L   | `package-extra` (singular) takes a list.                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `action.yaml`, `README.md`                |
| L4  | L   | The wrapper `bash verify.sh \|\| { echo "❌ Verification failed" >&2; exit 1; }` adds a second, contentless error line after the specific one.                                                                                                                                                                                                                                                                                                                                                                    | `action.yaml`                             |

### 2.3 Considered and rejected

- **Rewrite in Python** (one `verify.py` with `zipfile`, `tarfile`, `email.parser`; run with
  `uv run --no-project`). It would remove the awk metadata parsing, `unzip`, the bash 3.2 job and
  three lint tools. Rejected for now: it is a rewrite of 800 lines that work and have 148 tests,
  it changes the toolchain documented in `CLAUDE.md` (P6, P8), and the current parsing is
  adequate. Revisit if checks need real metadata semantics (markers in `Requires-Dist`, license
  expressions) or the scripts grow past about 800 lines.
- **Verify the source tree** (`pyright` on `src/`, `pytest`). Out of scope (P1).
- **A matrix input** (`dist-type: both` already covers wheel and sdist in one job).
- **Run the wheel and sdist installs in parallel.** The sdist install is the slow one, but
  background jobs make failure reporting and logs harder for a gain that the default cache largely
  removes (P6 over P5).
- **Reject every `.devN` version.** Legitimate in pull request builds. Only the `0.0.0` placeholder
  stays invalid.

## 3. Target state

### 3.1 Interface

Inputs after the change. Defaults are written in `action.yaml` only.

| Input                  | Default | Change                                                                                                       |
| ---------------------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| `package-name`         | `""`    | **Optional.** Empty: read from the built wheel. Set: asserted equal (normalized). Fixes M4.                  |
| `module-name`          | `""`    | Unchanged (derived from the package name, `.` means a sub-package).                                          |
| `package-extras`       | `""`    | **Renamed** from `package-extra` (L3).                                                                       |
| `package-dependencies` | `""`    | Unchanged.                                                                                                   |
| `dist-type`            | `both`  | Unchanged.                                                                                                   |
| `python-version`       | `3.13`  | Unchanged.                                                                                                   |
| `project-path`         | `.`     | Unchanged.                                                                                                   |
| `check-types`          | `true`  | Unchanged.                                                                                                   |
| `twine-version`        | `""`    | Empty means the pin of `scripts/tools.txt` (T5). A value overrides it. Replaces the hard-coded default (M3). |
| `pyright-version`      | `""`    | Same.                                                                                                        |

Outputs: `wheel-path`, `sdist-path`, `version` unchanged; **`dist-dir`** added (L2): the directory
that holds both files, ready for `upload-artifact` or `uv publish "$dist_dir"/*`. All outputs are
written right after the build, so they exist even when a later phase fails.

Exit codes of `verify.sh`: 0 passed, 1 a check failed, 2 invalid inputs (unchanged).

### 3.2 Phases

Same fail-fast order, with two additions marked **new**. Each phase is one function and one log
group.

| #   | Phase          | What it does                                                                                                                                 |
| --- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Validate       | All inputs, all errors reported, exit 2. `package-name` is validated only when set.                                                          |
| 2   | Build          | `uv build --no-config --no-sources` into `${WORK}/dist` (H1). One wheel, one sdist. **New:** resolve `PACKAGE_NAME` from the wheel if empty. |
| 3   | Check archives | Name, version, extras, `py.typed` (wheel), same version in both, `uvx --no-config twine check --strict`.                                     |
| 4   | Install        | `uv venv --no-config` and `uv pip install --no-config --python <venv>` per selected artifact. No `cd`, no `VIRTUAL_ENV`, no `PATH` edit.     |
| 5   | Check install  | Name, version, dependencies, import (`python -I` of the venv interpreter), **new:** `uv pip check --python <venv>` (M5).                     |
| 6   | Check types    | `pyright --verifytypes` on the first installed artifact (if `check-types`).                                                                  |

Every phase appends `<status> <phase>` and the text of each `log_error` to `${WORK}/report`.
An `EXIT` trap in `verify.sh` renders the job summary from it (M1), see 3.4.

### 3.3 Files

Target layout of `scripts/` (all sourced by `verify.sh` except `verify.sh` itself):

| File               | Role                                                                 | Change                                                                                                    |
| ------------------ | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `verify.sh`        | The only executable: inputs, phases, outputs, summary.               | Gains `write_summary`, `resolve_package_name`; loses subprocess plumbing.                                 |
| `lib.sh`           | Logging, name normalization, CSV, identifier checks.                 | `log_error` also appends to the report.                                                                   |
| `check_dist.sh`    | Library: `check_dist`, `read_version`, `read_field`, `list_archive`. | **Loses** `usage`, `main`, argument parsing, exit codes.                                                  |
| `check_install.sh` | Library: `check_install` (adds `uv pip check`).                      | **Loses** `usage`, `main`, argument parsing; takes the venv as argument and calls `uv pip show --python`. |
| `check_types.sh`   | Library: `check_types`.                                              | **Loses** `usage`, `main`, argument parsing.                                                              |
| `tools.txt`        | Pins: `twine==7.0.0`, `pyright==1.1.414` (T5).                       | **New.**                                                                                                  |
| `load-cases.sh`    | Deleted (T6).                                                        | **Removed.**                                                                                              |

Functions that take explicit arguments (`check_install <venv> <package> <module> <deps> <version>`)
replace the environment contract (`VIRTUAL_ENV`, `PYRIGHT_VERSION`, cwd). Validation of a value
happens once, in `validate_inputs`; library functions trust their caller (they are not a public
interface).

`action.yaml` after the change (two steps, about 70 lines instead of 136):

```yaml
runs:
  using: "composite"
  steps:
    - name: Set up uv
      uses: astral-sh/setup-uv@<sha> # ratchet:astral-sh/setup-uv@<tag>
      with:
        python-version: ${{ inputs.python-version }}
        enable-cache: false # decided explicitly, see T8
    - name: Verify
      id: verify
      shell: bash
      env:
        PACKAGE_NAME: ${{ inputs.package-name }}
        # ... one line per input
      run: bash "$GITHUB_ACTION_PATH/scripts/verify.sh"
```

The `set -euo pipefail` line is dropped from the `run:` only if `CLAUDE.md` is amended to say that a
step whose body is a single script call is exempt (the script sets it); otherwise keep it.

### 3.4 Job summary

`write_summary` runs from the `EXIT` trap, so it also runs after a failure. It writes to
`$GITHUB_STEP_SUMMARY` (skipped when unset):

```text
## ❌ Verify uv build: failed in "Check archives"
- ❌ wrong package name in dist/x.whl (expected a, got b)

| Phase          | Result |
| -------------- | ------ |
| Validate       | ✅     |
| Build          | ✅     |
| Check archives | ❌     |
| Install        | skipped |
...
<details><summary>Content of x.whl</summary> ... </details>
```

This replaces the "Show artifacts" step. It is plain bash over `${WORK}/report` and the archives, so
it is covered by bats (set `GITHUB_STEP_SUMMARY` to a temp file).

### 3.5 Tools pins (T5)

`scripts/tools.txt` holds `twine==X` and `pyright==Y`. `verify.sh` reads the version of a tool from
it when the input is empty and builds `uvx "<tool>==<version>"`. `.github/dependabot.yml` gets a
`pip` entry for `/scripts` so that the pins are bumped by pull requests that CI then tests (the
scheduled `test-latest-tools` job catches upstream breakage earlier). The README no longer states
the version in prose, only "pinned, see `scripts/tools.txt`". To verify before implementing:
that Dependabot's pip ecosystem picks up a file named `tools.txt` (if not, name it
`requirements.txt`).

### 3.6 Workflows

Target set (14 files instead of 16):

| File                                                              | Change                                                                  |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `ci.yaml`                                                         | Unchanged: it already has the nightly schedule.                         |
| `ci-format`, `ci-shell`, `ci-shell-bash32`, `ci-verify-workflows` | Unchanged.                                                              |
| `ci-action.yaml`                                                  | Cases loaded inline (`jq -c . tests/cases.json`); two new jobs (below). |
| `nightly.yaml`, `nightly-test-released.yaml`                      | **Deleted** (T6).                                                       |
| `lib-*`, `bot-*`, `security-*`                                    | Unchanged.                                                              |

Why deleting the released-action mirror is right (P14): the released tag is immutable, and the only
things that change under it are uv, twine, pyright, the runner image and PyPI. The scheduled run of
`ci.yaml` already exercises all of those with the full case table; the extra run of the released
tag adds signal only when `main` and the release differ, which is exactly when the unreleased
code is the one under development. Deleted with it: `test_workflow_mirror.bats`, `load-cases.sh`,
`test_load_cases.bats`, the `released` and `comment`-for-release fields of `cases.json`, the
release checklist in the workflow header and in `CLAUDE.md`. Net: about 370 lines and one manual
step per release.

### 3.7 Tests

- `tests/bats/test_check_*.bats`: call the functions directly (sourced) instead of the CLI; drop the
  argument-parsing tests (M2). Everything else stays.
- `test_verify.bats` (uv/uvx mocked): add the summary (verdict, failed phase, reason), the
  `package-name` inference, the `--no-config` flags (assert the mock saw them), `dist-dir`, and the
  pin lookup.
- `test_readme.bats`: add (a) README defaults equal `action.yaml` defaults **and** `verify.sh`
  contains no default literal for an input (grep for the old ones), (b) every message prefix of
  the troubleshooting table occurs in `scripts/` (M7).
- `cases.json`: fix H2 by making the case unambiguous (see T1), and add rows for the checks that
  have no real-tool proof: wheel and sdist with different versions (two-backend fixture or a
  `setup` that breaks one), `uv pip check` conflict, `package-name` omitted, `dist-type: wheel`.
- Keep `test-two-invocations`, `test-latest-tools`; fold `test-tool-versions` into a case row.

### 3.8 Documentation

- README: properties at the top (a short list, P1 to P14 condensed), one quick start with only
  `uses:` (no `package-name`), the inputs table, the phases table, troubleshooting (tested).
- The "Migration from 0.0.x" table moves to the `v0.1.0` release notes and is removed from the README
  once released; the README keeps one line pointing to the release notes.
- `CLAUDE.md`: remove the nightly-mirror paragraph and the "check scripts have a CLI" wording;
  state that the check scripts are libraries sourced by `verify.sh`.

## 4. Breaking changes

All land before `v0.1.0` is tagged, so they ride the existing breaking release.

| Change                                                   | Impact                                                                  | Migration                                      |
| -------------------------------------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------- |
| `package-extra` renamed `package-extras`                 | Workflows that set it fail with "Unexpected input".                     | Rename the input.                              |
| The build ignores the project's `[tool.uv]` / `uv.toml`  | A project that needs a private index or `exclude-newer` to build fails. | Set `UV_INDEX_URL` or another `UV_*` variable. |
| `package-name` optional                                  | None (relaxation).                                                      | None.                                          |
| New check `uv pip check`                                 | A project with conflicting declared dependencies now fails.             | Fix the requirements.                          |
| `twine-version` and `pyright-version` default to `""`    | Documentation only; the effective defaults are the pins of `tools.txt`. | None.                                          |
| New output `dist-dir`                                    | None.                                                                   | None.                                          |
| `scripts/check_*.sh` are no longer runnable on their own | Only affects someone who called them from outside the action.           | Use `PACKAGE_NAME=... bash scripts/verify.sh`. |

## 5. Implementation plan

One branch and one PR per row, in this order (CLAUDE.md git workflow). Each keeps `make lint`,
`make format` and `bats tests/bats/` green.

| PR  | Branch                               | Content                                                                                           | Fixes          |
| --- | ------------------------------------ | ------------------------------------------------------------------------------------------------- | -------------- |
| 1   | `bugfix/hermetic-build`              | `--no-config` on build, venv, install, show; drop the `cd` trick; make the CI case reliable (T1). | H1, H2         |
| 2   | `refactor/check-scripts-as-libs`     | Remove CLIs, pass explicit arguments, validate once; update bats and header comments.             | M2             |
| 3   | `feat/job-summary`                   | `report` file, `EXIT` trap, `write_summary`, remove the "Show artifacts" step, drop the wrapper.  | M1, L4         |
| 4   | `chore/delete-nightly-mirror`        | Delete the mirror workflows, the mirror test, `load-cases.sh` and its test; update `CLAUDE.md`.   | M6             |
| 5   | `feat/tools-pins-file`               | `tools.txt`, empty defaults, Dependabot `pip` entry, defaults only in `action.yaml`.              | M3             |
| 6   | `feat/optional-package-name`         | Infer the name from the wheel; `dist-dir` output; rename to `package-extras`; `uv pip check`.     | M4, M5, L2, L3 |
| 7   | `docs/readme-tested-troubleshooting` | Properties in the README, tested troubleshooting table, migration table to release notes.         | M7             |
| 8   | `ci/explicit-uv-cache`               | Decide and set `enable-cache` after measuring a run with and without (T8).                        | L1             |

PRs 1 and 4 are independent of the rest and can go first. PR 6 is the only one that changes the
public API beyond a rename and should be reviewed with the README diff open.

### Decisions to confirm and facts to check

- **T1.** Make the "project uv config is ignored" case reliable: use a project `[tool.uv]` that
  breaks the install but not the build (for example `exclude-newer = "2000-01-01"`, which makes the
  `coola` dependency unresolvable) and a second case with an unreachable `index-url` that proves
  the build is isolated too. Check both fail on `main` today and pass after PR 1.
- **T5.** Dependabot and a file named `tools.txt` (see 3.5).
- **T8.** `enable-cache`: keep it off if the measured gain is under about 10 seconds (P9 and P6
  win), on otherwise (P5 wins). pyright's PyPI wrapper downloads a Node package on first use, which
  the uv cache does not hold; measure that too.
- **Name inference.** Confirm that dynamic names are not a case to support (PEP 621 requires
  `name` to be static), so reading `Name` from the wheel is always possible.
- **Not run here:** everything that needs a GitHub runner (the matrix, the cache, the summary
  rendering, Dependabot).

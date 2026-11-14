# verify-uv-build-action: target state

Status: proposal. Nothing in this document is implemented yet.
Basis: review of `action.yaml`, `scripts/*.sh`, `tests/bats/`, `README.md`, `CLAUDE.md`,
`CONTRIBUTING.md` and `.github/workflows/*` at commit `ba37bea` (`main`, v0.1.0 not tagged yet).
Scope: breaking changes are accepted. Windows stays out of scope. The previous proposal (F1 to F18,
PRs 1 to 6) is implemented and is not repeated here. This document starts from the code as it is
now.

Verified while writing (commands run locally): `bats tests/bats/` passes (72 tests);
`uv pip install` run from a directory with a `pyproject.toml` that has `[tool.uv] index-url`
uses that index, run from another directory it does not (see G2). Not verified: anything that only
runs on GitHub runners.

## 1. Properties of the action

These are the properties the action must have. Every choice in section 3 is justified against one
of them. P1 to P12 are the current properties; the wording changed where the review found a gap
(P2, P5, P9, P10 and P12 are tightened, P13 is new).

| #   | Property                  | Definition                                                                                                                                                                                                                                                                                   |
| --- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | Purpose                   | Build a Python project with `uv build`, then verify that the **published artifacts** (wheel and sdist) are correct and usable: metadata, extras, typing marker, a clean install, the import and type completeness. It checks artifacts, never the source tree.                               |
| P2  | Faithful                  | What is verified is what a user gets from `pip install <package>`. Checks run on the built files and on a clean install that is **hermetic**: not influenced by the checkout (no `src/` on `sys.path`, no stale `dist/`) nor by the project's own uv configuration (`[tool.uv]`, `uv.toml`). |
| P3  | Fail loudly               | A check that cannot run is a failure, never a skip. No discarded errors, no "tool not available, skipping". Opt-outs are explicit inputs.                                                                                                                                                    |
| P4  | Minimal configuration     | Only `package-name` is required. Defaults are right for a standard `uv` project. An input exists only if its effect cannot be inferred. No toggle for a check that is always cheap.                                                                                                          |
| P5  | Fast                      | One build, one install per verified artifact, tools through `uvx` (cached, isolated). Cheap archive checks run before the install. No work is done twice, and a job needs no matrix to cover both artifacts.                                                                                 |
| P6  | Simple to maintain        | All logic is in bash scripts that are unit tested; `action.yaml` only wires inputs to the scripts. Few files, small functions, no duplicated logic between wheel and sdist, between workflows, or between local and CI runs.                                                                 |
| P7  | Safe                      | Inputs reach scripts only through `env:` and are validated before use (name, module, versions, enums). Third-party actions are pinned to SHAs. Least-privilege permissions. Tool versions are pinned.                                                                                        |
| P8  | Portable                  | Linux and macOS runners, GNU and BSD tools. Scripts also run locally with the same entry point as CI.                                                                                                                                                                                        |
| P9  | Non-polluting, re-entrant | Leaves no state for later steps: no exported env vars, no `.venv`, no file in the workspace. Every invocation uses its own temporary directory, so several invocations in one job (monorepo, wheel and sdist) never interfere. Results are step outputs that stay valid for the whole job.   |
| P10 | Actionable diagnostics    | One `❌` line per failure says what was expected and what was found, and shows as a GitHub annotation. Details (file lists, metadata) are in collapsed log groups and in the job summary. All failures of a phase are reported together.                                                     |
| P11 | Stable, versioned         | Inputs and outputs are a public API. Releases are immutable exact tags, no floating tags. Breaking changes are listed in the README.                                                                                                                                                         |
| P12 | Dogfooded                 | CI runs the unreleased action on a Python/OS matrix and proves that **every headline check fails when it should** (not only through mocked unit tests). A nightly run exercises the latest release **and the latest upstream tools**.                                                        |
| P13 | Single source of truth    | Each fact lives once: input defaults and tool pins in `action.yaml` (and the README table, enforced by a test); the shared matrix in `lib-get-test-matrix.yaml`; the build, check and install logic in `scripts/`.                                                                           |

## 2. Review of the current state

### 2.1 What is good and stays

- Composite action, no Docker, no Node. Seven steps in a fail-fast order, outputs instead of
  exported variables, artifacts outside the workspace.
- `uv build --no-sources`, `twine check --strict`, tools pinned and run through `uvx`.
- Scripts are sourceable, share `lib.sh`, report all failures of a script before exiting, normalize
  names (PEP 503/685), and have a bats file each (72 tests).
- `ci.yaml` / `ci-*` / `lib-*` / `bot-*` / `security-*` layout, least-privilege permissions, SHA pins.
- The failure matrix in `ci-action.yaml` (one job, one table) is the right shape.

### 2.2 Problems

Severity: **H** = a check gives a wrong answer or a result becomes invalid, **M** = fragile,
untested or misleading, **L** = maintenance cost or polish.

| ID  | Sev | Problem                                                                                                                                                                                                                                                                                                                                                                                                                    | Where                                         |
| --- | --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| G1  | H   | Build and venv directories are fixed (`$RUNNER_TEMP/verify-uv-build/{dist,venv}`) and `rm -rf`ed at the start of each run. A second invocation in the same job (the README monorepo example, or a wheel run followed by an sdist run) deletes the files of the first, so the `wheel-path` / `sdist-path` outputs of the first run dangle (violates P9).                                                                    | `action.yaml` "Build", "Install"              |
| G2  | H   | "Install" runs `uv venv` and `uv pip install` from the workspace. uv reads the project's `[tool.uv]` / `uv.toml` there (verified: a project `index-url` is used from the project directory, not from another directory). `exclude-newer`, `index-url`, `override-dependencies` change what is installed, so the check no longer matches `pip install <package>` (violates P2). The `twine` call has the same cwd.          | `action.yaml` "Install", "Check artifacts"    |
| G3  | M   | About 110 of the 190 lines of shell are inline in `action.yaml` and untested: input validation, the "exactly one wheel / one sdist" check, version extraction, the install target (`pkg[extra] @ file://...`), the default module name in the types step. `CLAUDE.md` says logic lives in tested scripts. None of it can be run locally, so the README's "run locally" section is three manual commands (violates P6, P8). | `action.yaml`, `README.md`                    |
| G4  | M   | The `py.typed` check on the sdist uses `^[^/]+/(.+/)?<module>/py.typed$`, so `tests/<module>/py.typed` passes. It is also redundant: `uv build` builds the wheel **from the sdist**, so a wheel that contains `<module>/py.typed` proves that the sdist ships it. One strict check on the wheel replaces two.                                                                                                              | `check_dist.sh` `has_py_typed`                |
| G5  | M   | `module-name` is not validated and is used as a regular expression in `check_dist.sh` (`a+b`, `a(b` break or mis-match). The tool-version inputs are not validated either: any string reaches `uvx "twine@..."` (violates P7).                                                                                                                                                                                             | `action.yaml`, `check_dist.sh`                |
| G6  | M   | The headline checks are only proven by mocked unit tests. `ci-action.yaml` has no case where twine fails, where the version is `0.0.0`, where pyright reports incompleteness, or that proves `--no-sources` ignores `[tool.uv.sources]` (violates P12).                                                                                                                                                                    | `ci-action.yaml`                              |
| G7  | M   | `nightly-test-released.yaml` (187 lines) is a hand-written, older copy of `ci-action.yaml`: four copy-pasted failure jobs, the removed `verify-*-extra` inputs, pinned to `v0.0.7`, and the failure cases live twice with no shared table. Nothing checks that the two files stay aligned (violates P6, P13).                                                                                                              | `nightly-test-released.yaml`                  |
| G8  | M   | Tool pins (`twine` 7.0.0, `pyright` 1.1.414) appear in `action.yaml`, the README and the CI overrides, with no signal that a newer tool breaks the action. Nothing runs the latest upstream tools (violates P12, P13).                                                                                                                                                                                                     | `action.yaml`, `README.md`                    |
| G9  | L   | Isolation depends on `working-directory`. `check_install.sh` run from the checkout (as the README local instructions allow) silently loses the protection against importing the source tree. `python -I` makes it independent of the cwd.                                                                                                                                                                                  | `check_install.sh` `import_location`          |
| G10 | L   | Inconsistent script contracts: `check_dist.sh` and `check_install.sh` take `<package> [module]` and default the module themselves; `check_types.sh` only takes a module, so the YAML step sources `lib.sh` to compute it. `INPUT_MODULE_NAME` is passed in three steps.                                                                                                                                                    | `action.yaml` "Check types", `check_types.sh` |
| G11 | L   | Failures are log lines only. The run summary page shows "Process completed with exit code 1" with no reason, and there is no job summary (violates P10).                                                                                                                                                                                                                                                                   | `lib.sh` `log_error`                          |
| G12 | L   | `wheel` and `sdist` are checked against the inputs but never against each other: nothing asserts that they report the same version.                                                                                                                                                                                                                                                                                        | `check_dist.sh`                               |
| G13 | L   | CI and local runs differ: no `make` target runs the bats tests (`ci-shell.yaml` calls `bats` directly), contrary to `CLAUDE.md`.                                                                                                                                                                                                                                                                                           | `Makefile`, `ci-shell.yaml`                   |
| G14 | L   | README: the examples use `actions/checkout@v6` while the repository uses v7. No note for projects that derive the version from VCS tags (`hatch-vcs`, `setuptools-scm`): with the default shallow checkout they publish a dev version, and only the `0.0.0` placeholder is detected.                                                                                                                                       | `README.md`                                   |
| G15 | L   | `dist-type` forces a two-job matrix to cover both artifacts. Each job pays for a runner start, `setup-uv` and a full build, although the build already produces both (violates P5).                                                                                                                                                                                                                                        | `action.yaml`, README matrix example          |

## 3. Target state

### 3.1 Architecture

One script owns the whole flow, `action.yaml` only wires inputs, and the flow is the same locally
and in CI.

```text
action.yaml                     inputs/outputs, setup-uv, one "Verify" step, one summary step
scripts/verify.sh               NEW  validate -> build -> check archives -> install -> check install -> check types
scripts/check_dist.sh           one archive: name, version, extras, py.typed (wheel only)
scripts/check_install.sh        one installed package: name, version, dependencies, import
scripts/check_types.sh          pyright --verifytypes
scripts/lib.sh                  logging, annotations, name normalization, csv, input validation
scripts/load-cases.sh           CI only: builds the case matrices from tests/cases.json
tests/cases.json                the table of end-to-end cases, shared by both workflows
```

`verify.sh` is a sourceable script made of small functions (`validate_inputs`, `build_dists`,
`install_dist`, `run_checks`), with the same input names as the action in upper case
(`PACKAGE_NAME`, `DIST_TYPE`, ...), so `PACKAGE_NAME=mypkg bash scripts/verify.sh` is the local
equivalent of the action. The existing `check_*.sh` scripts stay standalone and are called as
processes, so their tests and usage do not change.

Why one script instead of one YAML step per phase:

- The logic is testable (bats with a mocked `uv`/`uvx`), runnable locally, and exists once (G3, P6).
- `action.yaml` shrinks to inputs, outputs and three steps. The shell-heavy part (about 190 lines)
  moves into tested code.
- The cost is losing per-phase step status in the Actions UI. It is replaced by one
  `::group::` per phase (collapsed, with timing in the log) and an `::error::` annotation per
  failure (G11), which is where people look first anyway.

### 3.2 Inputs (public API)

| Input                  | Required | Default   | Change                                                                                                                                                                                        |
| ---------------------- | -------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package-name`         | yes      | -         | Unchanged. Validated as a distribution name.                                                                                                                                                  |
| `module-name`          | no       | derived   | Unchanged semantics. **Validated** as dotted Python identifiers (`^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$`) (G5).                                                                 |
| `package-extra`        | no       | `""`      | Unchanged.                                                                                                                                                                                    |
| `package-dependencies` | no       | `""`      | Unchanged.                                                                                                                                                                                    |
| `dist-type`            | no       | `both`    | **Changed.** `wheel`, `sdist` or `both`. `both` verifies and installs both artifacts in one job (G15). The default becomes `both` because the purpose is to verify what is published. See D1. |
| `python-version`       | no       | `3.13`    | Unchanged.                                                                                                                                                                                    |
| `project-path`         | no       | `.`       | Unchanged.                                                                                                                                                                                    |
| `twine-version`        | no       | `7.0.0`   | Unchanged default. **Validated** (`latest` or a version). `latest` is a valid value, used by the nightly run (G8).                                                                            |
| `pyright-version`      | no       | `1.1.414` | Same as `twine-version`.                                                                                                                                                                      |
| `check-types`          | no       | `true`    | Unchanged. Controls the `py.typed` marker and pyright.                                                                                                                                        |

No input is removed. `module-name` and the version inputs get stricter validation, which can only
break callers that passed invalid values.

### 3.3 Outputs

| Output       | Content                                                                   |
| ------------ | ------------------------------------------------------------------------- |
| `wheel-path` | Absolute path of the built wheel. **Stays valid for the whole job** (G1). |
| `sdist-path` | Absolute path of the built sdist. Same guarantee.                         |
| `version`    | Version from the built wheel metadata.                                    |

Build files live in `mktemp -d "$RUNNER_TEMP/verify-uv-build.XXXXXX"`, one directory per
invocation, never deleted by a later invocation (the runner deletes `RUNNER_TEMP` at the end of
the job) (G1, P9).

### 3.4 Flow

`action.yaml` steps: (1) `astral-sh/setup-uv` (pinned SHA, `python-version`, no activated
environment), (2) `Verify`: `bash "$GITHUB_ACTION_PATH/scripts/verify.sh"`, inputs in `env:` only,
(3) `Show artifacts`, `if: always()`: listing of the archives into the job summary.

Phases inside `verify.sh`, each in a log group, in a fail-fast order:

| #   | Phase          | What it does                                                                                                                                                                                                                                              | Changes vs now                                                                                   |
| --- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 1   | Validate       | All inputs: enums, `pyproject.toml` exists in `project-path`, package, module and version formats. Reports every invalid input, exit 2.                                                                                                                   | Validation of module and tool versions is new (G5). Runs in the tested script.                   |
| 2   | Build          | `uv build "$PROJECT_PATH" --no-sources --out-dir "$work/dist"`, exactly one wheel and one sdist, version from the wheel metadata, outputs to `$GITHUB_OUTPUT` (skipped when unset, for local runs).                                                       | Unique `$work` directory (G1). Same checks.                                                      |
| 3   | Check archives | `check_dist.sh` on the wheel (name, version, extras, `<module>/py.typed`) and on the sdist (name, version, extras). Then the wheel and the sdist must report the same version (G12). Then `uvx twine@<v> check --strict` on both, run from `$work`.       | `py.typed` only on the wheel (G4). Version equality is new. Same failures are reported together. |
| 4   | Install        | For each selected artifact (`wheel`, `sdist` or both): `uv venv "$work/venv-<type>"`, then `uv pip install` **from `$work`** with the direct reference when extras are set. `UV_*` variables of the caller are respected, the project config is not (G2). | Runs outside the workspace (G2). Loops over `both`.                                              |
| 5   | Check install  | `check_install.sh` for each venv, run from `$work`. The import runs with `python -I` (G9). Version must equal the built wheel version, also for the sdist install.                                                                                        | `python -I`. Called per artifact.                                                                |
| 6   | Check types    | Only if `check-types`, once, on the first installed artifact (wheel when both): `check_types.sh <package> <module>` run from `$work`. The module default is computed inside the script (G10).                                                             | Contract aligned with the other scripts (G10). Once, not per matrix entry.                       |

Decisions that stay: `--no-sources` always on, `twine --strict`, pyright through `uvx` with
`PYTHONPATH` set to the site-packages of the venv, no tool installed into the environment under
test, a check that cannot run is a failure.

Both artifacts verified in one run costs one extra `uv venv` and one install of the sdist (which
builds it, about the cost of the old second job minus a runner start and `setup-uv`). With
`dist-type: wheel` the run is as fast as today.

### 3.5 Scripts

Same conventions as now (`CLAUDE.md`): bash, GNU/BSD portable, sourceable, header comment kept in
sync, exit `0` ok / `1` check failed / `2` bad usage, shellcheck and shfmt clean.

| Script             | Change                                                                                                                                                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib.sh`           | `log_error` also prints `::error::<message>` when `GITHUB_ACTIONS=true` (G11). New `is_dotted_identifier`, `is_version_spec` (G5). `die` and `normalize_name` unchanged.                                                                                                                   |
| `check_dist.sh`    | `py.typed` pattern becomes `^<module path>/py\.typed$` for the wheel only. The sdist is not checked for it (G4). Takes an explicit `check_types` only for the wheel; the sdist call passes `false`. New function `read_version <archive>` reused by `verify.sh` to compare versions (G12). |
| `check_install.sh` | `python -I -c` for the import (G9). Nothing else changes.                                                                                                                                                                                                                                  |
| `check_types.sh`   | Arguments become `<package_name> [module_name]` like the others (G10). Module default computed in `lib.sh`. `PYRIGHT_VERSION` and `VIRTUAL_ENV` stay environment inputs.                                                                                                                   |
| `load-cases.sh`    | New, CI only, about 30 lines. `load-cases.sh all\|released` prints the case matrix of `tests/cases.json` as JSON for `fromJson` (`released`: only rows with `"released": true`). Uses `jq`.                                                                                                |
| `verify.sh`        | New, about 150 lines (G3). Functions listed in 3.1, main guarded by `BASH_SOURCE`.                                                                                                                                                                                                         |

Expected size: scripts about 560 lines (from 480), `action.yaml` about 120 lines (from 274), of
which 80 are the inputs and outputs documentation.

### 3.6 Tests

Bats stays the unit layer, with no network:

- `test_verify.bats` (new): `uv` and `uvx` mocked on `PATH`. Cases: all inputs invalid are reported
  together; build output with 0 or 2 wheels fails; version extraction; two invocations get two
  distinct directories and the first outputs still exist (regression G1); install runs outside the
  project directory (regression G2: the mock records its cwd); `both` installs twice and
  `wheel` once; wheel and sdist with different versions fail (G12); local run without
  `GITHUB_OUTPUT`.
- `test_check_dist.bats`: sdist with `tests/<module>/py.typed` does not matter anymore, wheel with
  the marker only under `tests/` fails (regression G4).
- `test_check_install.bats`: a `python` mock proves `-I` is passed (G9).
- `test_check_types.bats`: new argument contract (G10).
- `test_lib.bats`: `log_error` annotation only under `GITHUB_ACTIONS` (G11), validators (G5).
- `test_load_cases.bats` (new): `all` returns every row, `released` only the flagged ones, an
  unknown mode exits 2, every row has the required keys.
- `test_workflow_mirror.bats` (new): `nightly-test-released.yaml` equals `ci-action.yaml` once the
  header, the workflow name, the `uses:` ref of the action, the artifact names and the loader mode
  are normalized. A short allow-list in the test names the jobs that exist only in `ci-action.yaml`
  because they test a feature the last release does not have yet. This replaces the header comment
  as the guard against drift.
- `test_readme.bats` (new, small): every input of `action.yaml` is in the README inputs table with
  the same default (P13). Plain `grep`, no new tool.

CI (`ci-action.yaml`) is the integration layer. Changes:

- `test`, `test-extra`, `test-tool-versions`: unchanged, except `test-extra` loses the `dist-type`
  matrix dimension because `both` is the default (smaller matrix, same coverage).
- The failure and edge cases move from the YAML matrix to rows of `tests/cases.json`
  (`name`, `expect`, the action inputs, an optional `setup` shell snippet, `released`). A `cases` job
  runs `scripts/load-cases.sh all` and feeds `test-cases` through `fromJson`. `test-cases` gets the
  missing headline cases (G6) as new rows:

  | Case                             | Expect  | Setup                                                                       |
  | -------------------------------- | ------- | --------------------------------------------------------------------------- |
  | version is the placeholder       | failure | set `version = "0.0.0"` in `pyproject.toml`                                 |
  | twine rejects the metadata       | failure | remove the `readme` line                                                    |
  | pyright reports incompleteness   | failure | append an unannotated function to `src/myproject/module.py`                 |
  | `[tool.uv.sources]` is ignored   | success | add `[tool.uv.sources]` with `coola` pointing to a path that does not exist |
  | project uv config is ignored     | success | add `[tool.uv]` with an unreachable `index-url` (regression G2)             |
  | two invocations in one job       | success | a dedicated job running the action twice, then reading both outputs (G1)    |
  | `dist-type: sdist` with an extra | success | existing                                                                    |

  The last two cases need more than a setup line; they get their own small jobs next to
  `test-tool-versions`. A row carries `"released": true` when the last release supports it; at
  release time the flags of the new features are flipped.

- `test-latest-tools` (new job): `twine-version: latest`, `pyright-version: latest`. Not required on
  pull requests (it would turn a PR red because of an upstream release); it runs on the schedule
  of `ci.yaml` only (`if: github.event_name == 'schedule'`, the event of the calling workflow) (G8).

### 3.7 Workflows

Kept as is: `ci.yaml`, `ci-format.yaml`, `ci-verify-workflows.yaml`, `lib-*.yaml`, `bot-*.yaml`,
`security-*.yaml`, `.make/`.

Changes:

- `nightly-test-released.yaml` stays a **mirror** of `ci-action.yaml` (D2), as in
  `build-pypi-package-action`. Same jobs, same assertions, same structure. It differs only by the
  `uses: durandtibo/verify-uv-build-action@<sha> # ratchet:...` ref of the last release instead of
  `uses: ./`, the artifact names, and `load-cases.sh released` instead of `all`, so only the rows
  flagged `"released": true` run. It has `workflow_call` and `workflow_dispatch` (`CLAUDE.md`).
- The mirror is the old file rewritten from the new `ci-action.yaml`: the four copy-pasted failure
  jobs go, the table is shared, the file shrinks to the same size as `ci-action.yaml`. The two files
  are kept aligned by `test_workflow_mirror.bats` (3.6), not by a comment.
- `test-latest-tools` runs on the schedule of `ci.yaml` only, so the **current** code is tested
  against the latest upstream twine and pyright. It is on the allow-list of the mirror test. That
  is the signal that a pin bump is due (G8).
- A release edits the pinned SHA and the ratchet comment of the mirror, flips the `released` flags
  of the new features, and shrinks the allow-list of the mirror test.
- `make test-shell` (`bats --recursive tests/bats`) in the root `Makefile`, called by
  `ci-shell.yaml` (G13). `.make/` is shared and is not edited.
- `ci-shell.yaml`: drop the duplicated "Verify bats installation" and "Show the versions" steps
  (one step prints both versions).

### 3.8 Documentation

- README: quick start with `actions/checkout@v7` and `fetch-depth: 0` (needed when the version
  comes from VCS tags), a table of the six phases, `dist-type` documented with `both`, a "Run the
  checks locally" section reduced to `PACKAGE_NAME=mypkg bash scripts/verify.sh`, troubleshooting
  with one row per `❌` message including the new ones, the migration table below.
- `CONTRIBUTING.md`: repository structure and test sections list `verify.sh` and `make test-shell`.
- `CLAUDE.md`: purpose paragraph lists `verify.sh`; workflow section describes `tests/cases.json`
  and the mirror workflow. These edits are part of the PR that changes the behaviour.

## 4. Breaking changes and migration

| Change                                                          | Who is affected                                         | Migration                                                                    |
| --------------------------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `dist-type` default is `both` instead of `wheel`                | callers that rely on the default and on speed           | Set `dist-type: wheel` to keep the old behaviour. Drop a wheel/sdist matrix. |
| `py.typed` is checked on the wheel only                         | none who ship it in the wheel (the sdist is its source) | None.                                                                        |
| `module-name`, `twine-version`, `pyright-version` are validated | callers that passed a malformed value                   | Fix the value.                                                               |
| Install ignores the project's `[tool.uv]` / `uv.toml`           | projects that need a custom index to install            | Set `UV_INDEX_URL` (or the matching `UV_*` variable) in the job environment. |
| Outputs stay valid after another invocation                     | none (it fixes a bug)                                   | None.                                                                        |
| Wheel and sdist must have the same version                      | projects with inconsistent dynamic metadata             | Fix the version source.                                                      |
| `check_types.sh` arguments are `<package_name> [module_name]`   | people who ran the script directly                      | Pass the package name first.                                                 |

## 5. Deliberately left alone

- Bash scripts instead of Python for the metadata parsing. Core metadata headers are simple enough,
  and the repository rule is bash that runs everywhere without a Python.
- `uv pip install` into a venv (not `uv sync`): the check is about the published artifact, not a
  lock file.
- Fixture at the repository root (`pyproject.toml`, `src/myproject/`). The default
  `project-path: .` is the case 95% of users run, so the main matrix should exercise it. The
  `project-path` case already covers the sub-directory. Known weak point: the fixture reuses the
  repository `README.md` as its `readme`, so a README edit can fail `twine check`. Accepted for now.
- Dependency **versions** are not checked, only that the declared direct dependencies are
  installed. `uv pip check` is not added: uv resolves a consistent environment, so it would pass by
  construction.
- `pyright` stays. `basedpyright` ships its own Node and might avoid a runtime download, but a
  cold-runner measurement is missing (a cold local `uvx basedpyright` took 8.5 s), and it changes
  the tool semantics. Revisit with numbers.
- No `expected-version` input: callers compare the `version` output with their tag in one line.
- No new floating tags, no Windows.

## 6. Decisions

| #   | Decision                                                                                                                                                                                                                                 | Reason                                                                                                                                                    |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | `dist-type` defaults to `both`.                                                                                                                                                                                                          | Matches P1 (verify what is published). The cost is one extra install. Use `dist-type: wheel` for the old behaviour. Confirmed.                            |
| D2  | `nightly-test-released.yaml` stays a mirror of `ci-action.yaml` with the same jobs, the pinned released SHA and the `released` rows of a shared `tests/cases.json`, as in `build-pypi-package-action`. A bats test guards the alignment. | The released API may differ from the current one, `ci-action.yaml` stays simple, and the repo already works this way. See the rationale below. Confirmed. |
| D3  | One `Verify` step (`verify.sh`) instead of one YAML step per phase.                                                                                                                                                                      | Tested logic and a local entry point outweigh per-step status. Confirmed.                                                                                 |

### D2 rationale

Options considered: **A** one workflow with a `released` input and two action steps per job
(`sign-pypi-package-action`), **B** a mirror workflow (`build-pypi-package-action`), **B-slim** a
mirror reduced to smoke jobs.

| Criterion                       | A: `released` input                               | B: mirror (chosen)                              | B-slim         |
| ------------------------------- | ------------------------------------------------- | ----------------------------------------------- | -------------- |
| Duplicated lines                | About 6 per job, one file                         | The whole file, two files                       | About 70 lines |
| Readability of `ci-action.yaml` | Worse: `if: inputs.released` on every action step | Best: only `uses: ./`                           | Best           |
| Drift between the two           | Cannot drift                                      | Guarded by `test_workflow_mirror.bats`          | Small surface  |
| Released API differs            | Works, with conditional noise                     | Natural: a separate file can use the old inputs | Natural        |
| Failure cases against release   | Needs `released` flags and a loader               | Same flags and loader, shared table             | Not run        |
| Release effort                  | Bump the SHA in every released step, flip flags   | Bump one SHA, flip flags, shrink the allow-list | Bump one SHA   |

Why B:

- The nightly run then tests what consumers pick up with the same assertions as CI, including the
  failure cases of the features the release already has. B-slim gives that up.
- The release is a separate copy, so a breaking change of the inputs does not need conditions in
  `ci-action.yaml` (A).
- The usual weakness of B, silent drift of the copy, is removed by the mirror test, and the case
  table is shared through `tests/cases.json` so a new case is one row.
- Cost accepted: about 190 duplicated lines, and a shared `tests/cases.json` plus
  `scripts/load-cases.sh` (about 30 lines) to maintain.

No open decision remains.

## 7. Implementation order

One branch and PR per row (`CLAUDE.md` workflow). Each PR keeps `make format`, `make lint` and
`bats tests/bats/` green. The action itself and the workflows cannot run locally: the PR
descriptions must say that CI was not awaited.

| PR  | Branch                      | Content                                                                                                                                                                                                                                                                                                        | Fixes                     |
| --- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| 1   | `test/cases-table`          | Move the failure cases of `ci-action.yaml` to `tests/cases.json` with `scripts/load-cases.sh` and `test_load_cases.bats`, add the headline cases (placeholder version, twine, pyright, `--no-sources`, uv config). G2 is expected to fail until PR 4: land that row skipped with a comment, enable it in PR 4. | G6                        |
| 2   | `refactor/script-contracts` | `lib.sh` validators and annotations, `python -I`, `check_types.sh` contract, `py.typed` wheel only, version helper.                                                                                                                                                                                            | G4, G5, G9, G10, G11, G12 |
| 3   | `chore/make-test-shell`     | `make test-shell`, `ci-shell.yaml` cleanup.                                                                                                                                                                                                                                                                    | G13                       |
| 4   | `feat/verify-script`        | `verify.sh` and `test_verify.bats`; `action.yaml` reduced to setup, verify, summary; unique work directories; install outside the workspace; `dist-type: both`; README, CONTRIBUTING and `CLAUDE.md` updates; enable the cases of PR 1. The only PR that changes the public API.                               | G1, G2, G3, G15           |
| 5   | `ci/nightly-mirror`         | Rewrite `nightly-test-released.yaml` as a mirror of the new `ci-action.yaml` with `load-cases.sh released`, add `test_workflow_mirror.bats`, add `test-latest-tools` to the schedule of `ci.yaml`.                                                                                                             | G7, G8                    |
| 6   | `docs/readme-v0-1-0`        | README details (`checkout@v7`, `fetch-depth: 0`, troubleshooting, `test_readme.bats`), migration table.                                                                                                                                                                                                        | G14, P13                  |
| 7   | `chore/release-v0-1-0`      | Tag `v0.1.0` (exact tag, no floating tag). Then bump the pin of the mirror, flip the `released` flags, shrink the allow-list.                                                                                                                                                                                  | P11                       |

## 8. Acceptance criteria

The target state is reached when:

- P1 to P13 hold, each backed by a bats test or a CI job in 3.6.
- `action.yaml` has three steps, none with more than one script call, no input interpolated in
  `run:`, and its inputs match the README table (checked by `test_readme.bats`).
- `PACKAGE_NAME=<pkg> bash scripts/verify.sh` runs the full verification locally.
- Each of G1 to G12 has a test that fails on the old behaviour (bats or a `ci-action.yaml` case).
- `nightly-test-released.yaml` mirrors `ci-action.yaml` (checked by `test_workflow_mirror.bats`),
  and both read the same `tests/cases.json`; a release edits one pinned SHA and the `released`
  flags.
- CI proves, end to end, that placeholder version, twine, missing marker, missing extra, missing
  dependency, wrong names and type incompleteness each fail the action, and that stale `dist/`,
  `[tool.uv]` config and `[tool.uv.sources]` do not.

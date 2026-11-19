# CLAUDE.md

Guidance for coding agents working in this repository.

## Repository purpose

A GitHub composite action (`action.yaml`) that builds a Python package with `uv build` and verifies
the resulting wheel and sdist: name, version, `py.typed` marker and extras in the core metadata,
`twine check`, a clean install with its direct dependencies, the import, and type completeness
(pyright). All the logic lives in `scripts/*.sh` (bash, must work on GNU/Linux and BSD/macOS;
Windows is not supported and not tested) and is tested with
[bats](https://github.com/bats-core/bats-core) in `tests/bats/`: `verify.sh` (the entry point of
the action, also run locally with `PACKAGE_NAME=<pkg> bash scripts/verify.sh`), `lib.sh`
(shared helpers), `check_dist.sh`, `check_install.sh` and `check_types.sh`. Only `verify.sh` is
executable: the others are libraries sourced by it and called as functions with explicit
arguments. `action.yaml` only wires the inputs to `verify.sh`.

`src/myproject/` and `pyproject.toml` are a small dummy Python package
used as the fixture that the action builds and verifies in CI. They are not part of the action. The
`dist/` directory holds local build output and is git-ignored. `review/target_state.md` is a
maintainer review of the design (the properties P1 to P14 and the problems found); it is not part
of the action.

## Environment

- Use the `Makefile`; run `make help` to list targets. `make install-tools` installs the lint and
  format tools.
- Do not edit `.make/`: it is a shared directory of makefiles synced by
  `bot-sync-shared-makefile.yaml`. Change the root `Makefile` instead.
- Run `make format` and `make lint` before committing. Fix what they report instead of disabling
  rules.
- Run the shell tests with `make test-shell` or `bats tests/bats/` (install `bats-core` with
  `make install-bats` if missing). Some workflows and the action itself cannot be run locally; say
  so in the PR instead of claiming they pass.

## Git workflow

- One branch and one PR per logical change, branched from an up-to-date `main`. Never commit or
  push to `main`.
- Name branches `<type>/<short-description>` in kebab-case, with type one of: `feat`, `bugfix`,
  `hotfix`, `docs`, `refactor`, `perf`, `test`, `chore`, `ci`.
- Write commit messages and PR titles as a short imperative sentence starting with a verb such as
  `Add`, `Fix`, `Update`, `Remove` or `Improve`. Do not use conventional-commit prefixes like
  `docs:` or `feat:` (the type prefix is only for branch names). The squash-merge appends the PR
  number, so do not add one.
- PR descriptions cover what changed, what was deliberately left alone, and any behaviour change.
- On conflicts with `main`, merge `origin/main` into the branch; do not rebase and force-push.
- Update `README.md` when inputs, behaviour, or workflows change.
- Releases are immutable exact version tags (`v1.9`, ...). Do not create or move floating tags
  (`v1`, `latest`) and do not document them as an option.

## Action rules (`action.yaml`)

- Keep input names, defaults, and descriptions consistent with `README.md`. Renaming or removing
  an input is a breaking change and must be flagged.
- Pass inputs to scripts through `env:`, never by interpolating them in `run:`.
- Every `run:` step sets `shell: bash`, starts with `set -euo pipefail`, and fails with a clear
  `❌` message.
- Call helper scripts through `"$GITHUB_ACTION_PATH/scripts/<name>.sh"`, never a relative path, so
  they resolve when the action is used from another repository.
- Pin third-party actions in workflows and in `action.yaml` to commit SHAs with a
  `# ratchet:<owner>/<repo>@<tag>` comment, never to tags or branches.
- Workflows use least-privilege `permissions` and set `timeout-minutes` on jobs.
- Only depend on what the action ships: `action.yaml` and the scripts it calls through
  `"$GITHUB_ACTION_PATH/scripts/"`. Never make the action read tests, `src/`, `review/` or other
  repo files, because they are not part of what a user of the action should rely on. When the action
  starts using a new file, say so in the PR. There is no `.gitattributes` `export-ignore`: the
  whole repository is checked out when the action is used from another repository.

## Shell script rules (`scripts/*.sh`)

- Must stay portable between GNU and BSD tools (`sed`, `tar`, `grep`, etc.).
- Keep logic in small functions so each can be unit tested; the main flow must be skippable when
  the script is sourced by tests.
- Quote all variables; validate inputs early with clear error messages and a non-zero exit code.
- Keep the header comment (description, usage, arguments, exit codes) in sync with the script.
- Code must pass `shellcheck` and `shfmt` via `make lint` / `make format`.
- A function that can fail is followed by an explicit `return 1` on failure
  (`cmd || { echo "❌ ..."; return 1; }`). Never rely on `set -e`: a caller in an `||` list turns it
  off.

## Workflow structure (`.github/workflows/`)

Files are prefixed by role:

- `ci.yaml`: entry point for pull requests, pushes to `main`, a nightly schedule and manual runs. It
  holds no steps, only jobs that call the reusable `ci-*.yaml` workflows below.
  - `ci-format.yaml`: shell, Markdown and YAML lint/format checks.
  - `ci-shell.yaml`: bats tests on the OS matrix.
  - `ci-shell-bash32.yaml`: bats tests on macOS with the system bash 3.2.
  - `ci-action.yaml`: one file that tests both versions of the action, selected by the boolean
    input `use-released` (default `false`). `ci.yaml` calls it with `false`: the action from this
    checkout (`uses: ./`), i.e. the version not released yet. General behaviour (`test`) runs on
    the Python/OS matrix; the edge cases run on one runner: every package extra, and the failure
    and edge cases of `tests/cases.json` (one row per case: inputs, optional `setup` snippet,
    expected outcome). Add a case as a new row. The `test-latest-tools` job (latest twine and
    pyright) only runs on the schedule of `ci.yaml`.
- `nightly.yaml`: nightly entry point (schedule and manual runs) that calls `ci-action.yaml` with
  `use-released: true`, which runs the latest released action (pinned SHA) with the rows flagged
  `"released": true` in `tests/cases.json`. On a release, bump the pinned SHA (every
  `durandtibo/verify-uv-build-action@` line of `ci-action.yaml`), flip the `released` flags, give
  the released steps the new inputs and remove the `if: ${{ !inputs.use-released }}` of the jobs
  that only ran on the local action. `tests/check_action_case.sh` holds the assertions shared by
  the local and released runs.
- `ci-verify-workflows.yaml`: lints the workflow files themselves. It has its own triggers and is not
  called from `ci.yaml`, so it can be a required check.
- `lib-get-test-matrix.yaml`, `lib-get-package-extras.yaml`: reusable workflows that load the shared
  Python/OS matrix and the package extras once; callers pass them down through inputs.
- `bot-*.yaml`: scheduled automation that opens PRs or acts on runs (format files, pin actions,
  sync the shared `.make` subtree, cancel stale queued runs).
- `security-*.yaml`: dependency review and OSSF Scorecard.

Conventions:

- Set `permissions` on every job (including jobs that call a reusable workflow). Every workflow
  has `permissions: {}` at the workflow level (it grants nothing), never a grant.
- Each `ci-*` check is a `workflow_call` workflow that also has `workflow_dispatch`, so it can be
  run alone.
  Add a new check as a new `ci-<name>.yaml` plus a job in `ci.yaml`.
- Put `make` targets in the steps rather than duplicating commands, so local runs and CI match.
- Start each file with a comment saying what it does, and update it when the behaviour changes.

## Tests

- Each script in `scripts/` has its own `tests/bats/test_<script_name>.bats` file.
- One behaviour per test; build small throwaway wheels/sdists or mock external commands rather than
  calling the network.
- Cover success, failure, and edge cases (missing extras, empty lists, missing or invalid files).
- Every bug fix needs a regression test that fails without the fix.
- If a check fails for a real reason, report it rather than weakening the test.
- Changes to `verify.sh` are tested with `uv`/`uvx` mocked on `PATH` (`tests/bats/test_verify.bats`).
- Changes to `action.yaml` behaviour are covered by the `ci-action.yaml` matrix; extend it when
  adding an input or a check.

## Testing strategy

The strategy is the same for all the action repositories of `durandtibo`. The properties of this
action (P1 to P14) are in `review/target_state.md`. The action cases are the rows of
`tests/cases.json`, read by `ci-action.yaml`.

Three levels:

1. **Code**: each script or function, tested alone with mocks (bats). It covers the logic and every
   edge case. No network, no GitHub.
2. **Local action**: the action from this checkout (`uses: ./`) in a real workflow
   (`ci-action.yaml`).
3. **Released action**: the latest stable release (`uses: durandtibo/verify-uv-build-action@<sha>`),
   run nightly with the cases flagged `"released": true` (`nightly.yaml` calls `ci-action.yaml` with
   `use-released: true`). Never run it on pull requests.

Rules:

- Test a behaviour at the cheapest level that can show it. The action tests (levels 2 and 3) check
  the contract and the wiring: inputs reach the script, outputs are set, the action fails on an
  invalid input. Do not re-test a script's logic there; add it to level 1.
- Split the action tests in two. **General behaviour** (the default usage, job `test`) runs on the
  full matrix: the OS and Python versions. **Edge cases** (one input, one invalid value, an unusual
  file, every package extra) run on one runner (`ubuntu-latest`) and do not cross the Python
  matrix. There is no reduced matrix on pull requests: the same matrix runs on pull requests,
  pushes and the schedule.
- Never write an OS or a Python version in a workflow: read the lists from
  `durandtibo/workflow-config-action` through `lib-get-test-matrix.yaml`.
- The cases are a JSON table (a new case is a row, not a job). A row has no `"released": true` until
  the last release has the feature; the released run skips those rows.
- Every input has a case with an invalid value that asserts the action failed in the validation: it
  can only fail if the input reached the script, so it proves the wiring. Assert the value or the
  format of outputs, never just print them.
- One file, two versions: each job has a step `uses: ./` with `if: ${{ !inputs.use-released }}` and
  a step with the pinned release with `if: ${{ inputs.use-released }}`, and one verify step that
  reads `steps.local.outputs.x || steps.released.outputs.x`. A job that tests a feature the last
  release does not have runs on the local action only.
- Failure paths use `continue-on-error: true`, an `id`, and a step that asserts `steps.<id>.outcome`.
  Assert an id or an exact output, not a message. A negative test needs a positive run on the same
  runner before it, so it cannot pass for the wrong reason.
- Tests have no side effects outside the runner: throwaway files and copies of the fixture. If
  something cannot be tested in CI, write down which check covers it.
- Check the action does not depend on a file outside `action.yaml` and `scripts/`: `uses: ./` runs
  the whole checkout and hides a missing or misplaced file, so the released run (level 3) is the
  check that the shipped files are enough.
- Set `timeout-minutes` and `fail-fast: false` on matrix jobs. Put assertions shared by the local
  and released runs in one script, not in two workflows.
- Keep the README inputs and outputs in step with `action.yaml` (`tests/bats/test_readme.bats`).

## Reporting

- State which checks ran (`make lint`, `make format`, `bats tests/bats/`) and which did not.
- Note that CI was not awaited.
- Report failures that already exist on `main` rather than hiding them.

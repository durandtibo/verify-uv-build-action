# CLAUDE.md

Guidance for coding agents working in this repository.

## Repository purpose

A GitHub composite action (`action.yaml`) that builds a Python package with `uv build` and verifies
the resulting wheel and sdist: name, version, `py.typed` marker and extras in the core metadata,
`twine check`, a clean install with its direct dependencies, the import, and type completeness
(pyright). All the logic lives in `scripts/*.sh` (bash, must work on GNU/Linux and BSD/macOS) and is
tested with [bats](https://github.com/bats-core/bats-core) in `tests/bats/`: `verify.sh` (the entry
point of the action, also run locally with `PACKAGE_NAME=<pkg> bash scripts/verify.sh`), `lib.sh`
(shared helpers), `check_dist.sh`, `check_install.sh` and `check_types.sh`. Only `verify.sh` is
executable: the others are libraries sourced by it and called as functions with explicit
arguments. `action.yaml` only wires the inputs to `verify.sh`.

`src/myproject/` and `pyproject.toml` are a small dummy Python package
used as the fixture that the action builds and verifies in CI. They are not part of the action. The
`dist/` directory holds local build output and is git-ignored.

## Environment

- Use the `Makefile`; run `make help` to list targets. `make install-tools` installs the lint and
  format tools.
- Do not edit `.make/`: it is a shared directory of makefiles shared across repositories. Change
  the root `Makefile` instead.
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

## Shell script rules (`scripts/*.sh`)

- Must stay portable between GNU and BSD tools (`sed`, `tar`, `grep`, etc.).
- Keep logic in small functions so each can be unit tested; the main flow must be skippable when
  the script is sourced by tests.
- Quote all variables; validate inputs early with clear error messages and a non-zero exit code.
- Keep the header comment (description, usage, arguments, exit codes) in sync with the script.
- Code must pass `shellcheck` and `shfmt` via `make lint` / `make format`.

## Workflow structure (`.github/workflows/`)

Files are prefixed by role:

- `ci.yaml`: entry point for pull requests, pushes to `main`, a nightly schedule and manual runs. It
  holds no steps, only jobs that call the reusable `ci-*.yaml` workflows below.
  - `ci-format.yaml`: shell, Markdown and YAML lint/format checks.
  - `ci-shell.yaml`: bats tests on the OS matrix.
  - `ci-shell-bash32.yaml`: bats tests on macOS with the system bash 3.2.
  - `ci-action.yaml`: runs the action from this checkout (`uses: ./`), i.e. the version not
    released yet, across the Python/OS matrix with every package extra, and runs the failure and
    edge cases of `tests/cases.json` (one row per case: inputs, optional `setup` snippet, expected
    outcome). `scripts/load-cases.sh` turns the table into a matrix. Add a case as a new row.
- `nightly.yaml`: nightly entry point (schedule and manual runs) that calls
  `nightly-test-released.yaml`, a mirror of `ci-action.yaml` that runs the cases flagged
  `"released": true` in `tests/cases.json` against the latest released action.
  `tests/bats/test_workflow_mirror.bats` fails when the two drift: change `ci-action.yaml` first,
  then mirror it. On a release, bump the pinned SHA, flip the `released` flags and shrink the
  allow-list of that test. The `test-latest-tools` job of `ci-action.yaml` (latest twine and
  pyright) only runs on the schedule of `ci.yaml`.
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
- Each `ci-*` and `nightly-test-*` check is a `workflow_call` workflow that also has
  `workflow_dispatch`, so it can be run alone.
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

## Reporting

- State which checks ran (`make lint`, `make format`, `bats tests/bats/`) and which did not.
- Note that CI was not awaited.
- Report failures that already exist on `main` rather than hiding them.

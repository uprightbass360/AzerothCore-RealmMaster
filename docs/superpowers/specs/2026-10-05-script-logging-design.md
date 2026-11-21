# Script run logs and debug mode — design

Date: 2026-10-05
Status: approved in conversation; awaiting spec review

## Goal

Every run of a RealmMaster command leaves a log file a user can attach to an
issue, and one switch (`--debug` / `RM_DEBUG=1`) adds detailed debug output
across all shell scripts. Normal terminal output stays as it is today.

Motivation: community bug reports arrive as terminal copy-pastes that lose
formatting and context, and failures often need a re-run plus several
`docker logs` round-trips to diagnose. A community user also asked for logs
written under a `logs/` folder.

## Scope

Phase 1 (this spec): a shared run-log library, adopted by the top-level
commands and the helpers users run by hand; bash-level debug tracing for every
bash script without editing them; a `debug` message function for incremental
use; tests and docs.

Phase 2 (follow-ups, separate changes): debug passthrough into the scripts that
run inside containers, and real `debug` messages at key decision points.

Out of scope: rewriting existing scripts' output helpers (`info`/`warn`/...),
structured (JSON) logs, shipping logs anywhere off the host.

## What a run produces

- Location: `logs/` at the repo root, gitignored. Separate from
  `storage/logs`, which holds the containers' own logs.
- One file per top-level run: `logs/<command>-<YYYYMMDD-HHMMSS>.log`
  (e.g. `logs/deploy-20261005-143012.log`). If that name exists (two runs in
  the same second), a `-2`, `-3`, ... suffix is added.
- `logs/latest.log`: symlink to the most recent run's file (any command).
- Header:
  - command, arguments (after flag stripping), host, user, start time (local
    and UTC);
  - repo commit (`git rev-parse --short HEAD`) and whether the working tree
    has local changes; "not a git checkout" if none;
  - key `.env` facts (values as written in `.env`, never secrets):
    `COMPOSE_PROJECT_NAME`, `STACK_IMAGE_MODE`, `STACK_SOURCE_VARIANT`,
    `MODULE_PLAYERBOTS`, `STORAGE_PATH`, `STORAGE_PATH_LOCAL`, the
    `AC_*_IMAGE*` values, and the number of `MODULE_*=1` flags;
  - `docker --version` and `docker compose version` (or "not found").
- Body: everything the run prints to stdout and stderr (the entry script and
  everything it calls), with ANSI escape sequences removed.
- Debug mode adds, to the file only:
  - a bash trace of every command in every bash script, prefixed
    `+ <file>:<line>: `;
  - `debug` messages, prefixed `[debug] <file>:<line>: `.
- Footer: exit code, duration, end time. If the exit code is non-zero, for
  each container of the compose project that exited non-zero or is
  restarting: its name, state and the last 50 lines of `docker logs`. In debug
  mode the same is collected for every container of the project, whatever the
  exit code. The project is `COMPOSE_PROJECT_NAME` from `.env`; if docker is
  unavailable this section says so and is skipped.

## Secrets

Before anything is written to the file, the values of every `.env` variable
whose name contains `PASSWORD`, `TOKEN`, `SECRET` or `KEY` (case-insensitive)
are replaced with `***`, wherever they appear on a line. This is required
because debug traces print expanded commands (e.g. `mysql -p<password>`).
Values shorter than 4 characters are not masked, because masking them would
mangle ordinary text; such values are unsafe as secrets anyway. The terminal is not filtered: it shows
what it shows today.

- An unquoted `.env` value ends at an inline comment (whitespace then `#`); a
  quoted value is exactly what is inside the quotes.
- The header's `Command:` line masks the value of every option whose name
  contains `pass`, `token`, `secret` or `key` (any case), and of `-p` (the
  backup scripts' password): `--mysql-password ***`, `--token=***`,
  `-p ***`. Option names stay visible. Only the header is masked this way;
  an option value the script prints, or that a debug trace shows, is masked
  only if it is also in `.env`.
- The writer reads `.env` again at EOF. If the run added secrets (setup.sh
  writes a new `.env`, so a password given as an argument or at a prompt
  first appears there), the whole file is rewritten with them masked (temp
  file in `logs/`, then renamed over the log, keeping its mode and owner). If
  that fails the writer prints one line on stderr and still exits 0.
- `logs/` is created `0700` (an existing one owned by the user is set to
  `0700`) and every log file is `0600`: a log can hold values that aren't in
  `.env`, such as a remote host's password typed at a prompt.
- When a command runs as root (sudo), `logs/`, the new file and `latest.log`
  are handed to `SUDO_UID:SUDO_GID` (else to the repo's owner), so later runs
  as the user can still write logs.

## Retention and opt-out

- Retention is per command: before a run writes its log, files of the same
  command beyond the newest `LOG_KEEP_RUNS - 1` are deleted, so the new one
  makes `LOG_KEEP_RUNS` (default 30, from the environment, falling back to `.env`, then 30). A frequently run command can't push other commands'
  logs out.
- `RM_LOG=0` (environment) or `--no-log` (argument) disables logging for that
  run: no file, no tracing; `--debug` without logging is ignored with a one-line
  notice on stderr.
- Read-only commands (`status.sh`, `changelog.sh`) only write a log when
  `--debug` is given. Other commands always log.

## How it works

### `scripts/bash/lib/run-log.sh`

Sourced by each adopting script. It finds the repo root from its own location
(`<lib>/../../..`), not from the caller's variables (entry scripts name theirs
`ROOT_DIR`, `PROJECT_DIR`, `PROJECT_ROOT` or `SCRIPT_DIR`).

Public function: `run_log_start <command-name> [--read-only] -- "$@"`. After it
returns, `RUN_LOG_ARGS` holds the arguments with `--debug` and `--no-log`
removed; the caller continues with `set -- "${RUN_LOG_ARGS[@]}"`, so no
existing argument parser has to learn the new flags. (`--read-only` is the
option described under Retention, for status.sh and changelog.sh.)

`run_log_start` steps:

1. Strip `--debug` / `--no-log` from the arguments into `RUN_LOG_ARGS`;
   `--debug` sets `RM_DEBUG=1`.
2. Nesting guard: if `RM_RUN_LOG` is already set (a parent command opened a
   log), do nothing more. The child's output already flows into the parent's
   log through the inherited stdout/stderr, and tracing is inherited too.
3. Opt-out / read-only checks as above.
4. Create `logs/`, prune old files of this command, pick the file name,
   `export RM_RUN_LOG=<file>`.
5. Start one writer process that reads a FIFO-backed file descriptor, strips
   ANSI codes, masks secrets, and appends to the file; write the header
   through it. Check that the writer is still alive (if not: remove the
   file, no log), and only then point `logs/latest.log` at the file, so it
   never dangles. Redirect stdout through
   `tee` to the original stdout and the writer; redirect stderr through `tee`
   to the original stderr and the writer.
6. Debug mode: open a dedicated trace descriptor (its own `tee -p` into the
   writer), set `BASH_XTRACEFD` to it, set `PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '`,
   `set -x`, and export `BASH_XTRACEFD`, `PS4`, `RM_DEBUG` and `BASH_ENV`
   pointing at `scripts/bash/lib/run-log-trace.sh` (which runs `set -x`), so
   every child bash process traces into the log as well. Only xtrace is passed
   down: exporting `SHELLOPTS` would also pass the entry script's
   errexit/nounset/pipefail to every child.
7. Install an EXIT trap that writes the footer, then closes the descriptors and
   waits for the writer to flush, so the file is complete when the command
   returns. No entry script sets its own EXIT trap today; if one does in the
   future, it must call `run_log_finish` from its trap (documented in the
   library).

### `debug` function

`debug "message"`: when `RM_DEBUG=1` and a log is open, writes
`[debug] <file>:<line>: message` to the log only; otherwise does nothing and
returns 0. `run_log_start` exports it (`export -f debug`) so child bash
scripts have it without sourcing anything. `lib/common.sh` defines the same
no-op-capable `debug` only if one isn't defined yet, so scripts that use it
keep working when run without logging (they run under `set -e`).

### Adoption

Two lines near the top of each adopting script, after its root directory is
known and before its argument parsing:

```bash
source "<path to>/scripts/bash/lib/run-log.sh"
run_log_start deploy -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
```

Adopting scripts:

- Top-level commands: `build.sh`, `deploy.sh`, `setup.sh`, `cleanup.sh`,
  `modules.sh`, `update-latest.sh`, and (read-only) `status.sh`,
  `changelog.sh`.
- Helpers users run directly (per the docs): `scripts/bash/backup-export.sh`,
  `scripts/bash/backup-import.sh`, `scripts/bash/migrate-stack.sh`,
  `scripts/bash/repair-storage-permissions.sh`. When called by a top-level
  command they hit the nesting guard and log into the parent's file.

Every other script needs no change: its output reaches the log through the
inherited stdout/stderr, and debug mode traces it through the exported
`BASH_ENV`.

## Known limits

- Terminal output and trace lines travel through separate descriptors, so
  their relative order in the file can be slightly off. Output lines and trace
  lines are each in order.
- stdout and stderr also travel through separate tees, so their relative
  order can be slightly off, on the terminal as well as in the file.
- In debug mode each `debug` call shows its own `local -` / `set +x` trace
  lines before the `[debug]` line.
- While logging, Docker Compose writes plain progress lines instead of its
  animated display (its stdout is a pipe).
- Scripts running inside containers are separate processes and are not traced;
  their output is covered by the failure-time `docker logs` collection
  (phase 2 adds debug passthrough).
- Python helpers are not traced; their output is captured, and they can read
  `RM_DEBUG` to print more (phase 2).
- Commands that replace the shell (`exec`) keep logging, since descriptors are
  inherited, but the footer is only written if the original process exits
  normally.

## Testing

New `scripts/bash/tests/test-run-log.sh`, run by CI with the other suites.
It uses a temp repo layout (copy of `lib/run-log.sh`, a fake `.env`, fake
entry and child scripts); no docker needed (docker calls are stubbed with a
shim on `PATH`).

- A run creates `logs/<command>-<timestamp>.log` and `logs/latest.log` with
  header, body and footer; the footer has the right exit code on success and on
  failure (`exit 3`, and a failing command under `set -e`).
- ANSI codes are removed in the file and still reach the terminal; stderr
  output still goes to stderr.
- Secret values from `.env` never appear in the file, including in debug
  traces of a command that uses them; short values are left alone.
- `--debug` traces a child script's commands (`+ child.sh:<line>:`) into the
  file and not to the terminal; without `--debug` there are no trace lines.
- `--debug` and `--no-log` are removed from the arguments the script sees.
- A nested run (an adopting script calling another) writes one log, containing
  both.
- Retention keeps the newest `LOG_KEEP_RUNS` files per command and never
  touches other commands' files.
- `RM_LOG=0` and `--no-log` write nothing; read-only commands write nothing
  without `--debug`.
- `debug` writes `[debug]` lines in debug mode, writes nothing otherwise, and
  never fails a `set -e` script, including one run without logging.
- Failure footer: with a docker shim reporting one exited-1 container, its log
  tail is included; with docker missing, the section says so.

Manual check: `./deploy.sh --debug` and a failing `./build.sh` on a real stack;
review the files for completeness and leaked secrets.

## Docs and config

- `docs/TROUBLESHOOTING.md`: "Logs and debugging" section (where logs are,
  attach `logs/latest.log`, re-run with `--debug`, `--no-log`, retention).
- Each adopting script's `--help`: one line for `--debug` / `--no-log`.
- `.env.template`, `.env.prebuilt`: `LOG_KEEP_RUNS=30` with a comment.
- `.gitignore`: `logs/`.

## Phase 2 (follow-ups)

- Container scripts: pass `RM_DEBUG` through the compose environment of
  ac-db-import, ac-db-guard, ac-backup and ac-modules; those scripts turn on
  `set -x` when it is set.
- `debug` messages at key decision points: build.sh's core-update decision,
  stage-modules' profile choice, manage-modules' install/skip/hold per
  module, db-import's SQL source and restore choice.
- Python helpers: read `RM_DEBUG` and print extra detail.

# Script Run Logs and Debug Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every RealmMaster command run leaves a log file under `logs/`, and `--debug` / `RM_DEBUG=1` adds a full bash trace plus `debug` messages from every bash script, without changing what the terminal shows.

**Architecture:** A sourced library (`scripts/bash/lib/run-log.sh`) opens the log at the top of each adopting command and copies stdout/stderr into it through one Python writer process (`scripts/python/run_log_writer.py`) that strips ANSI codes and masks `.env` secrets. Debug mode exports `SHELLOPTS`/`BASH_XTRACEFD`/`PS4` so every child bash script traces into the log with no edits. An EXIT trap writes the footer (exit code, duration, failed containers' `docker logs` tails); INT/TERM are turned into exits so the trap always runs.

**Tech Stack:** bash ≥ 4.4 (`local -`, `exec {var}>`, `wait` on process substitutions not needed), Python 3 standard library, existing bash test style (`scripts/bash/tests/*.sh`), Python `unittest` (`python3 -m unittest discover -s scripts/python/tests -t scripts/python`).

**Spec:** `docs/superpowers/specs/2026-10-05-script-logging-design.md`

All code in Tasks 1–2 was prototyped and run before this plan was written: `test-run-log.sh` passes 63/63, the writer's unit tests 11/11, shellcheck is clean. Copy it verbatim.

## Global Constraints

- Work in the worktree `/home/upb/src/AzerothCore-RealmMaster.wt-logging` (branch `feat/script-logging`). Never touch `/home/upb/src/AzerothCore-RealmMaster` or `~/src/rm-prebuilt-test`.
- Log location `logs/` at the repo root (gitignored); file name `logs/<command>-<YYYYMMDD-HHMMSS>.log` (`-2`, `-3`, … on collision); `logs/latest.log` symlink.
- Secrets: values (≥ 4 chars, not containing `${`) of `.env` names containing PASSWORD, TOKEN, SECRET or KEY (case-insensitive) become `***` in the file. The terminal is never filtered.
- Retention per command: `LOG_KEEP_RUNS` (env, then `.env`, default 30).
- Opt-out: `RM_LOG=0` or `--no-log`. Read-only commands (`status.sh`, `changelog.sh`) log only with `--debug`.
- `--debug` and `--no-log` are stripped before the script's own argument parser runs.
- Logging must never break a command: no python3, unwritable `logs/`, `--no-log` → the command runs normally, without a log.
- No new dependencies. Tests need no docker or network (docker is shimmed).
- Tests: every new test is picked up by CI (`.github/workflows/ci.yml` runs `scripts/bash/tests/*.sh` and the Python suite).
- shellcheck: no new warnings in touched files.
- Commits end with a blank line then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Repo-local git identity is already set in the worktree. Don't push.

## Review Focus

1. Interactive prompts (`read -p` without a trailing newline, e.g. deploy's "Proceed? [y/N]") still appear immediately on the terminal; in the file the prompt may share a line with the next output line — acceptable, but the prompt must not be lost or delayed on screen. (Manual check in Task 3.)
2. A background process started by a command that outlives it (holds the log descriptors): `run_log_finish` must still return within ~5 s (`run_log__wait_pid` polls 50 × 0.1 s) rather than hang. (Covered by design; verify in Task 3's manual smoke that `./deploy.sh` returns promptly.)
3. Nested commands: `update-latest.sh` → `deploy.sh` (after the `exec` removal) must produce one `update-latest-*.log` containing deploy's output, and deploy must not open a second file. (Nesting is tested in Task 2; Task 3's adoption test checks that the `exec` is gone.)
4. `--debug` passed to a command that forwards unknown args (update-latest forwards to deploy): `--debug` is stripped by update-latest, and deploy still runs in debug mode via the exported `RM_DEBUG`/`SHELLOPTS`. (Manual smoke in Task 3.)
5. A log is never created as root in a user's checkout by accident: `logs/` is only written by the host scripts (never mounted into containers). (Static check in Task 3: `logs` does not appear in `docker-compose.yml`.)

---

### Task 1: Log writer (`run_log_writer.py`)

**Files:**
- Create: `scripts/python/run_log_writer.py`
- Test: `scripts/python/tests/test_run_log_writer.py`

**Interfaces:**
- Produces: CLI `python3 scripts/python/run_log_writer.py <log-file> <env-file>` — reads stdin until EOF, appends each cleaned line (+ `\n`) to `<log-file>`, flushing per line; exit 0, or 2 on wrong argument count. Functions `load_secrets(env_path: Path) -> list[str]` (longest first) and `clean_line(line: str, secrets: list[str]) -> str`.

- [ ] **Step 1: Write the failing test** — create `scripts/python/tests/test_run_log_writer.py`:

````python
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from run_log_writer import clean_line, load_secrets

WRITER = Path(__file__).resolve().parents[1] / "run_log_writer.py"


class LoadSecretsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = self.tmp / ".env"

    def write_env(self, text):
        self.env.write_text(text)
        return load_secrets(self.env)

    def test_secret_names_are_matched_case_insensitively(self):
        secrets = self.write_env(
            "MYSQL_ROOT_PASSWORD=hunter22\nGH_TOKEN=tok-1234\nApi_Secret=s3cr3t!\n"
            "SSH_KEY=key-5678\nSERVER_ADDRESS=10.0.0.5\n"
        )
        self.assertEqual(set(secrets), {"hunter22", "tok-1234", "s3cr3t!", "key-5678"})

    def test_short_values_references_and_comments_are_skipped(self):
        secrets = self.write_env(
            "SHORT_TOKEN=abc\nREF_PASSWORD=${MYSQL_ROOT_PASSWORD}\n# OLD_PASSWORD=commented\nEMPTY_KEY=\n"
        )
        self.assertEqual(secrets, [])

    def test_quotes_and_export_are_handled(self):
        secrets = self.write_env("export DB_PASSWORD=\"quoted pw\"\nX_TOKEN='single'\n")
        self.assertEqual(set(secrets), {"quoted pw", "single"})

    def test_longest_first(self):
        secrets = self.write_env("A_PASSWORD=abcd\nB_PASSWORD=abcdefgh\n")
        self.assertEqual(secrets, ["abcdefgh", "abcd"])

    def test_missing_env_file(self):
        self.assertEqual(load_secrets(self.tmp / "nope.env"), [])


class CleanLineTest(unittest.TestCase):
    def test_ansi_codes_are_removed(self):
        self.assertEqual(clean_line("\x1b[0;32mok\x1b[0m done\n", []), "ok done")
        self.assertEqual(clean_line("\x1b[1;33m⚠️  warn\x1b[0m", []), "⚠️  warn")

    def test_carriage_return_keeps_the_final_state(self):
        self.assertEqual(clean_line("10%\r50%\r100%\n", []), "100%")
        self.assertEqual(clean_line("done\r\n", []), "done")

    def test_secrets_are_masked_everywhere_on_the_line(self):
        line = clean_line("mysql -phunter22 -e x; echo hunter22", ["hunter22"])
        self.assertEqual(line, "mysql -p*** -e x; echo ***")

    def test_overlapping_secrets_mask_the_longest(self):
        self.assertEqual(clean_line("pw=abcdefgh", ["abcdefgh", "abcd"]), "pw=***")


class WriterProcessTest(unittest.TestCase):
    def test_appends_cleaned_lines_until_eof(self):
        tmp = Path(tempfile.mkdtemp())
        env = tmp / ".env"
        env.write_text("MYSQL_ROOT_PASSWORD=hunter22\n")
        log = tmp / "run.log"
        log.write_text("header\n")
        subprocess.run(
            [sys.executable, str(WRITER), str(log), str(env)],
            input="\x1b[0;32mone\x1b[0m\ntwo hunter22\nno newline at end",
            text=True, check=True,
        )
        self.assertEqual(log.read_text(), "header\none\ntwo ***\nno newline at end\n")

    def test_usage_error(self):
        result = subprocess.run([sys.executable, str(WRITER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
````

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -p 'test_run_log_writer.py'`
Expected: ERROR, `ModuleNotFoundError: No module named 'run_log_writer'`.

- [ ] **Step 3: Implement** — create `scripts/python/run_log_writer.py` (mode 0755):

````python
#!/usr/bin/env python3
"""Append a run's output to its log file: strip ANSI codes, mask secrets.

Reads stdin until EOF (every writer of the pipe has closed it) and appends
each line to the log file. Used by scripts/bash/lib/run-log.sh; see
docs/superpowers/specs/2026-10-05-script-logging-design.md.

Secrets are the values of .env variables whose name contains PASSWORD,
TOKEN, SECRET or KEY (case-insensitive) and that are at least 4 characters
long; they are replaced with *** wherever they appear.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")
SECRET_NAME_RE = re.compile(r"PASSWORD|TOKEN|SECRET|KEY", re.IGNORECASE)
MIN_SECRET_LEN = 4


def load_secrets(env_path: Path) -> list[str]:
    """Secret values from a .env file, longest first (so longer values win)."""
    secrets: set[str] = set()
    try:
        lines = env_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = name.strip()
        if name.startswith("export "):
            name = name[len("export "):].strip()
        if not SECRET_NAME_RE.search(name):
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        if len(value) < MIN_SECRET_LEN or "${" in value:
            continue
        secrets.add(value)
    return sorted(secrets, key=len, reverse=True)


def clean_line(line: str, secrets: list[str]) -> str:
    """One output line as it should appear in the log file."""
    line = line.rstrip("\n")
    # A terminal redraws a line on \r (progress meters); keep what it ends on.
    if "\r" in line:
        parts = [p for p in line.split("\r") if p]
        line = parts[-1] if parts else ""
    line = ANSI_RE.sub("", line)
    for secret in secrets:
        line = line.replace(secret, "***")
    return line


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: run_log_writer.py <log-file> <env-file>", file=sys.stderr)
        return 2
    log_path, env_path = Path(argv[1]), Path(argv[2])
    secrets = load_secrets(env_path)
    stdin = open(sys.stdin.fileno(), "r", encoding="utf-8", errors="replace", newline="\n", closefd=False)
    with open(log_path, "a", encoding="utf-8") as out:
        for raw in stdin:
            out.write(clean_line(raw, secrets) + "\n")
            out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
````

- [ ] **Step 4: Run the tests**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python`
Expected: all OK (11 new tests plus the existing ones).

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/python/run_log_writer.py
git add scripts/python/run_log_writer.py scripts/python/tests/test_run_log_writer.py
git commit -m "feat(logging): log writer that strips colors and masks secrets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Run-log library, `debug`, `.gitignore`

**Files:**
- Create: `scripts/bash/lib/run-log.sh`
- Modify: `scripts/bash/lib/common.sh` (append the `debug` fallback)
- Modify: `.gitignore` (add `logs/`)
- Test: `scripts/bash/tests/test-run-log.sh`

**Interfaces:**
- Consumes: Task 1's writer CLI.
- Produces:
  - `run_log_start <command-name> [--read-only] -- "$@"` — sets array `RUN_LOG_ARGS` (args without `--debug`/`--no-log`); callers continue with `set -- "${RUN_LOG_ARGS[@]}"`. Must be called at the script's top level (not inside a function), before the script parses arguments.
  - `run_log_finish` — the EXIT trap; scripts that later add their own EXIT trap must call it.
  - `debug "message"` — exported to child bash processes; no-op unless a log is open in debug mode; never fails.
  - Environment while a log is open: `RM_RUN_LOG=<file>`; in debug mode also `RM_DEBUG=1`, `RM_DEBUG_FD`, `BASH_XTRACEFD`, `PS4`, `SHELLOPTS` (exported).
  - `RUN_LOG_ROOT` may be preset (tests); otherwise it is the repo root derived from the library's own path.

- [ ] **Step 1: Write the failing test** — create `scripts/bash/tests/test-run-log.sh` (mode 0755):

````bash
#!/bin/bash
# Tests for scripts/bash/lib/run-log.sh (per-run log files and debug mode).
# Builds a throwaway repo layout in a temp dir (the library, the writer, a
# .env, fake entry and child scripts) and runs it there. Docker is replaced by
# a shim on PATH. No real docker or network needed.
#
# Usage: scripts/bash/tests/test-run-log.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }
has(){ grep -qF -- "$2" "$1" && echo yes || echo no; }

# --- fake repo -------------------------------------------------------------
R="$WORK/repo"
mkdir -p "$R/scripts/bash/lib" "$R/scripts/python" "$WORK/bin"
cp "$REPO_ROOT/scripts/bash/lib/run-log.sh" "$R/scripts/bash/lib/"
cp "$REPO_ROOT/scripts/python/run_log_writer.py" "$R/scripts/python/"
cat > "$R/.env" <<'EOF'
COMPOSE_PROJECT_NAME=rm-test
STACK_IMAGE_MODE=modules
MYSQL_ROOT_PASSWORD=sup3rs3cret
SHORT_TOKEN=abc
MODULE_A=1
MODULE_B=0
EOF

cat > "$R/child.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
debug "child decided X"
echo "child out sup3rs3cret"
echo "child err" >&2
EOF

# entry.sh <name>: a command adopting the library.
cat > "$R/entry.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/bash/lib/run-log.sh"
run_log_start "${ENTRY_NAME:-entry}" ${ENTRY_READ_ONLY:+--read-only} -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
echo "args: $*"
printf '\033[0;32mgreen\033[0m\n'
printf 'progress 10%%\rprogress 100%%\n'
pw_cmd="mysql -psup3rs3cret -u abc"
echo "short token abc stays"
debug "entry decided Y"
"$ROOT_DIR/child.sh"
[ "${NESTED:-0}" = 1 ] && ENTRY_NAME=inner NESTED=0 "$ROOT_DIR/entry.sh" inner-arg
[ -n "${EXIT_CODE:-}" ] && exit "$EXIT_CODE"
[ "${FAIL_CMD:-0}" = 1 ] && false
echo "end"
EOF
chmod +x "$R/child.sh" "$R/entry.sh"

# Docker shim: one project container exited 1, one running, one exited 0.
cat > "$WORK/bin/docker" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "--version "*) echo "Docker version 99.0" ;;
  "compose version") echo "Docker Compose version v9" ;;
  "ps -a") printf 'ac-bad|exited|Exited (1) 2 minutes ago\nac-good|running|Up 5 minutes\nac-done|exited|Exited (0) 1 minute ago\n' ;;
  "logs --tail") echo "log line from $4" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH"

reset_logs(){ rm -rf "$R/logs"; }
log_file(){ readlink -f "$R/logs/latest.log"; }
# run_entry [env...] -- [args...]: runs entry.sh; sets RC, output in $WORK/out and $WORK/err.
run_entry(){
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  env -u RM_RUN_LOG -u RM_DEBUG -u RM_LOG "${envs[@]}" "$R/entry.sh" "$@" >"$WORK/out" 2>"$WORK/err"
  RC=$?
}
# count_logs <glob>: files in logs/ matching the glob.
count_logs(){ find "$R/logs" -maxdepth 1 -name "$1" 2>/dev/null | wc -l; }

echo "normal run"
reset_logs
run_entry -- --flag value
F="$(log_file)"
check "exit status" "$RC" "0"
check "log file named <command>-<timestamp>.log" "$(basename "$F" | grep -cE '^entry-[0-9]{8}-[0-9]{6}\.log$')" "1"
check "latest.log points at it" "$([ -L "$R/logs/latest.log" ] && echo yes)" "yes"
check "header: command and args" "$(has "$F" 'Command:   entry --flag value')" "yes"
check "header: .env facts" "$(has "$F" 'STACK_IMAGE_MODE=modules')" "yes"
check "header: enabled module count" "$(has "$F" 'Enabled MODULE_* flags: 1')" "yes"
check "header: docker version" "$(has "$F" 'Docker version 99.0')" "yes"
check "body: stdout" "$(has "$F" 'args: --flag value')" "yes"
check "body: child stdout and stderr" "$(has "$F" 'child err')" "yes"
check "body: colors stripped" "$(grep -c $'\033' "$F")" "0"
check "body: progress collapsed to final state" "$(grep -c 'progress' "$F")" "1"
check "footer: exit code" "$(has "$F" 'exit code 0')" "yes"
check "terminal: colors kept" "$(grep -c $'\033\[0;32m' "$WORK/out")" "1"
check "terminal: stderr stays on stderr" "$(grep -c 'child err' "$WORK/err")" "1"
check "terminal: stdout has no stderr lines" "$(grep -c 'child err' "$WORK/out")" "0"
check "no trace lines without --debug" "$(grep -c '^+ ' "$F")" "0"
check "no [debug] lines without --debug" "$(grep -c '^\[debug\]' "$F")" "0"
check "no container section on success" "$(has "$F" 'container ac-')" "no"

echo "secrets"
check "password masked in output" "$(has "$F" 'child out ***')" "yes"
check "password never in the file" "$(has "$F" 'sup3rs3cret')" "no"
check "short value left alone" "$(has "$F" 'short token abc stays')" "yes"

echo "debug mode"
reset_logs
run_entry -- --debug keep
F="$(log_file)"
check "--debug removed from the script's arguments" "$(has "$F" 'args: keep')" "yes"
check "entry commands traced with file:line" "$(grep -cE '^\+ entry\.sh:[0-9]+: echo' "$F" | awk '{print ($1>0)?"yes":"no"}')" "yes"
check "child commands traced with file:line" "$(grep -cE '^\+ child\.sh:[0-9]+: echo' "$F" | awk '{print ($1>0)?"yes":"no"}')" "yes"
check "[debug] lines from entry and child" "$(grep -cE '^\[debug\] (entry|child)\.sh:[0-9]+: ' "$F")" "2"
check "traced password masked" "$(has "$F" 'sup3rs3cret')" "no"
check "traces stay out of the terminal" "$(grep -c '^+ ' "$WORK/out" "$WORK/err" | awk -F: '{s+=$2} END {print s}')" "0"
check "debug: container logs for all containers" "$(grep -c '^--- container ac-' "$F")" "3"
reset_logs
run_entry RM_DEBUG=1 --
check "RM_DEBUG=1 works like --debug" "$(grep -c '^\[debug\]' "$(log_file)")" "2"

echo "failures"
reset_logs
run_entry EXIT_CODE=3 --
F="$(log_file)"
check "exit status preserved" "$RC" "3"
check "footer: exit code 3" "$(has "$F" 'exit code 3')" "yes"
check "failed container's log included" "$(has "$F" 'log line from ac-bad')" "yes"
check "running container skipped" "$(has "$F" 'ac-good')" "no"
check "exited-0 container skipped" "$(has "$F" 'ac-done')" "no"
reset_logs
run_entry FAIL_CMD=1 --
check "set -e failure exit status" "$RC" "1"
check "set -e failure footer" "$(has "$(log_file)" 'exit code 1')" "yes"
reset_logs
# A PATH with every system tool except docker.
NODOCKER="$WORK/nodocker-bin"
mkdir -p "$NODOCKER"
for tool in /usr/local/bin/* /usr/bin/* /bin/*; do
  name="$(basename "$tool")"
  [ "$name" = docker ] || [ -e "$NODOCKER/$name" ] || ln -s "$tool" "$NODOCKER/$name"
done
run_entry EXIT_CODE=2 PATH="$NODOCKER" --
check "no docker: section says so" "$(has "$(log_file)" 'docker not found; skipped')" "yes"

echo "opt-out and read-only"
reset_logs
run_entry -- --no-log
check "--no-log: command succeeds (child's debug calls included)" "$RC" "0"
check "--no-log: no log written" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "no"
check "--no-log removed from arguments" "$(grep -c 'args: $' "$WORK/out")" "1"
run_entry RM_LOG=0 --
check "RM_LOG=0: command succeeds" "$RC" "0"
check "RM_LOG=0: no log written" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "no"
run_entry -- --no-log --debug
check "--debug with --no-log: notice" "$(grep -c 'ignoring --debug' "$WORK/err")" "1"
run_entry ENTRY_READ_ONLY=1 --
check "read-only command: succeeds without a log" "$RC" "0"
check "read-only command: no log without --debug" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "no"
run_entry ENTRY_READ_ONLY=1 -- --debug
check "read-only command: log with --debug" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "yes"

echo "logging unavailable: the command still runs"
reset_logs
NOPY="$WORK/nopython-bin"
mkdir -p "$NOPY"
for tool in /usr/local/bin/* /usr/bin/* /bin/*; do
  name="$(basename "$tool")"
  case "$name" in python3*) continue ;; esac
  [ -e "$NOPY/$name" ] || ln -s "$tool" "$NOPY/$name"
done
run_entry PATH="$NOPY" --
check "no python3: command succeeds" "$RC" "0"
check "no python3: output intact" "$(grep -c '^end$' "$WORK/out")" "1"
check "no python3: notice" "$(grep -c 'python3 not found' "$WORK/err")" "1"
check "no python3: no log" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "no"
reset_logs
touch "$R/logs"
run_entry --
check "logs/ not creatable: command succeeds" "$RC" "0"
check "logs/ not creatable: notice" "$(grep -c 'running without a log' "$WORK/err")" "1"
rm -f "$R/logs"

echo "nesting"
reset_logs
run_entry NESTED=1 --
check "one log for a nested run" "$(count_logs '*-[0-9]*.log')" "1"
check "inner command's output in the outer log" "$(has "$(log_file)" 'args: inner-arg')" "yes"

echo "retention"
reset_logs
mkdir -p "$R/logs"
for i in 01 02 03 04 05; do touch "$R/logs/entry-20260101-0000$i.log"; done
touch "$R/logs/other-20260101-000000.log"
run_entry LOG_KEEP_RUNS=3 --
check "keeps the newest LOG_KEEP_RUNS of this command" "$(count_logs 'entry-*')" "3"
check "oldest removed" "$([ -e "$R/logs/entry-20260101-000001.log" ] && echo kept || echo gone)" "gone"
check "other commands' logs untouched" "$([ -e "$R/logs/other-20260101-000000.log" ] && echo yes)" "yes"

echo "same-second runs"
reset_logs
run_entry -- ; run_entry -- ; run_entry --
check "three runs, three files" "$(count_logs 'entry-*')" "3"

echo "debug without a log"
cat > "$WORK/plain.sh" <<EOF
#!/bin/bash
set -euo pipefail
source "$R/scripts/bash/lib/run-log.sh"
debug "nobody listens"
echo "still fine"
EOF
chmod +x "$WORK/plain.sh"
check "debug is a no-op under set -e without a log" "$(env -u RM_RUN_LOG -u RM_DEBUG "$WORK/plain.sh" 2>&1)" "still fine"

echo "signals"
reset_logs
cat > "$R/sleeper.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/bash/lib/run-log.sh"
run_log_start sleeper -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
echo "before wait"
sleep 30
EOF
chmod +x "$R/sleeper.sh"
for sig in INT TERM; do
  reset_logs
  result="$(python3 - "$R/sleeper.sh" "$sig" <<'PY'
import os, signal, subprocess, sys, time
script, name = sys.argv[1], sys.argv[2]
p = subprocess.Popen([script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
time.sleep(1.5)
os.killpg(p.pid, getattr(signal, "SIG" + name))
print(p.wait(timeout=15))
PY
)"
  expected=130; [ "$sig" = TERM ] && expected=143
  check "SIG$sig: exit status" "$result" "$expected"
  check "SIG$sig: footer written" "$(has "$(log_file)" "exit code $expected")" "yes"
done

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
````

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/bash/tests/test-run-log.sh`
Expected: fails immediately with `cp: cannot stat '…/scripts/bash/lib/run-log.sh'`.

- [ ] **Step 3: Implement the library** — create `scripts/bash/lib/run-log.sh`:

````bash
#!/bin/bash
# Per-run log files and debug mode for RealmMaster scripts.
# See docs/superpowers/specs/2026-10-05-script-logging-design.md.
#
# Usage, near the top of a command (after its root dir is known, before its
# argument parsing):
#   source "<repo>/scripts/bash/lib/run-log.sh"
#   run_log_start deploy -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
#
# run_log_start strips --debug and --no-log from the arguments (RUN_LOG_ARGS
# holds the rest), opens logs/<command>-<timestamp>.log, and copies stdout and
# stderr into it. --debug (or RM_DEBUG=1) also traces every bash command, in
# this script and every bash script it runs, into the log only. The log is
# finished by an EXIT trap; a script that sets its own EXIT trap must call
# run_log_finish from it.
#
# Environment: RM_LOG=0 disables logging; RM_DEBUG=1 enables debug mode;
# LOG_KEEP_RUNS (or .env) sets how many logs to keep per command (default 30).
# RM_RUN_LOG is set while a log is open; nested commands write into it.

RUN_LOG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_LOG_ROOT="${RUN_LOG_ROOT:-$(cd "$RUN_LOG_LIB_DIR/../../.." && pwd)}"
RUN_LOG_ARGS=()

# debug "message": write a [debug] line to the run log in debug mode; a no-op
# otherwise. Never fails, so it is safe under set -e.
debug(){
  local -
  set +x
  [ "${RM_DEBUG:-0}" = "1" ] && [ -n "${RM_DEBUG_FD:-}" ] || return 0
  printf '[debug] %s:%s: %s\n' "${BASH_SOURCE[1]##*/}" "${BASH_LINENO[0]}" "$*" \
    1>&"$RM_DEBUG_FD" 2>/dev/null || true
  return 0
}

# run_log__env_value KEY: value of KEY from .env (no expansion), else empty.
run_log__env_value(){
  local env_file="$RUN_LOG_ROOT/.env" line
  [ -f "$env_file" ] || return 0
  line="$(grep -E "^${1}=" "$env_file" 2>/dev/null | tail -n1)" || true
  line="${line#*=}"
  line="${line%$'\r'}"
  line="${line#\"}"; line="${line%\"}"
  printf '%s' "$line"
}

run_log__prune(){
  local dir="$1" command="$2" keep="$3" f
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(
    find "$dir" -maxdepth 1 -type f -name "${command}-[0-9]*.log" -printf '%f\n' 2>/dev/null | sort
  )
  local excess=$(( ${#files[@]} - (keep - 1) ))
  local i
  for (( i = 0; i < excess; i++ )); do
    rm -f "$dir/${files[$i]}"
  done
}

run_log__header(){
  local command="$1"; shift
  local commit dirty key enabled
  echo "=== RealmMaster ${command} run ==="
  echo "Command:   ${command} $*"
  echo "Started:   $(date '+%Y-%m-%d %H:%M:%S %Z') ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
  echo "Host/user: $(hostname 2>/dev/null || echo unknown) / $(id -un 2>/dev/null || echo unknown)"
  if commit="$(git -C "$RUN_LOG_ROOT" rev-parse --short HEAD 2>/dev/null)"; then
    dirty=""
    [ -z "$(git -C "$RUN_LOG_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ] || dirty=" (local changes)"
    echo "Repo:      ${commit}${dirty}"
  else
    echo "Repo:      not a git checkout"
  fi
  for key in COMPOSE_PROJECT_NAME STACK_IMAGE_MODE STACK_SOURCE_VARIANT MODULE_PLAYERBOTS \
             STORAGE_PATH STORAGE_PATH_LOCAL; do
    echo "${key}=$(run_log__env_value "$key")"
  done
  if [ -f "$RUN_LOG_ROOT/.env" ]; then
    grep -E '^AC_[A-Z_]*IMAGE[A-Z_]*=' "$RUN_LOG_ROOT/.env" 2>/dev/null || true
    enabled="$(grep -cE '^MODULE_[A-Z0-9_]+=1[[:space:]]*$' "$RUN_LOG_ROOT/.env" 2>/dev/null || true)"
    echo "Enabled MODULE_* flags: ${enabled:-0}"
  else
    echo ".env: not found"
  fi
  echo "Docker:    $(docker --version 2>/dev/null || echo 'not found')"
  echo "Compose:   $(docker compose version 2>/dev/null || echo 'not found')"
  echo "Debug:     ${RM_DEBUG:-0}"
  echo "==="
}

# run_log__container_tails all|failed: name, state and last 50 log lines of
# the compose project's containers (all, or only exited non-zero/restarting).
run_log__container_tails(){
  local which="$1" project name state status
  project="$(run_log__env_value COMPOSE_PROJECT_NAME)"
  if ! command -v docker >/dev/null 2>&1; then
    echo "Container logs: docker not found; skipped"
    return 0
  fi
  [ -n "$project" ] || { echo "Container logs: COMPOSE_PROJECT_NAME not set; skipped"; return 0; }
  local listing
  if ! listing="$(docker ps -a --filter "label=com.docker.compose.project=${project}" \
        --format '{{.Names}}|{{.State}}|{{.Status}}' 2>/dev/null)"; then
    echo "Container logs: docker ps failed; skipped"
    return 0
  fi
  while IFS='|' read -r name state status; do
    [ -n "$name" ] || continue
    if [ "$which" = "failed" ]; then
      case "$state" in
        restarting) ;;
        exited) [[ "$status" == "Exited (0)"* ]] && continue ;;
        *) continue ;;
      esac
    fi
    echo "--- container ${name} (${state}: ${status}), last 50 lines ---"
    docker logs --tail 50 "$name" 2>&1 || echo "(docker logs failed)"
  done <<< "$listing"
}

run_log__wait_pid(){
  local pid="$1" i
  [ -n "$pid" ] || return 0
  for (( i = 0; i < 50; i++ )); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
}

run_log_start(){
  local command="$1"; shift
  # Child scripts may call debug whether or not this run is logged.
  export -f debug
  local read_only=0
  if [ "${1:-}" = "--read-only" ]; then read_only=1; shift; fi
  [ "${1:-}" = "--" ] && shift
  local no_log=0 arg
  RUN_LOG_ARGS=()
  for arg in "$@"; do
    case "$arg" in
      --debug) RM_DEBUG=1 ;;
      --no-log) no_log=1 ;;
      *) RUN_LOG_ARGS+=("$arg") ;;
    esac
  done

  # Nested command: the parent's log already captures us (and its tracing).
  [ -z "${RM_RUN_LOG:-}" ] || return 0

  if [ "$no_log" = "1" ] || [ "${RM_LOG:-1}" = "0" ]; then
    if [ "${RM_DEBUG:-0}" = "1" ]; then
      echo "Note: --debug writes to the run log, which is disabled; ignoring --debug." >&2
    fi
    RM_DEBUG=0
    export RM_LOG=0
    return 0
  fi
  if [ "$read_only" = "1" ] && [ "${RM_DEBUG:-0}" != "1" ]; then
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Note: python3 not found; running without a log." >&2
    return 0
  fi
  local dir="$RUN_LOG_ROOT/logs"
  if ! mkdir -p "$dir" 2>/dev/null || [ ! -w "$dir" ]; then
    echo "Note: cannot write to $dir; running without a log." >&2
    return 0
  fi
  local keep
  keep="${LOG_KEEP_RUNS:-$(run_log__env_value LOG_KEEP_RUNS)}"
  [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 1 ] || keep=30
  run_log__prune "$dir" "$command" "$keep"

  local stamp file n=1
  stamp="$(date '+%Y%m%d-%H%M%S')"
  file="$dir/${command}-${stamp}.log"
  while [ -e "$file" ]; do
    n=$((n + 1))
    file="$dir/${command}-${stamp}-${n}.log"
  done
  : > "$file"
  ln -sfn "$(basename "$file")" "$dir/latest.log" 2>/dev/null || true

  RUN_LOG_STARTED="$(date +%s)"
  export RM_RUN_LOG="$file"

  # One writer appends everything to the file (stripping colors, masking
  # secrets); stdout and stderr reach both their usual place and the writer.
  exec {RUN_LOG_WRITER_FD}> >(trap "" INT TERM; exec python3 -u "$RUN_LOG_ROOT/scripts/python/run_log_writer.py" "$file" "$RUN_LOG_ROOT/.env")
  RUN_LOG_WRITER_PID=$!
  run_log__header "$command" "${RUN_LOG_ARGS[@]}" >&"$RUN_LOG_WRITER_FD"

  exec {RUN_LOG_ORIG_OUT}>&1 {RUN_LOG_ORIG_ERR}>&2
  exec 1> >(trap "" INT TERM; exec tee -a "/dev/fd/$RUN_LOG_WRITER_FD")
  RUN_LOG_TEE_OUT_PID=$!
  exec 2> >(trap "" INT TERM; exec tee -a "/dev/fd/$RUN_LOG_WRITER_FD" >&"$RUN_LOG_ORIG_ERR")
  RUN_LOG_TEE_ERR_PID=$!

  if [ "${RM_DEBUG:-0}" = "1" ]; then
    export RM_DEBUG=1 RM_DEBUG_FD="$RUN_LOG_WRITER_FD"
    export BASH_XTRACEFD="$RUN_LOG_WRITER_FD"
    export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
    set -x
    export SHELLOPTS
  fi
  trap run_log_finish EXIT
  # Turn Ctrl-C / termination into a normal exit so the EXIT trap finishes
  # the log (the default signal death skips it).
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# run_log_finish: write the footer and flush the log. Called by the EXIT trap.
run_log_finish(){
  local rc=$?
  { set +x; } 2>/dev/null
  [ -n "${RUN_LOG_WRITER_FD:-}" ] || return "$rc"
  trap - EXIT
  # Restore the real stdout/stderr; the tee processes then see EOF and drain.
  exec 1>&"$RUN_LOG_ORIG_OUT" 2>&"$RUN_LOG_ORIG_ERR"
  run_log__wait_pid "${RUN_LOG_TEE_OUT_PID:-}"
  run_log__wait_pid "${RUN_LOG_TEE_ERR_PID:-}"
  {
    echo "==="
    local now; now="$(date +%s)"
    echo "Finished:  $(date '+%Y-%m-%d %H:%M:%S %Z'), exit code ${rc}, $(( now - RUN_LOG_STARTED ))s"
    if [ "${RM_DEBUG:-0}" = "1" ]; then
      run_log__container_tails all
    elif [ "$rc" -ne 0 ]; then
      run_log__container_tails failed
    fi
  } >&"$RUN_LOG_WRITER_FD" 2>&1
  exec {RUN_LOG_WRITER_FD}>&-
  run_log__wait_pid "${RUN_LOG_WRITER_PID:-}"
  RUN_LOG_WRITER_FD=""
  return "$rc"
}
````

- [ ] **Step 4: Add the `debug` fallback to `scripts/bash/lib/common.sh`** — append at the end of the file:

```bash

# debug "message": defined by lib/run-log.sh (and exported to child scripts)
# when a command runs with a log; otherwise a no-op so scripts can call it
# under set -e whether or not they were started by a logging command.
if ! declare -F debug >/dev/null 2>&1; then
  debug(){ return 0; }
fi
```

- [ ] **Step 5: Ignore the logs directory** — append to `.gitignore`:

```
# Script run logs (scripts/bash/lib/run-log.sh)
logs/
```

- [ ] **Step 6: Run the tests and shellcheck**

Run: `bash scripts/bash/tests/test-run-log.sh && shellcheck scripts/bash/lib/run-log.sh scripts/bash/tests/test-run-log.sh scripts/bash/lib/common.sh`
Expected: `passed: 63  failed: 0`; shellcheck reports nothing new for `common.sh` (compare with `git show HEAD:scripts/bash/lib/common.sh | shellcheck -`).

Then the full suites: `python3 -m unittest discover -s scripts/python/tests -t scripts/python` and `for t in scripts/bash/tests/*.sh scripts/hooks/tests/test-lua-hooks.sh; do bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` — no FAIL lines.

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/bash/tests/test-run-log.sh
git add scripts/bash/lib/run-log.sh scripts/bash/lib/common.sh scripts/bash/tests/test-run-log.sh .gitignore
git commit -m "feat(logging): per-run log files and debug mode library

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Adopt in the commands, docs, config

**Files:**
- Modify: `build.sh`, `deploy.sh`, `setup.sh`, `cleanup.sh`, `modules.sh`, `update-latest.sh`, `status.sh`, `changelog.sh`
- Modify: `scripts/bash/backup-export.sh`, `scripts/bash/backup-import.sh`, `scripts/bash/migrate-stack.sh`, `scripts/bash/repair-storage-permissions.sh`
- Modify: `scripts/bash/setup/cli.sh` (help text), `scripts/python/local_modules.py` (help epilog)
- Modify: `docs/TROUBLESHOOTING.md`, `.env.template`, `.env.prebuilt`
- Test: `scripts/bash/tests/test-run-log-adoption.sh`

**Interfaces:**
- Consumes: Task 2's `run_log_start` / `RUN_LOG_ARGS`.

- [ ] **Step 1: Write the failing test** — create `scripts/bash/tests/test-run-log-adoption.sh` (mode 0755):

```bash
#!/bin/bash
# Every command that users run directly adopts lib/run-log.sh: it sources the
# library and calls run_log_start at top level, before parsing its arguments,
# and doesn't exec into another program (which would skip the log's footer).
#
# Usage: scripts/bash/tests/test-run-log-adoption.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# script|command name|read-only
ADOPTERS=(
  "build.sh|build|"
  "deploy.sh|deploy|"
  "setup.sh|setup|"
  "cleanup.sh|cleanup|"
  "modules.sh|modules|"
  "update-latest.sh|update-latest|"
  "status.sh|status|--read-only"
  "changelog.sh|changelog|--read-only"
  "scripts/bash/backup-export.sh|backup-export|"
  "scripts/bash/backup-import.sh|backup-import|"
  "scripts/bash/migrate-stack.sh|migrate-stack|"
  "scripts/bash/repair-storage-permissions.sh|repair-storage-permissions|"
)

for entry in "${ADOPTERS[@]}"; do
  IFS='|' read -r script name ro <<< "$entry"
  f="$REPO_ROOT/$script"
  echo "$script"
  start_line="$(grep -nE "^run_log_start ${name} ${ro:+$ro }-- \"\\\$@\"; set -- \"\\\$\{RUN_LOG_ARGS\[@\]\}\"$" "$f" | head -1 | cut -d: -f1)"
  check "calls run_log_start $name ${ro} at top level" "$([ -n "$start_line" ] && echo yes || echo no)" "yes"
  check "sources lib/run-log.sh" "$(grep -cE '^source ".*scripts/bash/lib/run-log\.sh"$|^source "\$SCRIPT_DIR/lib/run-log\.sh"$' "$f")" "1"
  parse_line="$(grep -nE '^while \[\[? \$# -gt 0' "$f" | head -1 | cut -d: -f1)"
  if [ -n "$parse_line" ] && [ -n "$start_line" ]; then
    check "before argument parsing" "$([ "$start_line" -lt "$parse_line" ] && echo yes || echo no)" "yes"
  fi
  check "no exec into another program" "$(grep -cE '^\s*exec [^{0-9<>]' "$f")" "0"
  check "bash -n" "$(bash -n "$f" 2>&1 && echo ok)" "ok"
done

echo "compose never mounts logs/"
check "logs/ not in docker-compose.yml" "$(grep -cE '(^|[^a-z_])logs/?:' "$REPO_ROOT/docker-compose.yml" | awk '{print ($1>0)?"mounted":"no"}')" "no"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/bash/tests/test-run-log-adoption.sh`
Expected: FAIL lines for every script ("calls run_log_start …", "sources lib/run-log.sh"), and "no exec" FAILs for `modules.sh`, `update-latest.sh`, `status.sh`.

- [ ] **Step 3: Adopt in the top-level commands.** Insert the two lines directly after the line named below (that line sets the script's root directory). Use exactly these lines:

| Script | Insert after | Lines |
|---|---|---|
| `build.sh` | `ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (line 9) | `source "$ROOT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start build -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `deploy.sh` | `ROOT_DIR=…` (line 11) | `source "$ROOT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start deploy -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `setup.sh` | `SCRIPT_DIR=…` (line 11) | `source "$SCRIPT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start setup -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `cleanup.sh` | `PROJECT_DIR="${SCRIPT_DIR}"` (line 13) | `source "$PROJECT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start cleanup -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `modules.sh` | `ROOT_DIR=…` (line 5) | `source "$ROOT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start modules -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `update-latest.sh` | `ROOT_DIR=…` (line 7) | `source "$ROOT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start update-latest -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `status.sh` | `PROJECT_DIR="$SCRIPT_DIR"` (line 7) | `source "$PROJECT_DIR/scripts/bash/lib/run-log.sh"` / `run_log_start status --read-only -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `changelog.sh` | `PROJECT_ROOT="$SCRIPT_DIR"` (line 7) | `source "$PROJECT_ROOT/scripts/bash/lib/run-log.sh"` / `run_log_start changelog --read-only -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |

- [ ] **Step 4: Remove the `exec`s that would skip the footer.**
  - `modules.sh`: replace `exec python3 "$ROOT_DIR/scripts/python/local_modules.py" --root "$ROOT_DIR" "$@"` with `python3 "$ROOT_DIR/scripts/python/local_modules.py" --root "$ROOT_DIR" "$@"` (under `set -e` its exit status is still the script's).
  - `update-latest.sh`: replace both `exec "$ROOT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"` (lines ~98 and ~107) with `"$ROOT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"; exit $?`.
  - `status.sh`: replace `exec "$BINARY_PATH" "${statusdash_args[@]}"` with `"$BINARY_PATH" "${statusdash_args[@]}"`.

- [ ] **Step 5: Adopt in the helpers users run directly.** Same two lines, after the named line:

| Script | Insert after | Lines |
|---|---|---|
| `scripts/bash/backup-export.sh` | `PROJECT_ROOT=…` (line 7) | `source "$SCRIPT_DIR/lib/run-log.sh"` / `run_log_start backup-export -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `scripts/bash/backup-import.sh` | `SCRIPT_DIR=…` (line 6) | `source "$SCRIPT_DIR/lib/run-log.sh"` / `run_log_start backup-import -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `scripts/bash/migrate-stack.sh` | `PROJECT_ROOT=…` (line 9) | `source "$SCRIPT_DIR/lib/run-log.sh"` / `run_log_start migrate-stack -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |
| `scripts/bash/repair-storage-permissions.sh` | `PROJECT_ROOT=…` (line 8) | `source "$SCRIPT_DIR/lib/run-log.sh"` / `run_log_start repair-storage-permissions -- "$@"; set -- "${RUN_LOG_ARGS[@]}"` |

If shellcheck flags the dynamic `source` (SC1091), add `# shellcheck source=scripts/bash/lib/run-log.sh` (top-level) or `# shellcheck source=lib/run-log.sh` (helpers) above it, matching how each file already handles its other sources.

- [ ] **Step 6: Help text.** Directly after each script's `--help` line in its usage text, add two lines aligned to that block's description column:

```
  --debug       Also write a trace of every command to the run log (logs/)
  --no-log      Don't write a run log (logs/) for this run
```

Locations: `build.sh:44`, `deploy.sh:270`, `cleanup.sh:51`, `update-latest.sh:33`, `status.sh:20` (for status: `--debug  Write a run log with a trace of every command (logs/)`), `changelog.sh:45` (same wording as status), `scripts/bash/setup/cli.sh:40`, `scripts/bash/backup-export.sh:50`, `scripts/bash/backup-import.sh:42`, `scripts/bash/migrate-stack.sh:157`, `scripts/bash/repair-storage-permissions.sh:21`.

For `modules.sh` (argparse in `scripts/python/local_modules.py`, line 448): add `epilog="Run logs: modules.sh writes logs/modules-<time>.log; --debug adds a command trace, --no-log skips the log."` to the top-level `argparse.ArgumentParser(...)` call.

- [ ] **Step 7: Config.** In `.env.template`, after the `BACKUP_DAILY_TIME=09` line's block (the `# Backups` section ends with it), add:

```
# =====================
# Script run logs (logs/)
# =====================
# How many logs to keep per command (deploy, build, ...); older ones are deleted.
LOG_KEEP_RUNS=30
```

Add the same block to `.env.prebuilt` after its `BACKUP_DAILY_TIME=09` line.

- [ ] **Step 8: Docs.** In `docs/TROUBLESHOOTING.md`, add `- [Logs and Debugging](#logs-and-debugging)` as the first Table of Contents entry, and this section directly before `## Common Issues`:

````markdown
## Logs and Debugging

Every run of `build.sh`, `deploy.sh`, `setup.sh`, `cleanup.sh`, `modules.sh`,
`update-latest.sh` and the backup/migration scripts writes a log file:

- `logs/<command>-<date>-<time>.log`, e.g. `logs/deploy-20261005-143012.log`
- `logs/latest.log` always points at the most recent run.

Each log starts with the command, the repo commit and key `.env` settings,
contains everything the command printed, and ends with the exit code. If the
command failed, it also contains the last 50 log lines of every container
that exited with an error or is restarting.

**Reporting a problem:** attach `logs/latest.log` (or the log of the failing
run). Passwords, tokens and keys from `.env` are replaced with `***`.

**More detail:** re-run the command with `--debug`. The log then also contains
every command run by every script, with file and line, and the logs of all
containers. The terminal output doesn't change.

**Options:**
- `--no-log` (or `RM_LOG=0`) skips the log for one run.
- `LOG_KEEP_RUNS` in `.env` sets how many logs are kept per command (default 30).
- `status.sh` and `changelog.sh` only write a log with `--debug`.
````

- [ ] **Step 9: Run the tests and a manual smoke**

Run: `bash scripts/bash/tests/test-run-log-adoption.sh` → `failed: 0`.
Run the full suites (as in Task 2 Step 6) → no FAIL lines; shellcheck on every touched script shows nothing new versus `git show origin/main:<file> | shellcheck -`.

Manual smoke in the worktree (it has no `.env`; copy one in and remove it after):
```bash
cp ../AzerothCore-RealmMaster/.env .env
./modules.sh list; echo "rc=$?"; ls logs/; head -5 logs/latest.log; tail -3 logs/latest.log
./modules.sh --debug list >/dev/null; grep -c '^+ ' logs/latest.log      # > 0
./deploy.sh --help >/dev/null; ls logs/ | grep -c '^deploy-'              # 1
./status.sh --help >/dev/null; ls logs/ | grep -c '^status-'              # 0 (read-only)
pw="$(grep '^MYSQL_ROOT_PASSWORD=' .env | cut -d= -f2)"
grep -lF -- "$pw" logs/*.log || echo "password not in any log"                 # must print the second message
rm -f .env; rm -rf logs
```
Expected as commented. Record the outputs in the task report. (Review Focus 1–4: also run `./deploy.sh` up to its first prompt and confirm the prompt shows immediately, then answer `n`.)

- [ ] **Step 10: Commit**

```bash
chmod +x scripts/bash/tests/test-run-log-adoption.sh
git add -A build.sh deploy.sh setup.sh cleanup.sh modules.sh update-latest.sh status.sh changelog.sh \
  scripts/bash/backup-export.sh scripts/bash/backup-import.sh scripts/bash/migrate-stack.sh \
  scripts/bash/repair-storage-permissions.sh scripts/bash/setup/cli.sh scripts/python/local_modules.py \
  scripts/bash/tests/test-run-log-adoption.sh docs/TROUBLESHOOTING.md .env.template .env.prebuilt
git commit -m "feat(logging): run logs for every command; --debug and --no-log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


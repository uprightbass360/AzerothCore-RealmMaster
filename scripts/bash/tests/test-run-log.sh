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
cp "$REPO_ROOT/scripts/bash/lib/run-log.sh" "$REPO_ROOT/scripts/bash/lib/run-log-trace.sh" "$R/scripts/bash/lib/"
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

# lax-child.sh: no set -e/-u/pipefail; debug mode must not add them.
cat > "$R/lax-child.sh" <<'EOF'
#!/bin/bash
echo "unset var is [${NOT_SET_ANYWHERE}]"
false | true
false
echo "lax child finished"
EOF

# entry.sh <name>: a command adopting the library.
cat > "$R/entry.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/bash/lib/run-log.sh"
run_log_start "${ENTRY_NAME:-entry}" ${ENTRY_READ_ONLY:+--read-only} -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
echo "args: $*"
[ -n "${PAUSE:-}" ] && sleep "$PAUSE"
# A background job that keeps stdout/stderr open after the script exits.
[ -n "${BG_HOLD:-}" ] && { sleep "$BG_HOLD" & }
printf '\033[0;32mgreen\033[0m\n'
printf 'progress 10%%\rprogress 100%%\n'
pw_cmd="mysql -psup3rs3cret -u abc"
echo "short token abc stays"
debug "entry decided Y"
if [ -n "${WRITE_SECRET:-}" ]; then
  echo "NEW_API_TOKEN=$WRITE_SECRET" >> "$ROOT_DIR/.env"
  echo "generated token $WRITE_SECRET"
fi
"$ROOT_DIR/child.sh"
"$ROOT_DIR/lax-child.sh"
[ "${NESTED:-0}" = 1 ] && ENTRY_NAME=inner NESTED=0 "$ROOT_DIR/entry.sh" inner-arg
[ -n "${EXIT_CODE:-}" ] && exit "$EXIT_CODE"
[ "${FAIL_CMD:-0}" = 1 ] && false
echo "end"
EOF
chmod +x "$R/child.sh" "$R/lax-child.sh" "$R/entry.sh"

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
check "log file readable only by the user (0600)" "$(stat -c %a "$F")" "600"
check "logs/ private (0700)" "$(stat -c %a "$R/logs")" "700"

echo "secrets"
check "password masked in output" "$(has "$F" 'child out ***')" "yes"
check "password never in the file" "$(has "$F" 'sup3rs3cret')" "no"
check "short value left alone" "$(has "$F" 'short token abc stays')" "yes"
reset_logs; mkdir -m 0755 "$R/logs"
run_entry --
check "existing logs/ of ours made private (0700)" "$(stat -c %a "$R/logs")" "700"

echo "secrets in arguments and written during the run"
reset_logs
run_entry -- --mysql-password Hunter2Secret --token=Tok3nValue -p PwShort9 --name visible
F="$(log_file)"
check "header: option values masked, names kept" "$(has "$F" 'Command:   entry --mysql-password *** --token=*** -p *** --name visible')" "yes"
check "header: no argument secret" "$(grep '^Command:' "$F" | grep -cE 'Hunter2Secret|Tok3nValue|PwShort9')" "0"
cp "$R/.env" "$WORK/env.bak"
reset_logs
run_entry WRITE_SECRET=Fr3shT0kenXYZ --
F="$(log_file)"
check "secret written to .env mid-run: run succeeds" "$RC" "0"
check "secret written to .env mid-run: masked in the final log" "$(grep -c 'Fr3shT0kenXYZ' "$F")" "0"
check "secret written to .env mid-run: line kept, masked" "$(has "$F" 'generated token ***')" "yes"
check "secret written to .env mid-run: earlier secrets still masked" "$(has "$F" 'sup3rs3cret')" "no"
cp "$WORK/env.bak" "$R/.env"

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
check "debug keeps child options: lax child still finishes" "$(has "$F" 'lax child finished')" "yes"
check "debug traces a child without set -x of its own" "$(grep -cE '^\+ lax-child\.sh:[0-9]+: echo' "$F" | awk '{print ($1>0)?"yes":"no"}')" "yes"
check "debug: entry still succeeds" "$RC" "0"
start_ts="$(date +%s%N)"
run_entry -- --debug
elapsed_ms=$(( ($(date +%s%N) - start_ts) / 1000000 ))
check "debug run finishes promptly (<3 s, no exit hang)" "$([ "$elapsed_ms" -lt 3000 ] && echo yes || echo "no (${elapsed_ms} ms)")" "yes"
reset_logs
cat > "$R/quiet.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/scripts/bash/lib/run-log.sh"
run_log_start quiet -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
echo "quiet end"
[ -n "${EXIT_CODE:-}" ] && exit "$EXIT_CODE"
true
EOF
chmod +x "$R/quiet.sh"
env -u RM_RUN_LOG -u RM_DEBUG -u RM_LOG "$R/quiet.sh" --debug >/dev/null 2>&1
check "debug log has no stray 'set +x' trace line" "$(grep -c 'set +x' "$(log_file)")" "0"
check "debug log still ends with the footer" "$(has "$(log_file)" 'exit code 0')" "yes"
reset_logs
env -u RM_RUN_LOG -u RM_DEBUG -u RM_LOG EXIT_CODE=4 "$R/quiet.sh" --debug >/dev/null 2>&1
check "debug: exit status kept with the quiet EXIT trap" "$?" "4"
check "debug: footer has the exit code" "$(has "$(log_file)" 'exit code 4')" "yes"
check "debug: no 'set +x' on failure either" "$(grep -c 'set +x' "$(log_file)")" "0"
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

echo "footer timing"
reset_logs
run_entry BG_HOLD=3 --
secs="$(sed -n 's/^Finished: .*exit code 0, \([0-9]*\)s$/\1/p' "$(log_file)")"
check "duration excludes the wait for output to drain" "$([ -n "$secs" ] && [ "$secs" -le 1 ] && echo yes || echo "no (${secs:-none}s)")" "yes"

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
# python3 older than 3.7 (the writer needs 3.7): a shim that fails the version check.
OLDPY="$WORK/oldpython-bin"
mkdir -p "$OLDPY"
cat > "$OLDPY/python3" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$OLDPY/python3"
run_entry PATH="$OLDPY:$PATH" --
check "old python3: command succeeds" "$RC" "0"
check "old python3: output intact" "$(grep -c '^end$' "$WORK/out")" "1"
check "old python3: notice" "$(grep -c '3.7 or newer' "$WORK/err")" "1"
check "old python3: no log" "$([ -e "$R/logs/latest.log" ] && echo yes || echo no)" "no"
reset_logs
# Writer that dies after starting: passes the version check, then exits.
DEADW="$WORK/deadwriter-bin"
mkdir -p "$DEADW"
cat > "$DEADW/python3" <<EOF
#!/bin/bash
case "\$1" in
  -c) exec $(command -v python3) "\$@" ;;
  -u) sleep 0.2; exit 1 ;;
esac
exit 1
EOF
chmod +x "$DEADW/python3"
for mode in "" --debug; do
  run_entry PATH="$DEADW:$PATH" PAUSE=0.6 -- $mode
  check "writer dies mid-run ${mode:-(normal)}: command succeeds" "$RC" "0"
  check "writer dies mid-run ${mode:-(normal)}: terminal output intact" "$(grep -c '^end$' "$WORK/out")" "1"
done
reset_logs
# Writer that dies at once: either the liveness check catches it or tee -p
# carries on; the command must work either way, and latest.log never dangles.
QUICKW="$WORK/quickdeath-bin"
mkdir -p "$QUICKW"
cat > "$QUICKW/python3" <<EOF
#!/bin/bash
case "\$1" in
  -c) exec $(command -v python3) "\$@" ;;
esac
exit 1
EOF
chmod +x "$QUICKW/python3"
run_entry PATH="$QUICKW:$PATH" --
check "writer dies at once: command succeeds" "$RC" "0"
check "writer dies at once: terminal output intact" "$(grep -c '^end$' "$WORK/out")" "1"
check "writer dies at once: latest.log never dangles" "$([ -L "$R/logs/latest.log" ] && [ ! -e "$R/logs/latest.log" ] && echo dangling || echo ok)" "ok"
reset_logs
touch "$R/logs"
run_entry --
check "logs/ not creatable: command succeeds" "$RC" "0"
check "logs/ not creatable: notice" "$(grep -c 'running without a log' "$WORK/err")" "1"
rm -f "$R/logs"

echo "run as root (sudo): logs/ handed back to the user"
# owner_of [env...]: run_log__owner's output and status under that environment.
owner_of(){
  # shellcheck disable=SC2016  # expanded by the inner bash
  env -u SUDO_UID -u SUDO_GID "$@" RUN_LOG_ROOT="$R" bash -c \
    'source "$RUN_LOG_ROOT/scripts/bash/lib/run-log.sh"; run_log__owner; echo " rc=$?"' 2>&1
}
check "owner: not root -> none" "$(owner_of RUN_LOG_EUID=1000)" " rc=1"
check "owner: sudo -> SUDO_UID:SUDO_GID" "$(owner_of RUN_LOG_EUID=0 SUDO_UID=1234 SUDO_GID=5678)" "1234:5678 rc=0"
check "owner: root without sudo -> owner of the repo" "$(owner_of RUN_LOG_EUID=0)" "$(stat -c %u:%g "$R") rc=0"
CHOWNBIN="$WORK/chown-bin"
mkdir -p "$CHOWNBIN"
printf '#!/bin/bash\necho "$*" >> "%s"\nexit 1\n' "$WORK/chown.calls" > "$CHOWNBIN/chown"
chmod +x "$CHOWNBIN/chown"
reset_logs; rm -f "$WORK/chown.calls"
run_entry -u SUDO_UID -u SUDO_GID RUN_LOG_EUID=0 SUDO_UID=1234 SUDO_GID=5678 PATH="$CHOWNBIN:$PATH" --
F="$(log_file)"
touch "$WORK/chown.calls"
check "sudo run: succeeds although chown fails" "$RC" "0"
check "sudo run: log written" "$(has "$F" 'exit code 0')" "yes"
check "sudo run: logs/ chowned to the sudo user" "$(grep -cxF -- "-h 1234:5678 $R/logs" "$WORK/chown.calls")" "1"
check "sudo run: log file chowned without following it" "$(grep -cxF -- "-h 1234:5678 $F" "$WORK/chown.calls")" "1"
check "sudo run: latest.log chowned without following it" "$(grep -cxF -- "-h 1234:5678 $R/logs/latest.log" "$WORK/chown.calls")" "1"
rm -f "$WORK/chown.calls"
run_entry -u SUDO_UID -u SUDO_GID RUN_LOG_EUID=1000 PATH="$CHOWNBIN:$PATH" --
check "normal user run: no chown" "$([ -e "$WORK/chown.calls" ] && echo called || echo none)" "none"
reset_logs; mkdir -p "$R/logs"; chmod 0500 "$R/logs"
run_entry --
check "logs/ not writable (left by an old root run): command succeeds" "$RC" "0"
check "logs/ not writable: notice" "$(grep -c 'running without a log' "$WORK/err")" "1"
chmod 0700 "$R/logs"
# logs/ as a symlink: never followed (a root run would chmod/chown the target).
LINK_TARGET="$WORK/link-target"
reset_logs; rm -rf "$LINK_TARGET"; mkdir -m 0755 "$LINK_TARGET"; echo keep > "$LINK_TARGET/existing"
ln -s "$LINK_TARGET" "$R/logs"
target_state(){ stat -c '%a %u:%g' "$LINK_TARGET"; find "$LINK_TARGET" -mindepth 1 -printf '%P\n' | sort; }
before="$(target_state)"
run_entry --
check "logs/ symlink: command succeeds" "$RC" "0"
check "logs/ symlink: notice" "$(grep -c 'running without a log' "$WORK/err")" "1"
check "logs/ symlink: target untouched" "$(target_state)" "$before"
check "logs/ symlink: no log file anywhere" "$(find "$R" "$LINK_TARGET" -name 'entry-*.log' | wc -l)" "0"
rm -f "$WORK/chown.calls"
run_entry -u SUDO_UID -u SUDO_GID RUN_LOG_EUID=0 PATH="$CHOWNBIN:$PATH" --
check "logs/ symlink as root: command succeeds" "$RC" "0"
check "logs/ symlink as root: chown never called" "$([ -e "$WORK/chown.calls" ] && echo called || echo none)" "none"
check "logs/ symlink as root: target untouched" "$(target_state)" "$before"
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

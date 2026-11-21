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

# run_log__mask_args ARG...: the arguments joined by spaces, with the value of
# every secret-looking option replaced by ***: options whose name contains
# pass, token, secret or key (any case), and -p (backup-export/-import's
# password). Handles both "--opt value" and "--opt=value".
run_log__mask_args(){
  local -a out=()
  local arg name mask_next=0
  for arg in "$@"; do
    if [ "$mask_next" = "1" ]; then
      out+=("***"); mask_next=0; continue
    fi
    if [[ "$arg" == -?* ]]; then
      name="${arg%%=*}"; name="${name#-}"; name="${name#-}"
      if [[ "${name,,}" =~ pass|token|secret|key ]] || [ "$name" = "p" ]; then
        if [[ "$arg" == *=* ]]; then
          out+=("${arg%%=*}=***")
        else
          out+=("$arg"); mask_next=1
        fi
        continue
      fi
    fi
    out+=("$arg")
  done
  printf '%s' "${out[*]}"
}

run_log__header(){
  local command="$1"; shift
  local commit dirty key enabled
  echo "=== RealmMaster ${command} run ==="
  echo "Command:   ${command} $(run_log__mask_args "$@")"
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

# run_log__owner: when running as root, the user:group that logs/ should
# belong to (the sudo user, else the owner of the repo); fails otherwise.
# RUN_LOG_EUID stands in for EUID in tests.
run_log__owner(){
  [ "${RUN_LOG_EUID:-$EUID}" = "0" ] || return 1
  if [ -n "${SUDO_UID:-}" ]; then
    printf '%s' "${SUDO_UID}${SUDO_GID:+:$SUDO_GID}"
    return 0
  fi
  local owner
  owner="$(stat -c %u:%g "$RUN_LOG_ROOT" 2>/dev/null)" || return 1
  printf '%s' "$owner"
}

# run_log__chown PATH...: as root, hand PATHs to run_log__owner, so a sudo
# run doesn't leave logs/ unwritable for later runs. Never follows a symlink
# (chown -h). Never fails.
run_log__chown(){
  local owner p
  owner="$(run_log__owner)" && [ -n "$owner" ] || return 0
  for p in "$@"; do
    chown -h "$owner" "$p" 2>/dev/null || true
  done
  return 0
}

# run_log__preflight: can this host run the log pipeline? Prints why not.
run_log__preflight(){
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Note: python3 not found; running without a log." >&2
    return 1
  fi
  if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' 2>/dev/null; then
    echo "Note: python3 3.7 or newer is needed for the run log; running without a log." >&2
    return 1
  fi
  if [ ! -f "$RUN_LOG_ROOT/scripts/python/run_log_writer.py" ]; then
    echo "Note: scripts/python/run_log_writer.py is missing; running without a log." >&2
    return 1
  fi
  # tee -p keeps the terminal output going if the writer ever dies (GNU tee).
  if ! tee -p /dev/null </dev/null >/dev/null 2>&1; then
    echo "Note: this tee has no -p option (GNU coreutils needed); running without a log." >&2
    return 1
  fi
  return 0
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

  if ! run_log__preflight; then
    return 0
  fi
  local dir="$RUN_LOG_ROOT/logs"
  # Never follow a symlinked logs/: as root, the chmod/chown below would hit
  # whatever it points at. Checked before anything else touches the dir.
  if [ -L "$dir" ]; then
    echo "Note: cannot write to $dir (it is a symlink); running without a log." >&2
    return 0
  fi
  # Logs can hold secrets that aren't in .env: keep them private.
  if ! { mkdir -m 0700 "$dir" 2>/dev/null || [ -d "$dir" ]; } || [ ! -w "$dir" ]; then
    echo "Note: cannot write to $dir; running without a log." >&2
    return 0
  fi
  if [ -O "$dir" ]; then chmod 0700 "$dir" 2>/dev/null || true; fi
  run_log__chown "$dir"
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
  ( umask 077; : > "$file" )
  run_log__chown "$file"

  RUN_LOG_STARTED="$(date +%s)"
  export RM_RUN_LOG="$file"

  # One writer appends everything to the file (stripping colors, masking
  # secrets); stdout and stderr reach both their usual place and the writer.
  exec {RUN_LOG_WRITER_FD}> >(trap "" INT TERM; exec python3 -u "$RUN_LOG_ROOT/scripts/python/run_log_writer.py" "$file" "$RUN_LOG_ROOT/.env")
  RUN_LOG_WRITER_PID=$!
  # In a subshell: if the writer already died, only the subshell gets SIGPIPE.
  ( run_log__header "$command" "${RUN_LOG_ARGS[@]}" >&"$RUN_LOG_WRITER_FD" ) 2>/dev/null || true
  if ! kill -0 "$RUN_LOG_WRITER_PID" 2>/dev/null; then
    exec {RUN_LOG_WRITER_FD}>&-
    RUN_LOG_WRITER_FD=""
    rm -f "$file"
    unset RM_RUN_LOG
    echo "Note: the run log writer failed to start; running without a log." >&2
    return 0
  fi
  ln -sfn "$(basename "$file")" "$dir/latest.log" 2>/dev/null || true
  run_log__chown "$dir/latest.log"

  exec {RUN_LOG_ORIG_OUT}>&1 {RUN_LOG_ORIG_ERR}>&2
  exec 1> >(trap "" INT TERM; exec tee -p -a "/dev/fd/$RUN_LOG_WRITER_FD")
  RUN_LOG_TEE_OUT_PID=$!
  exec 2> >(trap "" INT TERM; exec tee -p -a "/dev/fd/$RUN_LOG_WRITER_FD" >&"$RUN_LOG_ORIG_ERR")
  RUN_LOG_TEE_ERR_PID=$!

  if [ "${RM_DEBUG:-0}" = "1" ]; then
    # Trace lines get their own tee -p (to /dev/null and the writer), so a dead
    # writer can't SIGPIPE a traced script. Only xtrace is passed to child bash
    # scripts (BASH_ENV runs set -x in each); exporting SHELLOPTS would also
    # pass the entry script's errexit/nounset/pipefail down.
    exec {RUN_LOG_TRACE_FD}> >(trap "" INT TERM; exec tee -p -a "/dev/fd/$RUN_LOG_WRITER_FD" >/dev/null 2>&"$RUN_LOG_ORIG_ERR")
    RUN_LOG_TRACE_PID=$!
    export RM_DEBUG=1 RM_DEBUG_FD="$RUN_LOG_TRACE_FD"
    export BASH_XTRACEFD="$RUN_LOG_TRACE_FD"
    export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
    export BASH_ENV="$RUN_LOG_LIB_DIR/run-log-trace.sh"
    # Save the exit status and stop tracing with that "+ set +x" line sent to
    # /dev/null (xtrace writes to the trace fd, not stderr), so the log ends
    # with the script's last command.
    # shellcheck disable=SC2064  # the fd number is fixed now
    trap "{ RUN_LOG_EXIT_RC=\$?; set +x; } ${RUN_LOG_TRACE_FD}>/dev/null; run_log_finish" EXIT
  else
    trap run_log_finish EXIT
  fi
  # Turn Ctrl-C / termination into a normal exit so the EXIT trap finishes
  # the log (the default signal death skips it).
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [ "${RM_DEBUG:-0}" = "1" ]; then set -x; fi
}

# run_log_finish: write the footer and flush the log. Called by the EXIT trap.
run_log_finish(){
  local rc=$?
  [ -z "${RUN_LOG_EXIT_RC:-}" ] || rc="$RUN_LOG_EXIT_RC"
  { set +x; } 2>/dev/null
  [ -n "${RUN_LOG_WRITER_FD:-}" ] || return "$rc"
  trap - EXIT
  # The run ends now; waiting for the output to drain doesn't count.
  local ended finished
  ended="$(date +%s)"
  finished="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  # Close the trace descriptor first: its tee would otherwise hold a pipe the
  # stdout/stderr tees are waiting on.
  if [ -n "${RUN_LOG_TRACE_FD:-}" ]; then
    exec {RUN_LOG_TRACE_FD}>&-
    run_log__wait_pid "${RUN_LOG_TRACE_PID:-}"
    RUN_LOG_TRACE_FD=""
  fi
  # Restore the real stdout/stderr; the tee processes then see EOF and drain.
  exec 1>&"$RUN_LOG_ORIG_OUT" 2>&"$RUN_LOG_ORIG_ERR"
  run_log__wait_pid "${RUN_LOG_TEE_OUT_PID:-}"
  run_log__wait_pid "${RUN_LOG_TEE_ERR_PID:-}"
  # In a subshell: if the writer has died, only the subshell gets SIGPIPE.
  (
    echo "==="
    echo "Finished:  ${finished}, exit code ${rc}, $(( ended - RUN_LOG_STARTED ))s"
    if [ "${RM_DEBUG:-0}" = "1" ]; then
      run_log__container_tails all
    elif [ "$rc" -ne 0 ]; then
      run_log__container_tails failed
    fi
  ) >&"$RUN_LOG_WRITER_FD" 2>&1 || true
  exec {RUN_LOG_WRITER_FD}>&-
  run_log__wait_pid "${RUN_LOG_WRITER_PID:-}"
  RUN_LOG_WRITER_FD=""
  return "$rc"
}

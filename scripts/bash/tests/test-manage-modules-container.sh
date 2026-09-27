#!/bin/bash
# manage-modules.sh must not move a compiled C++ module's checkout during a
# container-mode deploy (MODULES_LOCAL_RUN unset, i.e. the ac-modules
# container): build.sh stages the compiled checkout into local-storage/modules
# and stage-modules.sh syncs it to storage/modules before containers start, so
# the container already has the built version - fetching/pulling it (or
# re-cloning it on an origin change) would stage SQL/config newer than the
# compiled binary. A missing checkout is still cloned, and non-C++ modules
# (lua/sql/tool) plus host-side runs (MODULES_LOCAL_RUN=1, the run build.sh
# drives) behave exactly as before. Drives the real generate_module_state +
# install_enabled_modules (sourced, main not run) against local bare repos in
# a temp dir. No docker or network needed.
#
# Usage: scripts/bash/tests/test-manage-modules-container.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Sourcing manage-modules.sh without its main guard would run a real module pass
# in the current directory; refuse rather than risk that.
# shellcheck disable=SC2016  # literal pattern, nothing to expand
grep -q '^if \[\[ "${BASH_SOURCE\[0\]}" == "$0" \]\]; then' "$REPO_ROOT/scripts/bash/manage-modules.sh" \
  || { echo "manage-modules.sh has no main guard; not sourcing it" >&2; exit 1; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# make_bare <name> <content>: bare repo $WORK/<name>.git with content.txt.
make_bare(){
  git init -q -b main "$WORK/src-$1"
  echo "$2" > "$WORK/src-$1/content.txt"
  git -C "$WORK/src-$1" add content.txt
  git -C "$WORK/src-$1" commit -q -m init
  git clone -q --bare "$WORK/src-$1" "$WORK/$1.git"
}

# advance_bare <name> <content>: add a new commit to $WORK/<name>.git via a
# throwaway clone (simulates upstream moving on after a build compiled it).
advance_bare(){
  local tmp="$WORK/advance-$1-$$-$RANDOM"
  git clone -q "$WORK/$1.git" "$tmp"
  echo "$2" > "$tmp/content.txt"
  git -C "$tmp" add content.txt
  git -C "$tmp" commit -q -m advance
  git -C "$tmp" push -q origin main
  rm -rf "$tmp"
}

make_bare cpp-up "cpp-v1"
make_bare cpp-fork "cpp-fork"
make_bare lua-up "lua-v1"
CPP_UP="$WORK/cpp-up.git"
CPP_FORK="$WORK/cpp-fork.git"
LUA_UP="$WORK/lua-up.git"

ROOT="$WORK/root"
mkdir -p "$ROOT/config" "$ROOT/modules" "$ROOT/state"
printf '{"modules": [
  {"key": "MODULE_CPP", "name": "mod-cpp", "repo": "%s", "type": "cpp"},
  {"key": "MODULE_LUA", "name": "mod-lua", "repo": "%s", "type": "lua"}
]}\n' "$CPP_UP" "$LUA_UP" > "$ROOT/config/module-manifest.json"
printf 'MODULE_CPP=1\nMODULE_LUA=1\n' > "$ROOT/.env"

# set_cpp_override <repo>: local override of MODULE_CPP's repo ("" removes it).
set_cpp_override(){
  if [ -n "$1" ]; then
    printf '{"modules": [{"key": "MODULE_CPP", "repo": "%s"}]}\n' "$1" \
      > "$ROOT/config/module-manifest.local.json"
  else
    rm -f "$ROOT/config/module-manifest.local.json"
  fi
}

# run_pass <mode: container|host>: one deploy's install step. Sets OUT and RC.
run_pass(){
  local mode="$1"
  local local_run=0
  [ "$mode" = "host" ] && local_run=1
  OUT="$(
    MODULES_ENV_PATH="$ROOT/.env" MODULES_LOCAL_RUN="$local_run" bash -c '
      set -e
      source "$1/scripts/bash/manage-modules.sh"
      cd "$2/modules"
      MANIFEST_PATH="$2/config/module-manifest.json"
      STATE_DIR="$2/state"
      generate_module_state
      install_enabled_modules
      echo "MODULES_INSTALL_FAILED=${MODULES_INSTALL_FAILED}"
    ' _ "$REPO_ROOT" "$ROOT" 2>&1
  )"
  RC=$?
}

cpp_dir="$ROOT/modules/mod-cpp"
lua_dir="$ROOT/modules/mod-lua"
cpp_content(){ cat "$cpp_dir/content.txt" 2>/dev/null; }
lua_content(){ cat "$lua_dir/content.txt" 2>/dev/null; }
cpp_origin(){ git -C "$cpp_dir" remote get-url origin 2>/dev/null; }
recloned(){ case "$OUT" in *"re-cloning"*) echo yes;; *) echo no;; esac; }

echo "container mode: initial install clones a missing checkout"
run_pass container
check "pass succeeds" "$RC" "0"
check "cpp cloned from upstream" "$(cpp_content)" "cpp-v1"
check "lua cloned from upstream" "$(lua_content)" "lua-v1"

echo "container mode: upstream advances; the compiled cpp checkout is kept, lua still updates"
advance_bare cpp-up "cpp-v2"
advance_bare lua-up "lua-v2"
run_pass container
check "pass succeeds" "$RC" "0"
check "cpp checkout NOT updated (still v1)" "$(cpp_content)" "cpp-v1"
check "lua checkout IS updated (v2)" "$(lua_content)" "lua-v2"
case "$OUT" in *"mod-cpp is compiled into the server; keeping the built checkout"*) r=yes;; *) r=no;; esac
check "logs that the compiled checkout is kept" "$r" "yes"

echo "container mode: cpp repo URL changes; the compiled checkout is NOT re-cloned"
set_cpp_override "$CPP_FORK"
run_pass container
check "pass succeeds" "$RC" "0"
check "cpp origin unchanged" "$(cpp_origin)" "$CPP_UP"
check "cpp content unchanged (not the fork's)" "$(cpp_content)" "cpp-v1"
check "not re-cloned" "$(recloned)" "no"
set_cpp_override ""

echo "container mode: a missing cpp checkout is still cloned"
rm -rf "$cpp_dir"
run_pass container
check "pass succeeds" "$RC" "0"
check "cpp cloned fresh" "$([ -d "$cpp_dir/.git" ] && echo yes || echo no)" "yes"
check "cpp content is upstream's current HEAD" "$(cpp_content)" "cpp-v2"

echo "host mode (MODULES_LOCAL_RUN=1): the cpp checkout IS updated (unchanged behaviour)"
advance_bare cpp-up "cpp-v3"
run_pass host
check "pass succeeds" "$RC" "0"
check "cpp checkout updated (v3)" "$(cpp_content)" "cpp-v3"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

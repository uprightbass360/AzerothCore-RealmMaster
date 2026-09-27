#!/bin/bash
# manage-modules.sh must re-clone an existing checkout when the module's repo
# changes (a fork added with ./modules.sh add <fork> --key MODULE_X, or that
# override removed again), and must not re-clone when the URL only differs by
# scheme, case, a trailing slash or ".git". Drives the real
# generate_module_state + install_enabled_modules (sourced, main not run)
# against local bare repos in a temp dir. No docker or network needed.
#
# Usage: scripts/bash/tests/test-manage-modules-origin.sh
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
make_bare up "upstream"
make_bare fork "fork"
UP="$WORK/up.git"
FORK="$WORK/fork.git"

ROOT="$WORK/root"
mkdir -p "$ROOT/config" "$ROOT/modules" "$ROOT/state"
printf '{"modules": [{"key": "MODULE_UP", "name": "mod-up", "repo": "%s", "type": "lua"}]}\n' \
  "$UP" > "$ROOT/config/module-manifest.json"
printf 'MODULE_UP=1\n' > "$ROOT/.env"

# set_override <repo>: local override of MODULE_UP's repo ("" removes it).
set_override(){
  if [ -n "$1" ]; then
    printf '{"modules": [{"key": "MODULE_UP", "repo": "%s"}]}\n' "$1" \
      > "$ROOT/config/module-manifest.local.json"
  else
    rm -f "$ROOT/config/module-manifest.local.json"
  fi
}

# run_pass: one deploy's install step. Sets OUT and RC.
run_pass(){
  OUT="$(
    PATH="${SHIM_PATH:+$SHIM_PATH:}$PATH" MODULES_ENV_PATH="$ROOT/.env" MODULES_LOCAL_RUN=1 bash -c '
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

checkout="$ROOT/modules/mod-up"
origin(){ git -C "$checkout" remote get-url origin 2>/dev/null; }
content(){ cat "$checkout/content.txt" 2>/dev/null; }
recloned(){ case "$OUT" in *"re-cloning"*) echo yes;; *) echo no;; esac; }

echo "first install from the upstream repo"
run_pass
check "pass succeeds" "$RC" "0"
check "cloned upstream" "$(content)" "upstream"

echo "fork added as an override of the installed module"
set_override "$FORK"
run_pass
check "pass succeeds" "$RC" "0"
check "origin is the fork" "$(origin)" "$FORK"
check "content is the fork's" "$(content)" "fork"
case "$OUT" in *"origin changed ($UP -> $FORK); re-cloning"*) r=yes;; *) r=no;; esac
check "logs the origin change" "$r" "yes"
check "no install failure recorded" "$(grep -c 'MODULES_INSTALL_FAILED=0' <<<"$OUT")" "1"

echo "same fork, URL differs only by scheme/case/trailing slash/.git"
touch "$checkout/.marker"
set_override "FILE://${FORK^^}/"
run_pass
check "pass succeeds" "$RC" "0"
check "not re-cloned" "$(recloned)" "no"
check "checkout kept (marker still there)" "$([ -e "$checkout/.marker" ] && echo yes || echo no)" "yes"
check "origin unchanged" "$(origin)" "$FORK"

echo "origin unreadable (git refuses a checkout owned by another user)"
# A git shim that fails `remote get-url` the way git does for a repo owned by
# another user, and passes everything else through.
REAL_GIT="$(command -v git)"
mkdir -p "$WORK/shim"
cat > "$WORK/shim/git" <<EOF
#!/bin/bash
case " \$* " in *" remote get-url "*)
  echo "fatal: detected dubious ownership in repository at '\$PWD'" >&2
  exit 128;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/shim/git"
SHIM_PATH="$WORK/shim" run_pass
check "not re-cloned" "$(recloned)" "no"
check "checkout kept (marker still there)" "$([ -e "$checkout/.marker" ] && echo yes || echo no)" "yes"

echo "override removed again"
set_override ""
run_pass
check "pass succeeds" "$RC" "0"
check "origin back to upstream" "$(origin)" "$UP"
check "content back to upstream" "$(content)" "upstream"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

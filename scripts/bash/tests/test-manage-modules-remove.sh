#!/bin/bash
# `./modules.sh remove` followed by a deploy must undo `./modules.sh add`: the
# next manage-modules.sh run removes the module's checkout and its staged Lua.
# Runs the real local_modules.py remove against a temp project root, then the
# real manage-modules.sh functions (sourced, main not run) against temp dirs.
# No docker or network needed.
#
# Usage: scripts/bash/tests/test-manage-modules-remove.sh
#   PYTHON_DIR=<dir> overrides where local_modules.py is taken from.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PYTHON_DIR="${PYTHON_DIR:-$REPO_ROOT/scripts/python}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Sourcing manage-modules.sh without its main guard would run a real module pass
# in the current directory; refuse rather than risk that.
grep -q '^if \[\[ "${BASH_SOURCE\[0\]}" == "$0" \]\]; then' "$REPO_ROOT/scripts/bash/manage-modules.sh" \
  || { echo "manage-modules.sh has no main guard; not sourcing it" >&2; exit 1; }

PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); echo "  ok   $1"; }
fail(){ FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

ROOT="$WORK/root"
mkdir -p "$ROOT/config" "$ROOT/modules/mod-mine/.git" "$ROOT/modules/mod-up" \
  "$ROOT/lua/mod-mine" "$ROOT/state"
cat > "$ROOT/config/module-manifest.json" <<'EOF'
{"modules": [
  {"key": "MODULE_ELUNA", "name": "mod-ale", "repo": "https://example.com/mod-ale.git", "type": "cpp"},
  {"key": "MODULE_UP", "name": "mod-up", "repo": "https://example.com/mod-up.git", "type": "cpp"}
]}
EOF
cat > "$ROOT/config/module-manifest.local.json" <<'EOF'
{"modules": [
  {"key": "MODULE_MINE", "name": "mod-mine", "repo": "https://example.com/mod-mine.git", "type": "lua",
   "post_install_hooks": ["copy-standard-lua"], "requires": ["MODULE_ELUNA"]}
]}
EOF
printf 'MODULE_ELUNA=1\nMODULE_MINE=1\nMODULE_UP=1\n' > "$ROOT/.env"
echo 'print(1)' > "$ROOT/lua/mod-mine/mine.lua"
echo 'print(2)' > "$ROOT/lua/hand-placed.lua"

echo "./modules.sh remove, then a deploy's module pass"
python3 "$PYTHON_DIR/local_modules.py" --root "$ROOT" remove MODULE_MINE >"$WORK/remove.log" 2>&1 \
  && pass "remove exits 0" || { fail "remove exits 0"; cat "$WORK/remove.log"; }

out="$(
  MODULES_ENV_PATH="$ROOT/.env" MODULES_LOCAL_RUN=1 bash -c '
    set -e
    source "$1/scripts/bash/manage-modules.sh"
    cd "$2/modules"
    MANIFEST_PATH="$2/config/module-manifest.json"
    STATE_DIR="$2/state"
    LUA_SCRIPTS_TARGET="$2/lua"
    generate_module_state
    remove_disabled_modules
    reset_staged_lua
    echo "PASS_DONE"
  ' _ "$REPO_ROOT" "$ROOT" 2>&1
)"
case "$out" in *PASS_DONE*) pass "module pass completes";; *) fail "module pass completes"; echo "$out";; esac
[ ! -e "$ROOT/modules/mod-mine" ] && pass "checkout removed" || fail "checkout removed"
[ ! -e "$ROOT/lua/mod-mine" ] && pass "staged Lua folder removed" || fail "staged Lua folder removed"
[ -d "$ROOT/modules/mod-up" ] && pass "enabled module's checkout kept" || fail "enabled module's checkout kept"
[ -f "$ROOT/lua/hand-placed.lua" ] && pass "hand-placed Lua kept" || fail "hand-placed Lua kept"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

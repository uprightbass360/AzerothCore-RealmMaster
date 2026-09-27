#!/bin/bash
# Tests for the Lua staging hooks (copy-standard-lua, copy-aio-lua,
# copy-aio-server, black-market-setup). Runs against fixture module
# directories in a temp dir; no docker or network needed.
#
# Usage: scripts/hooks/tests/test-lua-hooks.sh
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass(){ PASS=$((PASS + 1)); echo "  ok   $1"; }
fail(){ FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

assert_file(){ [ -f "$1" ] && pass "$2" || fail "$2 (missing $1)"; }
assert_no_path(){ [ ! -e "$1" ] && pass "$2" || fail "$2 (unexpected $1)"; }
assert_eq(){ [ "$1" = "$2" ] && pass "$3" || fail "$3 (expected '$2', got '$1')"; }

# run_hook <hook> <module_dir> <target|""> [module_name]
# Sets HOOK_RC and HOOK_OUT.
run_hook(){
  local hook="$1" dir="$2" target="$3" name="${4-}"
  HOOK_OUT="$(env -u LUA_SCRIPTS_TARGET -u MODULE_NAME \
    MODULE_KEY="MODULE_TEST" MODULE_DIR="$dir" \
    ${name:+MODULE_NAME="$name"} \
    ${target:+LUA_SCRIPTS_TARGET="$target"} \
    "$HOOKS_DIR/$hook" 2>&1)"
  HOOK_RC=$?
}

mk(){ mkdir -p "$(dirname "$1")"; echo "-- $1" > "$1"; }

echo "copy-standard-lua"
M="$WORK/mod-std"
mk "$M/root.lua"
mk "$M/lua_scripts/a.lua"
mk "$M/scripts/b.lua"
mk "$M/Server Files/lua_scripts/c.lua"
mk "$M/README.md"
T="$WORK/target1"
run_hook copy-standard-lua "$M" "$T" "mod-std"
assert_eq "$HOOK_RC" 0 "exits 0 when scripts are staged"
assert_file "$T/mod-std/root.lua" "stages root-level Lua into module subfolder"
assert_file "$T/mod-std/a.lua" "stages lua_scripts/*.lua"
assert_file "$T/mod-std/b.lua" "stages scripts/*.lua"
assert_file "$T/mod-std/c.lua" "stages paths containing spaces"
assert_no_path "$T/root.lua" "does not write to the target root"
assert_no_path "$T/mod-std/README.md" "copies only .lua files"

rm "$M/root.lua"
run_hook copy-standard-lua "$M" "$T" "mod-std"
assert_no_path "$T/mod-std/root.lua" "re-run removes scripts deleted upstream"

mk "$T/user-script.lua"
run_hook copy-standard-lua "$M" "$T" "mod-std"
assert_file "$T/user-script.lua" "leaves files outside the module subfolder alone"

run_hook copy-standard-lua "$M" "" "mod-std"
assert_eq "$HOOK_RC" 0 "no target configured: exits 0"
case "$HOOK_OUT" in *skipping*) pass "no target configured: says it is skipping";;
  *) fail "no target configured: says it is skipping (got: $HOOK_OUT)";; esac

run_hook copy-standard-lua "$M" "$WORK/target-noname"
assert_file "$WORK/target-noname/mod-std/a.lua" "falls back to basename of MODULE_DIR when MODULE_NAME is empty"

RO="$WORK/readonly"
mkdir -p "$RO"; chmod 555 "$RO"
run_hook copy-standard-lua "$M" "$RO/lua" "mod-std"
if [ "$(id -u)" -eq 0 ]; then
  echo "  skip unwritable target (running as root)"
else
  assert_eq "$HOOK_RC" 2 "unwritable target: exits 2 (error), not success"
fi

E="$WORK/mod-empty"; mkdir -p "$E"; mk "$E/README.md"
T2="$WORK/target2"
run_hook copy-standard-lua "$E" "$T2" "mod-empty"
assert_eq "$HOOK_RC" 1 "no Lua found: exits 1 (warning)"
assert_no_path "$T2/mod-empty" "no Lua found: leaves no empty subfolder"

echo "copy-aio-lua"
A="$WORK/aio-mod"
mk "$A/Server/s.lua"
mk "$A/Client/c.lua"
T3="$WORK/target3"
run_hook copy-aio-lua "$A" "$T3" "aio-mod"
assert_eq "$HOOK_RC" 0 "exits 0 when scripts are staged"
assert_file "$T3/aio-mod/s.lua" "stages Server/*.lua"
assert_no_path "$T3/aio-mod/c.lua" "does not stage client files"

echo "copy-aio-server"
S="$WORK/mod-aio"
mk "$S/AIO_Server/AIO.lua"
mk "$S/AIO_Server/queue.lua"
mk "$S/AIO_Server/Dep_Smallfolk/smallfolk.lua"
mk "$S/AIO_Client/AIO.lua"
mk "$S/Examples/HelloWorld.lua"
T4="$WORK/target4"
run_hook copy-aio-server "$S" "$T4" "mod-aio"
assert_eq "$HOOK_RC" 0 "exits 0 when scripts are staged"
assert_file "$T4/mod-aio/AIO.lua" "stages AIO_Server/AIO.lua"
assert_file "$T4/mod-aio/Dep_Smallfolk/smallfolk.lua" "preserves AIO_Server subdirectories"
assert_eq "$(find "$T4" -name AIO.lua | wc -l | tr -d ' ')" 1 "does not stage AIO_Client (duplicate AIO.lua)"
assert_no_path "$T4/mod-aio/HelloWorld.lua" "does not stage examples"

echo "black-market-setup"
B="$WORK/Black-Market"
mk "$B/Server Files/lua_scripts/bm.lua"
mk "$B/Server Files/lua_scripts/sub/bm2.lua"
mk "$B/Client Files/AddOns/x.lua"
T5="$WORK/target5"
run_hook black-market-setup "$B" "$T5" "Black-Market"
assert_eq "$HOOK_RC" 0 "exits 0 when scripts are staged"
assert_file "$T5/Black-Market/bm.lua" "stages Server Files/lua_scripts"
assert_file "$T5/Black-Market/sub/bm2.lua" "preserves subdirectories"
assert_no_path "$T5/Black-Market/x.lua" "does not stage client addon files"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

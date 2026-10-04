#!/bin/bash
# rebuild-with-modules.sh copies the staged modules into the core source tree
# before compiling. Only enabled modules may go in: a checkout left in staging
# by a module that is no longer enabled or no longer in the manifest (e.g. its
# manifest entry was lost) used to be copied in and compiled anyway. Directories
# left in the source tree by earlier builds must go too, whatever their name.
#
# Extracts sync_modules_into_source() with sed so rebuild-with-modules.sh's
# main never runs. No docker or network needed.
#
# Usage: scripts/bash/tests/test-rebuild-source-sync.sh
set -uo pipefail

REBUILD_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/bash/rebuild-with-modules.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

FUNC_FILE="$WORK/sync.sh"
sed -n '/^sync_modules_into_source(){/,/^}/p' "$REBUILD_SH" > "$FUNC_FILE"
if ! grep -q '^sync_modules_into_source(){' "$FUNC_FILE"; then
  echo "FAIL: could not extract sync_modules_into_source() from $REBUILD_SH" >&2
  exit 1
fi

# setup <dir>: staging and a source modules/ dir as left by an earlier build.
setup(){
  local root="$1"
  mkdir -p "$root/staging" "$root/source/modules"
  # staging: two enabled modules, one disabled, one no longer in the manifest
  mkdir -p "$root/staging/mod-a/src" "$root/staging/Other_Enabled/src" \
    "$root/staging/mod-disabled/src" "$root/staging/mod-orphan/src" "$root/staging/.modules-meta"
  touch "$root/staging/mod-a/src/a.cpp" "$root/staging/Other_Enabled/src/o.cpp" \
    "$root/staging/mod-disabled/src/d.cpp" "$root/staging/mod-orphan/src/x.cpp" \
    "$root/staging/.modules-meta/m" "$root/staging/modules.env"
  # source: core-tracked files plus directories from earlier builds
  touch "$root/source/modules/CMakeLists.txt" "$root/source/modules/.gitkeep"
  mkdir -p "$root/source/modules/mod-old/src" "$root/source/modules/Acore_eventScripts" \
    "$root/source/modules/mod-a/stale"
  touch "$root/source/modules/mod-old/src/old.cpp"
}

# run <dir> [PATH]: run the sync. Sets OUT and RC.
run(){
  local root="$1" path="${2:-$PATH}"
  OUT="$(cd "$root/source" && PATH="$path" bash -c '
    source "$1"
    sync_modules_into_source "$2" modules "mod-a Other_Enabled"
  ' _ "$FUNC_FILE" "$root/staging" 2>&1)"
  RC=$?
}

listing(){ (cd "$1/source/modules" && find . -mindepth 1 -maxdepth 1 | sed 's|^\./||' | sort | tr '\n' ' '); }

expect='.gitkeep .modules-meta CMakeLists.txt Other_Enabled mod-a modules.env '

echo "with rsync"
setup "$WORK/r"
run "$WORK/r"
check "exit status" "$RC" "0"
check "only enabled modules, metadata and core files" "$(listing "$WORK/r")" "$expect"
check "enabled module copied" "$([ -f "$WORK/r/source/modules/mod-a/src/a.cpp" ] && echo yes)" "yes"
check "old content of an enabled module replaced" "$([ -e "$WORK/r/source/modules/mod-a/stale" ] && echo kept || echo gone)" "gone"
check "names the skipped modules" "$(grep -c 'mod-disabled' <<<"$OUT")$(grep -c 'mod-orphan' <<<"$OUT")" "11"
check "staging untouched" "$([ -d "$WORK/r/staging/mod-orphan" ] && echo yes)" "yes"

echo "without rsync (cp fallback)"
setup "$WORK/c"
BIN="$WORK/bin"
mkdir -p "$BIN"
for tool in bash find rm cp mkdir basename sed sort tr; do ln -sf "$(command -v "$tool")" "$BIN/$tool"; done
run "$WORK/c" "$BIN"
check "exit status" "$RC" "0"
check "only enabled modules, metadata and core files" "$(listing "$WORK/c")" "$expect"

echo "nothing enabled"
setup "$WORK/n"
OUT="$(cd "$WORK/n/source" && bash -c 'source "$1"; sync_modules_into_source "$2" modules ""' _ "$FUNC_FILE" "$WORK/n/staging" 2>&1)"
check "no module directories" "$(listing "$WORK/n")" ".gitkeep .modules-meta CMakeLists.txt modules.env "

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

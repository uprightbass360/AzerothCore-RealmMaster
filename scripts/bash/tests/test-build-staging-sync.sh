#!/bin/bash
# Tests for build.sh's sync_staged_modules (the staging sync inside
# stage_modules): it must not delete the C++ build record
# (.built-modules, see lib/module-build-record.sh) while still honouring
# the existing excludes and --delete/copy semantics.
#
# Extracts sync_staged_modules() straight out of build.sh with sed so this
# never sources (and never runs) build.sh's main. Does not touch build.sh,
# docker, deploy.sh or manage-modules.sh.
#
# Usage: scripts/bash/tests/test-build-staging-sync.sh
set -uo pipefail

BUILD_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/build.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# Extract sync_staged_modules() out of build.sh, unsourced otherwise.
FUNC_FILE="$WORK/sync_staged_modules.sh"
sed -n '/^sync_staged_modules(){/,/^}/p' "$BUILD_SH" > "$FUNC_FILE"
if ! grep -q '^sync_staged_modules(){' "$FUNC_FILE"; then
  echo "FAIL: could not extract sync_staged_modules() from $BUILD_SH" >&2
  exit 1
fi

# A bin dir holding only the tools the fallback branch needs (find, rm, tar,
# cp) so a subshell using it as its whole PATH has no rsync on it, forcing
# `command -v rsync` to fail and exercising the find+tar fallback branch.
FALLBACK_BIN="$WORK/fallback-bin"
mkdir -p "$FALLBACK_BIN"
for tool in find rm tar cp; do
  tool_path="$(command -v "$tool")" || { echo "FAIL: $tool not found on PATH" >&2; exit 1; }
  ln -s "$tool_path" "$FALLBACK_BIN/$tool"
done
BASH_BIN="$(command -v bash)"

# make_fixture <case-dir-name>: local_modules_dir (source) and
# staging_modules_dir (destination) populated with the fixtures every case
# checks, under $WORK/<name>/{local,staging}.
make_fixture(){
  local base="$WORK/$1"
  local local_dir="$base/local"
  local staging_dir="$base/staging"
  mkdir -p "$local_dir" "$staging_dir/.modules-meta"

  # Only in staging: the build record and the other files the existing
  # excludes protect.
  echo "mod-a" > "$staging_dir/.built-modules"
  echo "sentinel" > "$staging_dir/.requires_rebuild"
  echo "MODULE_A=1" > "$staging_dir/modules.env"
  echo "mod-a" > "$staging_dir/.modules-meta/modules-enabled.txt"

  # Only in staging, not excluded: must be removed (--delete semantics).
  mkdir -p "$staging_dir/stale-module"
  echo "junk" > "$staging_dir/stale-module/file.txt"

  # Only in the source dir: must be copied over.
  mkdir -p "$local_dir/new-module"
  echo "hello" > "$local_dir/new-module/file.txt"

  echo "$base"
}

# run_sync <mode: rsync|fallback> <local_dir> <staging_dir>
run_sync(){
  local mode="$1" local_dir="$2" staging_dir="$3"
  case "$mode" in
    rsync)
      bash -c 'source "$1"; sync_staged_modules "$2" "$3"' _ "$FUNC_FILE" "$local_dir" "$staging_dir"
      ;;
    fallback)
      PATH="$FALLBACK_BIN" "$BASH_BIN" -c 'source "$1"; sync_staged_modules "$2" "$3"' _ "$FUNC_FILE" "$local_dir" "$staging_dir"
      ;;
  esac
}

# assert_case <mode>: runs a fresh fixture through the given branch and
# checks all four required outcomes.
assert_case(){
  local mode="$1"
  local base
  base="$(make_fixture "$mode")"
  local local_dir="$base/local"
  local staging_dir="$base/staging"

  if ! command -v rsync >/dev/null 2>&1 && [ "$mode" = "rsync" ]; then
    echo "SKIP: rsync branch requires rsync on PATH" >&2
    return
  fi

  run_sync "$mode" "$local_dir" "$staging_dir" 2>"$base/err"
  local rc=$?
  check "$mode: sync exits 0" "$rc" "0"

  [ -f "$staging_dir/.built-modules" ]
  check "$mode: .built-modules survives" "$?" "0"

  [ -f "$staging_dir/.requires_rebuild" ]
  check "$mode: .requires_rebuild survives" "$?" "0"

  [ -f "$staging_dir/modules.env" ]
  check "$mode: modules.env survives" "$?" "0"

  [ -f "$staging_dir/.modules-meta/modules-enabled.txt" ]
  check "$mode: .modules-meta/modules-enabled.txt survives" "$?" "0"

  [ -e "$staging_dir/stale-module" ]
  check "$mode: staging-only module folder is removed" "$?" "1"

  [ -f "$staging_dir/new-module/file.txt" ]
  check "$mode: source-only module folder is copied" "$?" "0"
}

echo "rsync branch"
assert_case rsync

echo "fallback branch (find+tar, no rsync on PATH)"
# Sanity: prove the fallback subshell really has no rsync before trusting
# its results.
if PATH="$FALLBACK_BIN" "$BASH_BIN" -c 'command -v rsync' >/dev/null 2>&1; then
  echo "FAIL: fallback PATH unexpectedly has rsync" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
  echo "  ok   fallback PATH has no rsync"
fi
assert_case fallback

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

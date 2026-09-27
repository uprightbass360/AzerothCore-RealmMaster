#!/bin/bash
# On playerbots stacks the core fork (local-storage/source/azerothcore-playerbots,
# branch Playerbot) and mod-playerbots must move together: mod-playerbots's HEAD
# regularly needs newer core symbols than an older compiled core provides. This
# tests build.sh's decision of whether ensure_source_repo should re-run
# setup-source.sh for an *existing* checkout, plus the two small helpers around
# it (reading MODULE_PLAYERBOTS's effective pinned ref, and the pin notice
# text) - all pure functions with no side effects.
#
# Extracts the functions straight out of build.sh with sed so this never
# sources (and never runs) build.sh's main (it calls `main "$@"`
# unconditionally at the end). Does not touch build.sh, docker, deploy.sh,
# setup-source.sh or manage-modules.sh.
#
# Usage: scripts/bash/tests/test-core-source-update.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_SH="$REPO_ROOT/build.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# Extract a single function out of build.sh, unsourced otherwise.
extract(){
  local func="$1"
  if ! grep -q "^${func}(){" "$BUILD_SH"; then
    echo "FAIL: $func() not found in $BUILD_SH" >&2
    exit 1
  fi
  sed -n "/^${func}(){/,/^}/p" "$BUILD_SH" >> "$FUNC_FILE"
}

FUNC_FILE="$WORK/funcs.sh"
: > "$FUNC_FILE"
extract core_source_update_reason
extract core_source_pin_notice
extract playerbots_pinned_ref

echo "=== core_source_update_reason ==="

run_reason(){
  bash -c 'source "$1"; core_source_update_reason "$2" "$3" "$4"' _ "$FUNC_FILE" "$1" "$2" "$3"
}

# run_reason <use_playerbot_source> <force_update> <playerbots_ref>
r="$(run_reason 1 0 "")"
check "playerbots+unpinned -> update (non-empty reason)" "$([ -n "$r" ] && echo yes || echo no)" "yes"

r="$(run_reason 1 0 "v1.2.3")"
check "playerbots+pinned -> no update (empty reason)" "$r" ""

r="$(run_reason 0 0 "")"
check "standard (no playerbots) -> no update" "$r" ""

r="$(run_reason 1 1 "")"
check "FORCE_UPDATE=1, playerbots+unpinned -> update" "$([ -n "$r" ] && echo yes || echo no)" "yes"

r="$(run_reason 1 1 "v1.2.3")"
check "FORCE_UPDATE=1, playerbots+pinned -> update anyway" "$([ -n "$r" ] && echo yes || echo no)" "yes"

r="$(run_reason 0 1 "")"
check "FORCE_UPDATE=1, standard -> update anyway" "$([ -n "$r" ] && echo yes || echo no)" "yes"

echo "=== core_source_pin_notice ==="

msg="$(bash -c 'source "$1"; core_source_pin_notice "$2"' _ "$FUNC_FILE" "v1.2.3")"
case "$msg" in
  *"pinned to v1.2.3"*"--force-update"*) r=yes;; *) r=no;;
esac
check "pin notice mentions the ref and --force-update" "$r" "yes"

echo "=== playerbots_pinned_ref ==="

# make_manifest_dir: a temp config dir with an upstream manifest, optionally
# overlaid by a local manifest pinning MODULE_PLAYERBOTS.
CONFIG_DIR="$WORK/config"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/module-manifest.json" <<'EOF'
{"modules": [
  {"key": "MODULE_PLAYERBOTS", "name": "mod-playerbots", "repo": "https://example.com/mod-playerbots.git", "type": "cpp"}
]}
EOF

ref="$(bash -c 'source "$1"; playerbots_pinned_ref "$2" "$3"' _ "$FUNC_FILE" "$CONFIG_DIR/module-manifest.json" "$REPO_ROOT/scripts/python/modules.py")"
check "upstream manifest without ref -> empty" "$ref" ""

cat > "$CONFIG_DIR/module-manifest.local.json" <<'EOF'
{"modules": [
  {"key": "MODULE_PLAYERBOTS", "ref": "Playerbot-pinned-sha"}
]}
EOF

ref="$(bash -c 'source "$1"; playerbots_pinned_ref "$2" "$3"' _ "$FUNC_FILE" "$CONFIG_DIR/module-manifest.json" "$REPO_ROOT/scripts/python/modules.py")"
check "local manifest pinning MODULE_PLAYERBOTS -> that ref" "$ref" "Playerbot-pinned-sha"

echo "=== update_core_source_if_needed ==="

# ensure_source_repo runs before detect_rebuild_reasons/confirm_build, so it
# must never update an *existing* checkout itself (fix round 1, item 1):
# every build.sh run that ends in "no build required" - and update-latest.sh,
# which runs build.sh --yes unconditionally - would otherwise move the core
# source (whose data/sql is mounted into ac-db-import/ac-db-guard) without
# pulling mod-playerbots or compiling. update_core_source_if_needed is called
# from main() only after confirm_build has decided a build will happen.
extract update_core_source_if_needed
cat >> "$FUNC_FILE" <<'EOF'

# Test stub: the real requires_playerbot_source depends on the full
# module-state machinery (generate_module_state, .env, the manifest).
# STUB_USE_PLAYERBOT lets the test drive update_core_source_if_needed's
# "playerbots in use" branch directly.
requires_playerbot_source(){
  [ "${STUB_USE_PLAYERBOT:-0}" = "1" ]
}
EOF

# A temp "ROOT_DIR" with a stub scripts/bash/setup-source.sh (records that it
# ran and exits with a controllable code) and a plain unpinned manifest.
UROOT="$WORK/uroot"
mkdir -p "$UROOT/scripts/bash" "$UROOT/config"
SETUP_LOG="$WORK/setup-source-calls.log"
cat > "$UROOT/scripts/bash/setup-source.sh" <<EOF
#!/bin/bash
echo called >> "$SETUP_LOG"
exit "\${STUB_SETUP_SOURCE_EXIT:-0}"
EOF
chmod +x "$UROOT/scripts/bash/setup-source.sh"
cat > "$UROOT/config/module-manifest.json" <<'EOF'
{"modules": [
  {"key": "MODULE_PLAYERBOTS", "name": "mod-playerbots", "repo": "https://example.com/mod-playerbots.git", "type": "cpp"}
]}
EOF

# A second ROOT_DIR whose MODULE_PLAYERBOTS is pinned via a local override.
UROOT_PINNED="$WORK/uroot-pinned"
mkdir -p "$UROOT_PINNED/scripts/bash" "$UROOT_PINNED/config"
cp "$UROOT/scripts/bash/setup-source.sh" "$UROOT_PINNED/scripts/bash/setup-source.sh"
cp "$UROOT/config/module-manifest.json" "$UROOT_PINNED/config/module-manifest.json"
cat > "$UROOT_PINNED/config/module-manifest.local.json" <<'EOF'
{"modules": [
  {"key": "MODULE_PLAYERBOTS", "ref": "Playerbot-pinned-sha"}
]}
EOF

# A third ROOT_DIR with no manifest at all, so playerbots_pinned_ref fails to
# read/parse it (simulates a broken or unreadable manifest).
UROOT_BADMANIFEST="$WORK/uroot-badmanifest"
mkdir -p "$UROOT_BADMANIFEST/scripts/bash"
cp "$UROOT/scripts/bash/setup-source.sh" "$UROOT_BADMANIFEST/scripts/bash/setup-source.sh"

SRC_WITH_GIT="$WORK/src-with-git"
mkdir -p "$SRC_WITH_GIT/.git"
SRC_NO_GIT="$WORK/src-no-git"
mkdir -p "$SRC_NO_GIT"

# run_update <root_dir> <use_playerbot> <force_update> <setup_source_exit> [src_dir]:
# sources common.sh (for info/warn/err) plus the extracted/stubbed functions,
# then calls update_core_source_if_needed against the given fixture. Sets
# OUT and RC; resets the setup-source.sh call log first so `called` (below)
# reflects only this call.
run_update(){
  local root_dir="$1" use_playerbot="$2" force_update="$3" setup_exit="$4"
  local src="${5:-$SRC_WITH_GIT}"
  rm -f "$SETUP_LOG"
  OUT="$(
    STUB_USE_PLAYERBOT="$use_playerbot" FORCE_UPDATE="$force_update" \
    STUB_SETUP_SOURCE_EXIT="$setup_exit" \
    ROOT_DIR="$root_dir" MODULE_HELPER="$REPO_ROOT/scripts/python/modules.py" \
    bash -c '
      source "'"$REPO_ROOT"'/scripts/bash/lib/common.sh"
      source "$1"
      update_core_source_if_needed "$2"
    ' _ "$FUNC_FILE" "$src" 2>&1
  )"
  RC=$?
}
called(){ [ -f "$SETUP_LOG" ] && echo yes || echo no; }

echo "standard (no playerbots), FORCE_UPDATE=0: not called"
run_update "$UROOT" 0 0 0
check "returns 0" "$RC" "0"
check "setup-source.sh NOT called" "$(called)" "no"

echo "playerbots + pinned, FORCE_UPDATE=0: not called, prints the pin notice"
run_update "$UROOT_PINNED" 1 0 0
check "returns 0" "$RC" "0"
check "setup-source.sh NOT called" "$(called)" "no"
case "$OUT" in *"pinned to Playerbot-pinned-sha"*"--force-update"*) r=yes;; *) r=no;; esac
check "prints the pin notice" "$r" "yes"

echo "playerbots + unpinned, FORCE_UPDATE=0, update succeeds"
run_update "$UROOT" 1 0 0
check "returns 0" "$RC" "0"
check "setup-source.sh IS called" "$(called)" "yes"
case "$OUT" in *"mod-playerbots is unpinned"*) r=yes;; *) r=no;; esac
check "prints the unpinned-update message" "$r" "yes"

echo "playerbots + unpinned, FORCE_UPDATE=0, update fails: warns and returns 0"
run_update "$UROOT" 1 0 1
check "returns 0 (not fatal)" "$RC" "0"
check "setup-source.sh IS called" "$(called)" "yes"
case "$OUT" in *"Could not update the core source; building with the current core"*) r=yes;; *) r=no;; esac
check "warns instead of failing" "$r" "yes"

echo "FORCE_UPDATE=1, update succeeds: called regardless of playerbots/pin state"
run_update "$UROOT" 0 1 0
check "returns 0" "$RC" "0"
check "setup-source.sh IS called" "$(called)" "yes"
case "$OUT" in *"Force update requested"*) r=yes;; *) r=no;; esac
check "prints the forced-update message" "$r" "yes"

echo "FORCE_UPDATE=1, update fails: fatal (non-zero)"
run_update "$UROOT" 0 1 1
check "returns non-zero" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"
check "setup-source.sh IS called" "$(called)" "yes"
case "$OUT" in *"Failed to update source repository"*) r=yes;; *) r=no;; esac
check "prints the failure message" "$r" "yes"

echo "missing checkout (no .git): not called, regardless of flags"
run_update "$UROOT" 1 1 0 "$SRC_NO_GIT"
check "returns 0" "$RC" "0"
check "setup-source.sh NOT called" "$(called)" "no"

echo "manifest can't be read: treated as don't-know, not unpinned"
run_update "$UROOT_BADMANIFEST" 1 0 0
check "returns 0" "$RC" "0"
check "setup-source.sh NOT called" "$(called)" "no"
case "$OUT" in *"Could not read mod-playerbots"*"pinned ref"*) r=yes;; *) r=no;; esac
check "warns that the ref could not be read" "$r" "yes"

echo "manifest can't be read, but FORCE_UPDATE=1: forced still wins"
run_update "$UROOT_BADMANIFEST" 1 1 0
check "returns 0" "$RC" "0"
check "setup-source.sh IS called" "$(called)" "yes"
case "$OUT" in *"Force update requested"*) r=yes;; *) r=no;; esac
check "prints the forced-update message" "$r" "yes"

echo "=== structural: build.sh wiring ==="

# update_core_source_if_needed must run after confirm_build succeeds and
# before sync_modules/stage_modules (moving the source only once a build is
# confirmed to actually happen).
confirm_line="$(grep -n 'if ! confirm_build' "$BUILD_SH" | head -1 | cut -d: -f1)"
# shellcheck disable=SC2016  # literal pattern, nothing to expand
update_call_line="$(grep -n 'update_core_source_if_needed "\$src_dir"' "$BUILD_SH" | tail -1 | cut -d: -f1)"
sync_call_line="$(grep -n '^  sync_modules$' "$BUILD_SH" | tail -1 | cut -d: -f1)"

check_order(){
  if [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ "$2" -lt "$3" ] 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ok   $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL $1 (lines: ${2:-<missing>}, ${3:-<missing>})"
  fi
}
check_order "confirm_build runs before update_core_source_if_needed" "$confirm_line" "$update_call_line"
check_order "update_core_source_if_needed runs before sync_modules/stage_modules" "$update_call_line" "$sync_call_line"

# ensure_source_repo's existing-checkout branch must not call setup-source.sh
# itself any more (only update_core_source_if_needed should, once main knows
# a build will happen).
# shellcheck disable=SC2016  # literal pattern, nothing to expand
EXISTING_CHECKOUT_BLOCK="$(sed -n '/^ensure_source_repo(){/,/^}/p' "$BUILD_SH" \
  | sed -n '/if \[ -d "\$src_path\/\.git" \]; then/,/return/p')"
if [ -z "$EXISTING_CHECKOUT_BLOCK" ]; then
  echo "FAIL: could not locate ensure_source_repo's existing-checkout branch" >&2
  FAIL=$((FAIL + 1))
else
  case "$EXISTING_CHECKOUT_BLOCK" in
    *setup-source.sh*) r=no;; *) r=yes;;
  esac
  check "ensure_source_repo's existing-checkout branch doesn't call setup-source.sh" "$r" "yes"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

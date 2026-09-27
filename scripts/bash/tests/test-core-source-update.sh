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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

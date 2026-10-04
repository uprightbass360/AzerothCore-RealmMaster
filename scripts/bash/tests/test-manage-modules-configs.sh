#!/bin/bash
# pass/fail never fail, so A && pass || fail is safe here.
# shellcheck disable=SC2015
# Edits to storage/config/modules/*.conf must survive a redeploy: each
# manage-modules.sh pass refreshes the shipped .conf.dist files but only seeds a
# .conf when none exists. Configs left behind by modules that are gone are
# removed only while they still match their shipped default.
# Runs the real manage-modules.sh functions (sourced, main not run) against temp
# dirs. No docker or network needed.
#
# Usage: scripts/bash/tests/test-manage-modules-configs.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Sourcing manage-modules.sh without its main guard would run a real module pass
# in the current directory; refuse rather than risk that.
# shellcheck disable=SC2016  # literal pattern, nothing to expand
grep -q '^if \[\[ "${BASH_SOURCE\[0\]}" == "$0" \]\]; then' "$REPO_ROOT/scripts/bash/manage-modules.sh" \
  || { echo "manage-modules.sh has no main guard; not sourcing it" >&2; exit 1; }

PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); echo "  ok   $1"; }
fail(){ FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

ROOT="$WORK/root"
ETC="$ROOT/etc"
CONFS="$ETC/modules"
mkdir -p "$ROOT/config" "$ROOT/modules/mod-a/conf" "$ROOT/modules/mod-b/conf" "$ROOT/state"
cat > "$ROOT/config/module-manifest.json" <<'EOF'
{"modules": [
  {"key": "MODULE_A", "name": "mod-a", "repo": "https://example.com/mod-a.git", "type": "cpp"},
  {"key": "MODULE_B", "name": "mod-b", "repo": "https://example.com/mod-b.git", "type": "cpp"}
]}
EOF
printf 'MODULE_A=1\nMODULE_B=1\n' > "$ROOT/.env"
echo 'A.Setting = 1' > "$ROOT/modules/mod-a/conf/a.conf.dist"
# Some modules ship a plain .conf instead of a .conf.dist.
echo 'B.Setting = 1' > "$ROOT/modules/mod-b/conf/b.conf"

module_pass(){
  MODULES_ENV_PATH="$ROOT/.env" MODULES_LOCAL_RUN=1 MODULES_ENV_TARGET_DIR="$ETC" bash -c '
    set -e
    source "$1/scripts/bash/manage-modules.sh"
    cd "$2/modules"
    MANIFEST_PATH="$2/config/module-manifest.json"
    STATE_DIR="$2/state"
    generate_module_state
    manage_configuration_files
    echo "PASS_DONE"
  ' _ "$REPO_ROOT" "$ROOT" 2>&1
}

echo "first deploy seeds configs"
out="$(module_pass)"
case "$out" in *PASS_DONE*) pass "module pass completes";; *) fail "module pass completes"; echo "$out";; esac
grep -qx 'A.Setting = 1' "$CONFS/a.conf" 2>/dev/null && pass "a.conf seeded from .dist" || fail "a.conf seeded from .dist"
[ -f "$CONFS/a.conf.dist" ] && pass "a.conf.dist staged" || fail "a.conf.dist staged"
grep -qx 'B.Setting = 1' "$CONFS/b.conf" 2>/dev/null && pass "plain b.conf seeded" || fail "plain b.conf seeded"

echo "redeploy after editing configs and a new upstream default"
echo 'A.Setting = 42' > "$CONFS/a.conf"
echo 'B.Setting = 42' > "$CONFS/b.conf"
echo 'A.Setting = 2' > "$ROOT/modules/mod-a/conf/a.conf.dist"
# Left behind by modules that are no longer installed: one untouched, one edited.
echo 'Gone.Setting = 1' > "$CONFS/gone.conf"
echo 'Gone.Setting = 1' > "$CONFS/gone.conf.dist"
echo 'Old.Setting = 42' > "$CONFS/old.conf"
echo 'Old.Setting = 1' > "$CONFS/old.conf.dist"
out="$(module_pass)"
case "$out" in *PASS_DONE*) pass "module pass completes";; *) fail "module pass completes"; echo "$out";; esac
grep -qx 'A.Setting = 42' "$CONFS/a.conf" && pass "edited a.conf kept" || fail "edited a.conf kept"
grep -qx 'A.Setting = 2' "$CONFS/a.conf.dist" && pass "a.conf.dist refreshed" || fail "a.conf.dist refreshed"
grep -qx 'B.Setting = 42' "$CONFS/b.conf" && pass "edited plain b.conf kept" || fail "edited plain b.conf kept"
[ ! -e "$CONFS/gone.conf" ] && pass "untouched config of removed module deleted" || fail "untouched config of removed module deleted"
[ -f "$CONFS/old.conf" ] && pass "edited config of removed module kept" || fail "edited config of removed module kept"
[ ! -e "$CONFS/gone.conf.dist" ] && [ ! -e "$CONFS/old.conf.dist" ] \
  && pass "removed modules' .dist files deleted" || fail "removed modules' .dist files deleted"
case "$out" in *old.conf*) pass "kept config is reported";; *) fail "kept config is reported"; echo "$out";; esac

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

#!/bin/bash
# Tests for lib/module-build-record.sh (the "which C++ modules are in the
# current image" record used by deploy.sh and build.sh).
#
# Usage: scripts/bash/tests/test-module-build-record.sh
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=../lib/module-build-record.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/module-build-record.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

F="$(module_build_record_file "$WORK/local-storage/")"
check "record lives under modules/" "$F" "$WORK/local-storage/modules/.built-modules"

out="$(module_build_record_reason "$F" mod-b mod-a 2>"$WORK/err")"
check "no record: no rebuild reason" "$out" ""
check "no record: seeds the enabled set" "$(tr '\n' ' ' < "$F")" "mod-a mod-b "
grep -q "run ./build.sh --force" "$WORK/err"; check "no record: prints a notice" "$?" "0"

out="$(module_build_record_reason "$F" mod-a mod-b 2>&1)"
check "unchanged set: no reason" "$out" ""

out="$(module_build_record_reason "$F" mod-a mod-b mod-c)"
check "added module" "$out" "Enabled C++ modules changed since last build (added: mod-c)"

out="$(module_build_record_reason "$F" mod-a)"
check "removed module" "$out" "Enabled C++ modules changed since last build (removed: mod-b)"

out="$(module_build_record_reason "$F" mod-a mod-c)"
check "added and removed" "$out" "Enabled C++ modules changed since last build (added: mod-c; removed: mod-b)"

out="$(module_build_record_reason "$F")"
check "all modules disabled" "$out" "Enabled C++ modules changed since last build (removed: mod-a mod-b)"

module_build_record_write "$F" mod-c mod-a
out="$(module_build_record_reason "$F" mod-a mod-c)"
check "after a build records the set: no reason" "$out" ""

module_build_record_write "$F"
out="$(module_build_record_reason "$F")"
check "empty set recorded and enabled: no reason" "$out" ""

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

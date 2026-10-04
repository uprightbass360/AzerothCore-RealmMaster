#!/bin/bash
# stage-modules.sh picks which compose service profile runs the realm. A
# prebuilt install (.env.prebuilt: STACK_IMAGE_MODE=modules) only has the
# Docker Hub *_MODULES images, even though playerbots is enabled; picking the
# playerbots profile made compose pull local-only image names and fail.
#
# Extracts detect_target_profile() with sed so stage-modules.sh never runs.
#
# Usage: scripts/bash/tests/test-stage-profile.sh
set -uo pipefail

STAGE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/bash/stage-modules.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

sed -n '/^detect_target_profile(){/,/^}/p' "$STAGE_SH" > "$WORK/f.sh"
grep -q '^detect_target_profile(){' "$WORK/f.sh" \
  || { echo "FAIL: could not extract detect_target_profile() from $STAGE_SH" >&2; exit 1; }
# shellcheck disable=SC1091
source "$WORK/f.sh"

# detect_target_profile <playerbots enabled 0|1> <STACK_IMAGE_MODE> <C++ module count>
check "prebuilt: playerbots on, image mode modules" "$(detect_target_profile 1 modules 30)" "modules"
check "source build with playerbots" "$(detect_target_profile 1 playerbots 30)" "playerbots"
check "playerbots on, image mode unset (older .env)" "$(detect_target_profile 1 "" 30)" "playerbots"
check "C++ modules, no playerbots" "$(detect_target_profile 0 modules 3)" "modules"
check "C++ modules, image mode unset" "$(detect_target_profile 0 "" 3)" "modules"
check "nothing to compile" "$(detect_target_profile 0 standard 0)" "standard"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

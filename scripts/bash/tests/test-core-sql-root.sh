#!/bin/bash
# db-import-conditional.sh and db-guard.sh pick where the core SQL comes from:
# the source checkout's data/sql (mounted at /source/data/sql) when it is
# there, otherwise the SQL inside the db-import image. Prebuilt installs have
# no source checkout; mounting the (empty) checkout path over the image's
# /azerothcore/data/sql used to hide that SQL and fail every fresh install.
#
# Extracts the resolution block from both scripts with sed; no docker needed.
#
# Usage: scripts/bash/tests/test-core-sql-root.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

for script in db-import-conditional.sh db-guard.sh; do
  echo "$script"
  block="$WORK/$script.block"
  sed -n '/^# Core SQL:/,/^CORE_SQL_ROOT=/p' "$REPO_ROOT/scripts/bash/$script" > "$block"
  if ! grep -q '^CORE_SQL_ROOT=' "$block"; then
    FAIL=$((FAIL + 1)); echo "  FAIL could not extract the core SQL block"; continue
  fi

  # shellcheck disable=SC2016  # expanded by the inner bash
  resolve(){ env -u AC_SOURCE_DIRECTORY CORE_SQL_SOURCE_MOUNT="$1" bash -c 'source "$1"; echo "$CORE_SQL_ROOT|${AC_SOURCE_DIRECTORY:-}"' _ "$block"; }

  mkdir -p "$WORK/src/data/sql/base/db_world"
  check "source checkout mounted: use it" "$(resolve "$WORK/src")" "$WORK/src/data/sql|$WORK/src"
  mkdir -p "$WORK/empty/data/sql"
  check "empty mount (prebuilt): image SQL" "$(resolve "$WORK/empty")" "/azerothcore/data/sql|"
  check "no mount at all: image SQL" "$(resolve "$WORK/missing")" "/azerothcore/data/sql|"
done

echo "no hard-coded core SQL path left"
check "db-import-conditional.sh" "$(grep -c '"/azerothcore/data/sql' "$REPO_ROOT/scripts/bash/db-import-conditional.sh")" "0"
check "db-guard.sh" "$(grep -c '"/azerothcore/data/sql' "$REPO_ROOT/scripts/bash/db-guard.sh")" "0"
check "compose mounts nothing over /azerothcore/data/sql" "$(grep -c ':/azerothcore/data/sql' "$REPO_ROOT/docker-compose.yml")" "0"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

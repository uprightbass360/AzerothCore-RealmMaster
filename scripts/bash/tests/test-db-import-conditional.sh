#!/bin/bash
# Safety tests for db-import-conditional.sh: it must never restore a backup over,
# or DROP, databases that already hold data, and must stop (not guess) when it
# cannot tell. Runs the real script against a fake mysql client in a temp tree;
# no docker or MySQL needed.
#
# Usage: scripts/bash/tests/test-db-import-conditional.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/db-import-conditional.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); echo "  ok   $1"; }
fail(){ FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# Fake mysql: logs every -e statement; behaviour selected by FAKE_MYSQL_MODE.
#   populated  table-count queries return 42
#   empty      table-count queries return 0
#   flaky      server answers SELECT 1, but table-count queries fail
mkdir -p "$WORK/bin"
cat > "$WORK/bin/mysql" <<'EOF'
#!/bin/bash
query=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) query="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$query" ] || { cat >/dev/null; exit 0; }
printf '%s\n' "$query" >> "$FAKE_MYSQL_LOG"
case "$query" in
  *information_schema.tables*)
    case "$FAKE_MYSQL_MODE" in
      populated) echo 42;;
      empty) echo 0;;
      flaky) echo "ERROR 2013 (HY000): Lost connection" >&2; exit 1;;
    esac;;
esac
exit 0
EOF
chmod +x "$WORK/bin/mysql"

# run_case <name> <mode> [marker...]
# Sets RC, OUT, and CASE_DIR (holding persist/ markers and mysql.log).
run_case(){
  local name="$1" mode="$2"; shift 2
  CASE_DIR="$WORK/$name"
  mkdir -p "$CASE_DIR/scripts/bash" "$CASE_DIR/persist" "$CASE_DIR/tmp"
  cp "$SRC" "$CASE_DIR/scripts/bash/db-import-conditional.sh"
  : > "$CASE_DIR/mysql.log"
  local marker
  for marker in "$@"; do
    echo "test marker" > "$CASE_DIR/persist/$marker"
  done
  OUT="$(cd "$CASE_DIR" && env PATH="$WORK/bin:$PATH" \
    FAKE_MYSQL_MODE="$mode" FAKE_MYSQL_LOG="$CASE_DIR/mysql.log" \
    RESTORE_STATUS_DIR="$CASE_DIR/persist" MARKER_STATUS_DIR="$CASE_DIR/tmp" \
    SEED_DBIMPORT_CONF_SCRIPT=/nonexistent \
    CONTAINER_MYSQL=fake-mysql MYSQL_ROOT_PASSWORD=pw MYSQL_USER=root \
    DB_AUTH_NAME=acore_auth DB_WORLD_NAME=acore_world \
    DB_CHARACTERS_NAME=acore_characters DB_PLAYERBOTS_NAME=acore_playerbots \
    timeout 60 bash "$CASE_DIR/scripts/bash/db-import-conditional.sh" 2>&1)"
  RC=$?
}

dropped(){ grep -q "DROP DATABASE" "$CASE_DIR/mysql.log"; }

echo "populated databases, no markers (fresh install being redeployed)"
run_case populated-nomarker populated
[ "$RC" -eq 0 ] && pass "exits 0" || fail "exits 0 (rc=$RC)"
dropped && fail "does not DROP databases" || pass "does not DROP databases"
case "$OUT" in *"Checking for backups to restore"*) fail "does not search for a backup to restore";;
  *) pass "does not search for a backup to restore";; esac

echo "populated databases, restore marker present"
run_case populated-marker populated .restore-completed
[ "$RC" -eq 0 ] && pass "exits 0" || fail "exits 0 (rc=$RC)"
dropped && fail "does not DROP databases" || pass "does not DROP databases"

echo "table check fails, restore marker present"
run_case flaky-marker flaky .restore-completed
[ "$RC" -ne 0 ] && pass "exits non-zero" || fail "exits non-zero"
dropped && fail "does not DROP databases" || pass "does not DROP databases"
[ -f "$CASE_DIR/persist/.restore-completed" ] && pass "keeps the restore marker" \
  || fail "keeps the restore marker"

echo "table check fails, no markers"
run_case flaky-nomarker flaky
[ "$RC" -ne 0 ] && pass "exits non-zero" || fail "exits non-zero"
dropped && fail "does not DROP databases" || pass "does not DROP databases"

echo "empty databases, no markers (fresh install)"
run_case empty-nomarker empty
dropped && pass "proceeds to create fresh databases" \
  || fail "proceeds to create fresh databases"

echo "empty databases, stale restore marker"
run_case empty-marker empty .restore-completed
[ ! -f "$CASE_DIR/persist/.restore-completed" ] && pass "clears the stale marker" \
  || fail "clears the stale marker"
dropped && pass "proceeds to create fresh databases" \
  || fail "proceeds to create fresh databases"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

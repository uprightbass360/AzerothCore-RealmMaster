#!/bin/bash
# Verify SQL Updates
# Checks that SQL updates have been applied via the updates table
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_ERROR="❌"
ICON_INFO="ℹ️"

# Default values
MODULE_NAME=""
DATABASE_NAME=""
SHOW_ALL=0
CHECK_HASH=0
CONTAINER_NAME="ac-mysql"

usage() {
  cat <<'EOF'
Usage: ./verify-sql-updates.sh [options]

Verify that SQL updates have been applied via AzerothCore's updates table.

Options:
  --module NAME             Check specific module
  --database NAME           Check specific database (auth/world/characters)
  --all                     Show all module updates
  --check-hash              Verify file hashes match database
  --container NAME          MySQL container name (default: ac-mysql)
  -h, --help                Show this help

Examples:
  ./verify-sql-updates.sh --all
  ./verify-sql-updates.sh --module mod-aoe-loot
  ./verify-sql-updates.sh --database acore_world --all

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) MODULE_NAME="$2"; shift 2;;
    --database) DATABASE_NAME="$2"; shift 2;;
    --all) SHOW_ALL=1; shift;;
    --check-hash) CHECK_HASH=1; shift;;
    --container) CONTAINER_NAME="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

MYSQL_HOST="${MYSQL_HOST:-ac-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
DB_AUTH_NAME="${DB_AUTH_NAME:-acore_auth}"
DB_WORLD_NAME="${DB_WORLD_NAME:-acore_world}"
DB_CHARACTERS_NAME="${DB_CHARACTERS_NAME:-acore_characters}"
DB_PLAYERBOTS_NAME="${DB_PLAYERBOTS_NAME:-acore_playerbots}"

# Logging functions
info() {
  echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

ok() {
  echo -e "${GREEN}${ICON_SUCCESS}${NC} $*"
}

warn() {
  echo -e "${YELLOW}${ICON_WARNING}${NC} $*"
}

err() {
  echo -e "${RED}${ICON_ERROR}${NC} $*"
}

# MySQL query helper
mysql_query() {
  local database="${1:-}"
  local query="$2"

  if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    err "MYSQL_ROOT_PASSWORD not set"
    return 1
  fi

  if command -v docker >/dev/null 2>&1; then
    if [ -n "$database" ]; then
      docker exec "$CONTAINER_NAME" mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" "$database" -N -B -e "$query" 2>/dev/null
    else
      docker exec "$CONTAINER_NAME" mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -N -B -e "$query" 2>/dev/null
    fi
  else
    if [ -n "$database" ]; then
      mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" "$database" -N -B -e "$query" 2>/dev/null
    else
      mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -N -B -e "$query" 2>/dev/null
    fi
  fi
}

# Check if database exists
db_exists() {
  local db_name="$1"
  local count
  count=$(mysql_query "" "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db_name'" 2>/dev/null || echo "0")
  [ "$count" = "1" ]
}

# Verify module SQL in database
verify_module_sql() {
  local module_name="$1"
  local database_name="$2"

  if ! db_exists "$database_name"; then
    err "Database does not exist: $database_name"
    return 1
  fi

  info "Checking module updates in $database_name"

  # Query updates table for module
  local query="SELECT name, hash, state, timestamp, speed FROM updates WHERE name LIKE '%${module_name}%' AND state='MODULE' ORDER BY timestamp DESC"
  local results
  results=$(mysql_query "$database_name" "$query" 2>/dev/null || echo "")

  if [ -z "$results" ]; then
    warn "No updates found for module: $module_name in $database_name"
    return 0
  fi

  # Display results
  echo
  printf "${BOLD}${CYAN}Module Updates for %s in %s:${NC}\n" "$module_name" "$database_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  while IFS=$'\t' read -r name hash state timestamp speed; do
    printf "${GREEN}${ICON_SUCCESS}${NC} %s\n" "$name"
    printf "   Hash: %s\n" "${hash:0:12}..."
    printf "   Applied: %s\n" "$timestamp"
    printf "   Speed: %sms\n" "$speed"
    echo
  done <<< "$results"

  return 0
}

# List all module updates
list_module_updates() {
  local database_name="$1"

  if ! db_exists "$database_name"; then
    err "Database does not exist: $database_name"
    return 1
  fi

  info "Listing all module updates in $database_name"

  # Query all module updates
  local query="SELECT name, state, timestamp FROM updates WHERE state='MODULE' ORDER BY timestamp DESC"
  local results
  results=$(mysql_query "$database_name" "$query" 2>/dev/null || echo "")

  if [ -z "$results" ]; then
    warn "No module updates found in $database_name"
    return 0
  fi

  # Display results
  echo
  printf "${BOLD}${CYAN}All Module Updates in %s:${NC}\n" "$database_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local count=0
  while IFS=$'\t' read -r name state timestamp; do
    printf "${GREEN}${ICON_SUCCESS}${NC} %s\n" "$name"
    printf "   Applied: %s\n" "$timestamp"
    ((count++))
  done <<< "$results"

  echo
  ok "Total module updates: $count"
  echo

  return 0
}

# Check update applied
check_update_applied() {
  local filename="$1"
  local database_name="$2"
  local expected_hash="${3:-}"

  if ! db_exists "$database_name"; then
    err "Database does not exist: $database_name"
    return 2
  fi

  # Query for specific file
  local query="SELECT hash, state, timestamp FROM updates WHERE name='$filename' LIMIT 1"
  local result
  result=$(mysql_query "$database_name" "$query" 2>/dev/null || echo "")

  if [ -z "$result" ]; then
    warn "Update not found: $filename"
    return 1
  fi

  # Parse result
  IFS=$'\t' read -r hash state timestamp <<< "$result"

  ok "Update applied: $filename"
  printf "   Hash: %s\n" "$hash"
  printf "   State: %s\n" "$state"
  printf "   Applied: %s\n" "$timestamp"

  # Check hash if provided
  if [ -n "$expected_hash" ] && [ "$expected_hash" != "$hash" ]; then
    err "Hash mismatch!"
    printf "   Expected: %s\n" "$expected_hash"
    printf "   Actual:   %s\n" "$hash"
    return 2
  fi

  return 0
}

# Generate verification report
generate_verification_report() {
  echo
  printf "${BOLD}${BLUE}🔍 Module SQL Verification Report${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  local total_updates=0
  local databases=("$DB_AUTH_NAME" "$DB_WORLD_NAME" "$DB_CHARACTERS_NAME")

  # Add playerbots if it exists
  if db_exists "$DB_PLAYERBOTS_NAME"; then
    databases+=("$DB_PLAYERBOTS_NAME")
  fi

  for db in "${databases[@]}"; do
    if ! db_exists "$db"; then
      continue
    fi

    # Get count of module updates
    local count
    count=$(mysql_query "$db" "SELECT COUNT(*) FROM updates WHERE state='MODULE'" 2>/dev/null || echo "0")

    if [ "$count" != "0" ]; then
      printf "${GREEN}${ICON_SUCCESS}${NC} ${BOLD}%s:${NC} %s module update(s)\n" "$db" "$count"
      total_updates=$((total_updates + count))

      if [ "$SHOW_ALL" = "1" ]; then
        # Show recent updates
        local query="SELECT name, timestamp FROM updates WHERE state='MODULE' ORDER BY timestamp DESC LIMIT 5"
        local results
        results=$(mysql_query "$db" "$query" 2>/dev/null || echo "")

        if [ -n "$results" ]; then
          while IFS=$'\t' read -r name timestamp; do
            printf "   - %s (%s)\n" "$name" "$timestamp"
          done <<< "$results"
          echo
        fi
      fi
    else
      printf "${YELLOW}${ICON_WARNING}${NC} ${BOLD}%s:${NC} No module updates\n" "$db"
    fi
  done

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "${BOLD}Total: %s module update(s) applied${NC}\n" "$total_updates"
  echo
}

# Main execution
main() {
  echo
  info "SQL Update Verification"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # Test MySQL connection
  if ! mysql_query "" "SELECT 1" >/dev/null 2>&1; then
    err "Cannot connect to MySQL server"
    printf "  Host: %s:%s\n" "$MYSQL_HOST" "$MYSQL_PORT"
    printf "  User: %s\n" "$MYSQL_USER"
    printf "  Container: %s\n\n" "$CONTAINER_NAME"
    exit 1
  fi

  # Execute based on options
  if [ -n "$MODULE_NAME" ]; then
    # Check specific module
    if [ -n "$DATABASE_NAME" ]; then
      verify_module_sql "$MODULE_NAME" "$DATABASE_NAME"
    else
      # Check all databases for this module
      for db in "$DB_AUTH_NAME" "$DB_WORLD_NAME" "$DB_CHARACTERS_NAME"; do
        if db_exists "$db"; then
          verify_module_sql "$MODULE_NAME" "$db"
        fi
      done
      if db_exists "$DB_PLAYERBOTS_NAME"; then
        verify_module_sql "$MODULE_NAME" "$DB_PLAYERBOTS_NAME"
      fi
    fi
  elif [ -n "$DATABASE_NAME" ]; then
    # List all updates in specific database
    list_module_updates "$DATABASE_NAME"
  else
    # Generate full report
    generate_verification_report
  fi

  echo
  ok "Verification complete"
  echo
}

main "$@"

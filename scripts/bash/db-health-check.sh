#!/bin/bash
# Database Health Check Script
# Provides comprehensive health status of AzerothCore databases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_ERROR="❌"
ICON_INFO="ℹ️"
ICON_DB="🗄️"
ICON_SIZE="💾"
ICON_TIME="🕐"
ICON_MODULE="📦"
ICON_UPDATE="🔄"

# Default values
VERBOSE=0
SHOW_PENDING=0
SHOW_MODULES=1
CONTAINER_NAME="ac-mysql"

usage() {
  cat <<'EOF'
Usage: ./db-health-check.sh [options]

Check the health status of AzerothCore databases.

Options:
  -v, --verbose         Show detailed information
  -p, --pending         Show pending updates
  -m, --no-modules      Hide module update information
  -c, --container NAME  MySQL container name (default: ac-mysql)
  -h, --help            Show this help

Examples:
  ./db-health-check.sh
  ./db-health-check.sh --verbose --pending
  ./db-health-check.sh --container ac-mysql-custom

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift;;
    -p|--pending) SHOW_PENDING=1; shift;;
    -m|--no-modules) SHOW_MODULES=0; shift;;
    -c|--container) CONTAINER_NAME="$2"; shift 2;;
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

# MySQL query helper
mysql_query() {
  local database="${1:-}"
  local query="$2"

  if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "Error: MYSQL_ROOT_PASSWORD not set" >&2
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

# Format bytes to human readable
format_bytes() {
  local bytes=$1
  if [ "$bytes" -lt 1024 ]; then
    echo "${bytes}B"
  elif [ "$bytes" -lt 1048576 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")KB"
  elif [ "$bytes" -lt 1073741824 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
  else
    echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
  fi
}

# Check if database exists
db_exists() {
  local db_name="$1"
  local count
  count=$(mysql_query "" "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db_name'" 2>/dev/null || echo "0")
  [ "$count" = "1" ]
}

# Get database size
get_db_size() {
  local db_name="$1"
  mysql_query "" "SELECT IFNULL(SUM(data_length + index_length), 0) FROM information_schema.TABLES WHERE table_schema='$db_name'" 2>/dev/null || echo "0"
}

# Get update count
get_update_count() {
  local db_name="$1"
  local state="${2:-}"

  if [ -n "$state" ]; then
    mysql_query "$db_name" "SELECT COUNT(*) FROM updates WHERE state='$state'" 2>/dev/null || echo "0"
  else
    mysql_query "$db_name" "SELECT COUNT(*) FROM updates" 2>/dev/null || echo "0"
  fi
}

# Get last update timestamp
get_last_update() {
  local db_name="$1"
  mysql_query "$db_name" "SELECT IFNULL(MAX(timestamp), 'Never') FROM updates" 2>/dev/null || echo "Never"
}

# Get table count
get_table_count() {
  local db_name="$1"
  mysql_query "" "SELECT COUNT(*) FROM information_schema.TABLES WHERE table_schema='$db_name'" 2>/dev/null || echo "0"
}

# Get character count
get_character_count() {
  mysql_query "$DB_CHARACTERS_NAME" "SELECT COUNT(*) FROM characters" 2>/dev/null || echo "0"
}

# Get active players (logged in last 24 hours)
get_active_players() {
  mysql_query "$DB_CHARACTERS_NAME" "SELECT COUNT(*) FROM characters WHERE logout_time > UNIX_TIMESTAMP(NOW() - INTERVAL 1 DAY)" 2>/dev/null || echo "0"
}

# Get account count
get_account_count() {
  mysql_query "$DB_AUTH_NAME" "SELECT COUNT(*) FROM account" 2>/dev/null || echo "0"
}

# Get pending updates
get_pending_updates() {
  local db_name="$1"
  mysql_query "$db_name" "SELECT name FROM updates WHERE state='PENDING' ORDER BY name" 2>/dev/null || true
}

# Check database health
check_database() {
  local db_name="$1"
  local display_name="$2"

  if ! db_exists "$db_name"; then
    printf "  ${RED}${ICON_ERROR} %s (%s)${NC}\n" "$display_name" "$db_name"
    printf "     ${RED}Database does not exist${NC}\n"
    return 1
  fi

  printf "  ${GREEN}${ICON_SUCCESS} %s (%s)${NC}\n" "$display_name" "$db_name"

  local update_count module_count last_update db_size table_count
  update_count=$(get_update_count "$db_name" "RELEASED")
  module_count=$(get_update_count "$db_name" "MODULE")
  last_update=$(get_last_update "$db_name")
  db_size=$(get_db_size "$db_name")
  table_count=$(get_table_count "$db_name")

  printf "     ${ICON_UPDATE} Updates: %s applied" "$update_count"
  if [ "$module_count" != "0" ] && [ "$SHOW_MODULES" = "1" ]; then
    printf " (%s module)" "$module_count"
  fi
  printf "\n"

  printf "     ${ICON_TIME} Last update: %s\n" "$last_update"
  printf "     ${ICON_SIZE} Size: %s (%s tables)\n" "$(format_bytes "$db_size")" "$table_count"

  if [ "$VERBOSE" = "1" ]; then
    local custom_count archived_count
    custom_count=$(get_update_count "$db_name" "CUSTOM")
    archived_count=$(get_update_count "$db_name" "ARCHIVED")

    if [ "$custom_count" != "0" ]; then
      printf "     ${ICON_INFO} Custom updates: %s\n" "$custom_count"
    fi
    if [ "$archived_count" != "0" ]; then
      printf "     ${ICON_INFO} Archived updates: %s\n" "$archived_count"
    fi
  fi

  # Show pending updates if requested
  if [ "$SHOW_PENDING" = "1" ]; then
    local pending_updates
    pending_updates=$(get_pending_updates "$db_name")
    if [ -n "$pending_updates" ]; then
      printf "     ${YELLOW}${ICON_WARNING} Pending updates:${NC}\n"
      while IFS= read -r update; do
        printf "        - %s\n" "$update"
      done <<< "$pending_updates"
    fi
  fi

  echo
}

# Show module updates summary
show_module_updates() {
  if [ "$SHOW_MODULES" = "0" ]; then
    return
  fi

  printf "${BOLD}${ICON_MODULE} Module Updates${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Get module updates from world database (most modules update world DB)
  local module_updates
  module_updates=$(mysql_query "$DB_WORLD_NAME" "SELECT SUBSTRING_INDEX(name, '_', 1) as module, COUNT(*) as count FROM updates WHERE state='MODULE' GROUP BY module ORDER BY module" 2>/dev/null || echo "")

  if [ -z "$module_updates" ]; then
    printf "  ${ICON_INFO} No module updates detected\n\n"
    return
  fi

  while IFS=$'\t' read -r module count; do
    printf "  ${GREEN}${ICON_SUCCESS}${NC} %s: %s update(s)\n" "$module" "$count"
  done <<< "$module_updates"
  echo
}

# Get backup information
get_backup_info() {
  local backup_dir="$PROJECT_ROOT/storage/backups"

  if [ ! -d "$backup_dir" ]; then
    printf "  ${ICON_INFO} No backups directory found\n"
    return
  fi

  # Check for latest backup
  local latest_hourly latest_daily
  if [ -d "$backup_dir/hourly" ]; then
    latest_hourly=$(ls -1t "$backup_dir/hourly" 2>/dev/null | head -n1 || echo "")
  fi
  if [ -d "$backup_dir/daily" ]; then
    latest_daily=$(ls -1t "$backup_dir/daily" 2>/dev/null | head -n1 || echo "")
  fi

  if [ -n "$latest_hourly" ]; then
    # Calculate time ago
    local backup_timestamp="${latest_hourly:0:8}_${latest_hourly:9:6}"
    local backup_epoch
    backup_epoch=$(date -d "${backup_timestamp:0:4}-${backup_timestamp:4:2}-${backup_timestamp:6:2} ${backup_timestamp:9:2}:${backup_timestamp:11:2}:${backup_timestamp:13:2}" +%s 2>/dev/null || echo "0")
    local now_epoch
    now_epoch=$(date +%s)
    local diff=$((now_epoch - backup_epoch))
    local hours=$((diff / 3600))
    local minutes=$(((diff % 3600) / 60))

    if [ "$hours" -gt 0 ]; then
      printf "  ${ICON_TIME} Last hourly backup: %s hours ago\n" "$hours"
    else
      printf "  ${ICON_TIME} Last hourly backup: %s minutes ago\n" "$minutes"
    fi
  fi

  if [ -n "$latest_daily" ] && [ "$latest_daily" != "$latest_hourly" ]; then
    local backup_timestamp="${latest_daily:0:8}_${latest_daily:9:6}"
    local backup_epoch
    backup_epoch=$(date -d "${backup_timestamp:0:4}-${backup_timestamp:4:2}-${backup_timestamp:6:2} ${backup_timestamp:9:2}:${backup_timestamp:11:2}:${backup_timestamp:13:2}" +%s 2>/dev/null || echo "0")
    local now_epoch
    now_epoch=$(date +%s)
    local diff=$((now_epoch - backup_epoch))
    local days=$((diff / 86400))

    printf "  ${ICON_TIME} Last daily backup: %s days ago\n" "$days"
  fi
}

# Main health check
main() {
  echo
  printf "${BOLD}${BLUE}${ICON_DB} AZEROTHCORE DATABASE HEALTH CHECK${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # Test MySQL connection
  if ! mysql_query "" "SELECT 1" >/dev/null 2>&1; then
    printf "${RED}${ICON_ERROR} Cannot connect to MySQL server${NC}\n"
    printf "  Host: %s:%s\n" "$MYSQL_HOST" "$MYSQL_PORT"
    printf "  User: %s\n" "$MYSQL_USER"
    printf "  Container: %s\n\n" "$CONTAINER_NAME"
    exit 1
  fi

  printf "${BOLD}${ICON_DB} Database Status${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # Check each database
  check_database "$DB_AUTH_NAME" "Auth DB"
  check_database "$DB_WORLD_NAME" "World DB"
  check_database "$DB_CHARACTERS_NAME" "Characters DB"

  # Optional: Check playerbots database
  if db_exists "$DB_PLAYERBOTS_NAME"; then
    check_database "$DB_PLAYERBOTS_NAME" "Playerbots DB"
  fi

  # Show character/account statistics
  printf "${BOLD}${CYAN}📊 Server Statistics${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local account_count character_count active_count
  account_count=$(get_account_count)
  character_count=$(get_character_count)
  active_count=$(get_active_players)

  printf "  ${ICON_INFO} Accounts: %s\n" "$account_count"
  printf "  ${ICON_INFO} Characters: %s\n" "$character_count"
  printf "  ${ICON_INFO} Active (24h): %s\n" "$active_count"
  echo

  # Show module updates
  show_module_updates

  # Show backup information
  printf "${BOLD}${ICON_SIZE} Backup Information${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  get_backup_info
  echo

  # Calculate total database size
  local total_size=0
  for db in "$DB_AUTH_NAME" "$DB_WORLD_NAME" "$DB_CHARACTERS_NAME"; do
    if db_exists "$db"; then
      local size
      size=$(get_db_size "$db")
      total_size=$((total_size + size))
    fi
  done

  if db_exists "$DB_PLAYERBOTS_NAME"; then
    local size
    size=$(get_db_size "$DB_PLAYERBOTS_NAME")
    total_size=$((total_size + size))
  fi

  printf "${BOLD}💾 Total Database Storage: %s${NC}\n" "$(format_bytes "$total_size")"
  echo

  printf "${GREEN}${ICON_SUCCESS} Health check complete!${NC}\n"
  echo
}

main "$@"

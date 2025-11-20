#!/bin/bash
# Backup Status Dashboard
# Displays comprehensive backup system status and statistics
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
ICON_BACKUP="📦"
ICON_TIME="🕐"
ICON_SIZE="💾"
ICON_CHART="📊"
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_SCHEDULE="📅"

# Default values
SHOW_DETAILS=0
SHOW_TRENDS=0

usage() {
  cat <<'EOF'
Usage: ./backup-status.sh [options]

Display backup system status and statistics.

Options:
  -d, --details     Show detailed backup listing
  -t, --trends      Show size trends over time
  -h, --help        Show this help

Examples:
  ./backup-status.sh
  ./backup-status.sh --details
  ./backup-status.sh --details --trends

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--details) SHOW_DETAILS=1; shift;;
    -t|--trends) SHOW_TRENDS=1; shift;;
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

BACKUP_PATH="${BACKUP_PATH:-$PROJECT_ROOT/storage/backups}"
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES:-60}"
BACKUP_RETENTION_HOURS="${BACKUP_RETENTION_HOURS:-6}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-3}"
BACKUP_DAILY_TIME="${BACKUP_DAILY_TIME:-09}"

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

# Get directory size
get_dir_size() {
  local dir="$1"
  if [ -d "$dir" ]; then
    du -sb "$dir" 2>/dev/null | cut -f1
  else
    echo "0"
  fi
}

# Count backups in directory
count_backups() {
  local dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
  else
    echo "0"
  fi
}

# Get latest backup timestamp
get_latest_backup() {
  local dir="$1"
  if [ -d "$dir" ]; then
    ls -1t "$dir" 2>/dev/null | head -n1 || echo ""
  else
    echo ""
  fi
}

# Parse timestamp from backup directory name
parse_timestamp() {
  local backup_name="$1"
  # Format: YYYYMMDD_HHMMSS or ExportBackup_YYYYMMDD_HHMMSS
  local timestamp
  if [[ "$backup_name" =~ ([0-9]{8})_([0-9]{6}) ]]; then
    timestamp="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"
    echo "$timestamp"
  else
    echo ""
  fi
}

# Calculate time ago from timestamp
time_ago() {
  local timestamp="$1"
  if [ -z "$timestamp" ]; then
    echo "Unknown"
    return
  fi

  # Parse timestamp: YYYYMMDD_HHMMSS
  local year="${timestamp:0:4}"
  local month="${timestamp:4:2}"
  local day="${timestamp:6:2}"
  local hour="${timestamp:9:2}"
  local minute="${timestamp:11:2}"
  local second="${timestamp:13:2}"

  local backup_epoch
  backup_epoch=$(date -d "$year-$month-$day $hour:$minute:$second" +%s 2>/dev/null || echo "0")

  if [ "$backup_epoch" = "0" ]; then
    echo "Unknown"
    return
  fi

  local now_epoch
  now_epoch=$(date +%s)
  local diff=$((now_epoch - backup_epoch))

  if [ "$diff" -lt 60 ]; then
    echo "${diff} seconds ago"
  elif [ "$diff" -lt 3600 ]; then
    local minutes=$((diff / 60))
    echo "${minutes} minute(s) ago"
  elif [ "$diff" -lt 86400 ]; then
    local hours=$((diff / 3600))
    echo "${hours} hour(s) ago"
  else
    local days=$((diff / 86400))
    echo "${days} day(s) ago"
  fi
}

# Calculate next scheduled backup
next_backup_time() {
  local interval_minutes="$1"
  local now_epoch
  now_epoch=$(date +%s)

  local next_epoch=$((now_epoch + (interval_minutes * 60)))
  local in_minutes=$(((next_epoch - now_epoch) / 60))

  if [ "$in_minutes" -lt 60 ]; then
    echo "in ${in_minutes} minute(s)"
  else
    local in_hours=$((in_minutes / 60))
    local remaining_minutes=$((in_minutes % 60))
    echo "in ${in_hours} hour(s) ${remaining_minutes} minute(s)"
  fi
}

# Calculate next daily backup
next_daily_backup() {
  local daily_hour="$1"
  local now_epoch
  now_epoch=$(date +%s)

  local today_backup_epoch
  today_backup_epoch=$(date -d "today ${daily_hour}:00:00" +%s)

  local next_epoch
  if [ "$now_epoch" -lt "$today_backup_epoch" ]; then
    next_epoch=$today_backup_epoch
  else
    next_epoch=$(date -d "tomorrow ${daily_hour}:00:00" +%s)
  fi

  local diff=$((next_epoch - now_epoch))
  local hours=$((diff / 3600))
  local minutes=$(((diff % 3600) / 60))

  echo "in ${hours} hour(s) ${minutes} minute(s)"
}

# Show backup tier status
show_backup_tier() {
  local tier_name="$1"
  local tier_dir="$2"
  local retention="$3"

  if [ ! -d "$tier_dir" ]; then
    printf "  ${ICON_WARNING} ${YELLOW}%s:${NC} No backups found\n" "$tier_name"
    return
  fi

  local count size latest
  count=$(count_backups "$tier_dir")
  size=$(get_dir_size "$tier_dir")
  latest=$(get_latest_backup "$tier_dir")

  if [ "$count" = "0" ]; then
    printf "  ${ICON_WARNING} ${YELLOW}%s:${NC} No backups found\n" "$tier_name"
    return
  fi

  local latest_timestamp
  latest_timestamp=$(parse_timestamp "$latest")
  local ago
  ago=$(time_ago "$latest_timestamp")

  printf "  ${GREEN}${ICON_SUCCESS} %s:${NC} %s backup(s), %s total\n" "$tier_name" "$count" "$(format_bytes "$size")"
  printf "     ${ICON_TIME} Latest: %s (%s)\n" "$latest" "$ago"
  printf "     ${ICON_SCHEDULE} Retention: %s\n" "$retention"

  if [ "$SHOW_DETAILS" = "1" ]; then
    printf "     ${ICON_BACKUP} Available backups:\n"
    local backup_list
    backup_list=$(ls -1t "$tier_dir" 2>/dev/null || true)
    while IFS= read -r backup; do
      if [ -n "$backup" ]; then
        local backup_size
        backup_size=$(get_dir_size "$tier_dir/$backup")
        local backup_timestamp
        backup_timestamp=$(parse_timestamp "$backup")
        local backup_ago
        backup_ago=$(time_ago "$backup_timestamp")
        printf "        - %s: %s (%s)\n" "$backup" "$(format_bytes "$backup_size")" "$backup_ago"
      fi
    done <<< "$backup_list"
  fi
}

# Show size trends
show_trends() {
  printf "${BOLD}${ICON_CHART} Backup Size Trends${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local daily_dir="$BACKUP_PATH/daily"
  if [ ! -d "$daily_dir" ]; then
    printf "  ${ICON_WARNING} No daily backups found for trend analysis\n\n"
    return
  fi

  # Get last 7 daily backups
  local backup_list
  backup_list=$(ls -1t "$daily_dir" 2>/dev/null | head -7 | tac)

  if [ -z "$backup_list" ]; then
    printf "  ${ICON_WARNING} Not enough backups for trend analysis\n\n"
    return
  fi

  # Find max size for scaling
  local max_size=0
  while IFS= read -r backup; do
    if [ -n "$backup" ]; then
      local size
      size=$(get_dir_size "$daily_dir/$backup")
      if [ "$size" -gt "$max_size" ]; then
        max_size=$size
      fi
    fi
  done <<< "$backup_list"

  # Display trend chart
  while IFS= read -r backup; do
    if [ -n "$backup" ]; then
      local size
      size=$(get_dir_size "$daily_dir/$backup")
      local timestamp
      timestamp=$(parse_timestamp "$backup")
      local date_str="${timestamp:0:4}-${timestamp:4:2}-${timestamp:6:2}"

      # Calculate bar length (max 30 chars)
      local bar_length=0
      if [ "$max_size" -gt 0 ]; then
        bar_length=$((size * 30 / max_size))
      fi

      # Create bar
      local bar=""
      for ((i=0; i<bar_length; i++)); do
        bar+="█"
      done
      for ((i=bar_length; i<30; i++)); do
        bar+="░"
      done

      printf "  %s: %s %s\n" "$date_str" "$(format_bytes "$size" | awk '{printf "%-8s", $0}')" "$bar"
    fi
  done <<< "$backup_list"
  echo
}

# Main status display
main() {
  echo
  printf "${BOLD}${BLUE}${ICON_BACKUP} AZEROTHCORE BACKUP STATUS${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # Check if backup directory exists
  if [ ! -d "$BACKUP_PATH" ]; then
    printf "${RED}${ICON_WARNING} Backup directory not found: %s${NC}\n\n" "$BACKUP_PATH"
    printf "Backup system may not be initialized yet.\n\n"
    exit 1
  fi

  # Show current backup tiers
  printf "${BOLD}${ICON_BACKUP} Backup Tiers${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  show_backup_tier "Hourly Backups" "$BACKUP_PATH/hourly" "${BACKUP_RETENTION_HOURS} hours"
  show_backup_tier "Daily Backups" "$BACKUP_PATH/daily" "${BACKUP_RETENTION_DAYS} days"

  # Check for manual backups
  local manual_count=0
  local manual_size=0
  if [ -d "$PROJECT_ROOT/manual-backups" ]; then
    manual_count=$(count_backups "$PROJECT_ROOT/manual-backups")
    manual_size=$(get_dir_size "$PROJECT_ROOT/manual-backups")
  fi

  # Also check for export backups in main backup dir
  local export_count=0
  if [ -d "$BACKUP_PATH" ]; then
    export_count=$(find "$BACKUP_PATH" -maxdepth 1 -type d -name "ExportBackup_*" 2>/dev/null | wc -l)
    if [ "$export_count" -gt 0 ]; then
      local export_size=0
      while IFS= read -r export_dir; do
        if [ -n "$export_dir" ]; then
          local size
          size=$(get_dir_size "$export_dir")
          export_size=$((export_size + size))
        fi
      done < <(find "$BACKUP_PATH" -maxdepth 1 -type d -name "ExportBackup_*" 2>/dev/null)
      manual_size=$((manual_size + export_size))
      manual_count=$((manual_count + export_count))
    fi
  fi

  if [ "$manual_count" -gt 0 ]; then
    printf "  ${GREEN}${ICON_SUCCESS} Manual/Export Backups:${NC} %s backup(s), %s total\n" "$manual_count" "$(format_bytes "$manual_size")"
  fi

  echo

  # Show next scheduled backups
  printf "${BOLD}${ICON_SCHEDULE} Backup Schedule${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "  ${ICON_TIME} Hourly interval: every %s minutes\n" "$BACKUP_INTERVAL_MINUTES"
  printf "  ${ICON_TIME} Next hourly backup: %s\n" "$(next_backup_time "$BACKUP_INTERVAL_MINUTES")"
  printf "  ${ICON_TIME} Daily backup time: %s:00\n" "$BACKUP_DAILY_TIME"
  printf "  ${ICON_TIME} Next daily backup: %s\n" "$(next_daily_backup "$BACKUP_DAILY_TIME")"
  echo

  # Calculate total storage
  local total_size=0
  for tier_dir in "$BACKUP_PATH/hourly" "$BACKUP_PATH/daily"; do
    if [ -d "$tier_dir" ]; then
      local size
      size=$(get_dir_size "$tier_dir")
      total_size=$((total_size + size))
    fi
  done
  total_size=$((total_size + manual_size))

  printf "${BOLD}${ICON_SIZE} Total Backup Storage: %s${NC}\n" "$(format_bytes "$total_size")"
  echo

  # Show trends if requested
  if [ "$SHOW_TRENDS" = "1" ]; then
    show_trends
  fi

  # Show backup configuration
  if [ "$SHOW_DETAILS" = "1" ]; then
    printf "${BOLD}⚙️  Backup Configuration${NC}\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  Backup directory: %s\n" "$BACKUP_PATH"
    printf "  Hourly retention: %s hours\n" "$BACKUP_RETENTION_HOURS"
    printf "  Daily retention: %s days\n" "$BACKUP_RETENTION_DAYS"
    printf "  Interval: every %s minutes\n" "$BACKUP_INTERVAL_MINUTES"
    printf "  Daily backup time: %s:00\n" "$BACKUP_DAILY_TIME"
    echo
  fi

  printf "${GREEN}${ICON_SUCCESS} Backup status check complete!${NC}\n"
  echo
}

main "$@"

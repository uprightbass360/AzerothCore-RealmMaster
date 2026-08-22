#!/bin/bash
# azerothcore-rm
set -e

BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-/backups}"
HOURLY_DIR="$BACKUP_DIR_BASE/hourly"
DAILY_DIR="$BACKUP_DIR_BASE/daily"
MONTHLY_DIR="$BACKUP_DIR_BASE/monthly"
RETENTION_HOURS=${BACKUP_RETENTION_HOURS:-6}
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}
RETENTION_MONTHS=${BACKUP_RETENTION_MONTHS:-12}
# Force base-10 (a bare printf %02d rejects "09" as invalid octal)
DAILY_TIME=$(printf '%02d' "$((10#${BACKUP_DAILY_TIME:-09}))" 2>/dev/null || echo "09")
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL_MINUTES:-60}
MYSQL_PORT=${MYSQL_PORT:-3306}
# Optional webhook (e.g. ntfy/Discord/Slack) notified on backup failures
BACKUP_ALERT_WEBHOOK="${BACKUP_ALERT_WEBHOOK:-}"
# Keep the password out of process command lines
export MYSQL_PWD="${MYSQL_PASSWORD}"

mkdir -p "$HOURLY_DIR" "$DAILY_DIR" "$MONTHLY_DIR"

log() { echo "[$(date '+%F %T')] $*"; }

alert() {
  log "🚨 $*"
  if [ -n "$BACKUP_ALERT_WEBHOOK" ] && command -v curl >/dev/null 2>&1; then
    curl -fsS -m 10 -d "azerothcore backup: $*" "$BACKUP_ALERT_WEBHOOK" >/dev/null 2>&1 || \
      log "⚠️  Failed to deliver alert webhook"
  fi
}

db_exists() {
  local name="$1"
  [ -z "$name" ] && return 1
  local sanitized="${name//\`/}"
  if mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -e "USE \`${sanitized}\`;" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# A dump is only trustworthy if the gzip stream is intact and mysqldump
# reached its completion trailer (a truncated dump has neither).
verify_dump() {
  local file="$1"
  gunzip -t "$file" 2>/dev/null || return 1
  zcat "$file" 2>/dev/null | tail -1 | grep -q "Dump completed" || return 1
  return 0
}

# Build database list from env (include optional acore_playerbots if present)
database_list() {
  local dbs=("${DB_AUTH_NAME}" "${DB_WORLD_NAME}" "${DB_CHARACTERS_NAME}")
  declare -A seen=()
  for base in "${dbs[@]}"; do
    [ -n "$base" ] && seen["$base"]=1
  done

  if db_exists "acore_playerbots" && [ -z "${seen[acore_playerbots]}" ]; then
    dbs+=("acore_playerbots")
    seen["acore_playerbots"]=1
    log "Detected optional database: acore_playerbots (will be backed up)" >&2
  fi

  if [ -n "${BACKUP_EXTRA_DATABASES:-}" ]; then
    local normalized="${BACKUP_EXTRA_DATABASES//,/ }"
    for extra in $normalized; do
      [ -z "$extra" ] && continue
      if [ -n "${seen[$extra]}" ]; then
        continue
      fi
      if db_exists "$extra"; then
        dbs+=("$extra")
        seen["$extra"]=1
        log "Configured extra database '${extra}' added to backup rotation" >&2
      else
        log "⚠️  Configured extra database '${extra}' not found (skipping)" >&2
      fi
    done
  fi

  printf '%s\n' "${dbs[@]}"
}

if [ "${BACKUP_SCHEDULER_LIST_ONLY:-0}" = "1" ]; then
  mapfile -t _dbs < <(database_list)
  printf '%s\n' "${_dbs[@]}"
  exit 0
fi

run_backup() {
  local tier_dir="$1"    # hourly or daily dir
  local tier_type="$2"   # "hourly" or "daily"
  local ts=$(date '+%Y%m%d_%H%M%S')
  local target_dir="$tier_dir/$ts"
  mkdir -p "$target_dir"
  log "Starting ${tier_type} backup to $target_dir"

  local -a dbs
  local -a failed_dbs=()
  mapfile -t dbs < <(database_list)
  local backup_start_time=$(date +%s)
  local total_uncompressed_size=0
  local total_compressed_size=0

  for db in "${dbs[@]}"; do
    local db_start_time=$(date +%s)
    log "Backing up database: $db"

    # Get database size before backup
    local db_size_mb=$(mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" \
      -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb FROM information_schema.tables WHERE table_schema = '$db';" \
      -s -N 2>/dev/null || echo "0")

    if mysqldump \
      -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" \
      --single-transaction --routines --triggers --events \
      --hex-blob --quick --lock-tables=false \
      --add-drop-database --databases "$db" \
      | gzip -c > "$target_dir/${db}.sql.gz" \
      && verify_dump "$target_dir/${db}.sql.gz"; then

      local db_end_time=$(date +%s)
      local db_duration=$((db_end_time - db_start_time))
      # Get compressed file size using ls (more portable than stat)
      local compressed_size=$(ls -l "$target_dir/${db}.sql.gz" 2>/dev/null | awk '{print $5}' || echo "0")
      local compressed_size_mb=$((compressed_size / 1024 / 1024))

      # Use awk for floating point arithmetic (more portable than bc)
      total_uncompressed_size=$(awk "BEGIN {printf \"%.2f\", $total_uncompressed_size + $db_size_mb}")
      total_compressed_size=$(awk "BEGIN {printf \"%.2f\", $total_compressed_size + $compressed_size_mb}")

      log "✅ Successfully backed up $db (${db_size_mb}MB → ${compressed_size_mb}MB, ${db_duration}s)"

      # Warn about slow backups
      if [[ $db_duration -gt 300 ]]; then
        log "⚠️  Slow backup detected for $db: ${db_duration}s (>5min)"
      fi
    else
      log "❌ Failed to back up $db (dump error or verification failure)"
      failed_dbs+=("$db")
      rm -f "$target_dir/${db}.sql.gz" 2>/dev/null || true
    fi
  done

  # Calculate overall backup statistics
  local backup_end_time=$(date +%s)
  local total_duration=$((backup_end_time - backup_start_time))
  # Use awk with -v variables: literal 'x / 0' is rejected by gawk at parse
  # time even in an untaken branch, which used to corrupt the manifest for
  # zero-duration backups.
  local compression_ratio=$(awk -v u="$total_uncompressed_size" -v c="$total_compressed_size" 'BEGIN {printf "%.1f", (u > 0) ? (u - c) * 100 / u : 0}')
  local backup_rate=$(awk -v u="$total_uncompressed_size" -v d="$total_duration" 'BEGIN {printf "%.2f", (d > 0) ? u / d : 0}')

  # Create backup manifest (parity with scripts/backup.sh and backup-hourly.sh)
  local size; size=$(du -sh "$target_dir" | cut -f1)
  local mysql_ver; mysql_ver=$(mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -e 'SELECT VERSION();' -s -N 2>/dev/null || echo "unknown")

  local retention_field="\"retention_days\": ${RETENTION_DAYS}"
  case "$tier_type" in
    hourly|interval) retention_field="\"retention_hours\": ${RETENTION_HOURS}" ;;
    monthly)         retention_field="\"retention_months\": ${RETENTION_MONTHS}" ;;
  esac
  cat > "$target_dir/manifest.json" <<EOF
{
  "timestamp": "${ts}",
  "type": "${tier_type}",
  "databases": [$(printf '"%s",' "${dbs[@]}" | sed 's/,$//')],
  "failed_databases": [$(printf '"%s",' "${failed_dbs[@]}" | sed 's/,$//' | sed 's/^""$//')],
  "backup_size": "${size}",
  ${retention_field},
  "mysql_version": "${mysql_ver}",
  "performance": {
    "duration_seconds": ${total_duration},
    "uncompressed_size_mb": ${total_uncompressed_size},
    "compressed_size_mb": ${total_compressed_size},
    "compression_ratio_percent": ${compression_ratio},
    "throughput_mb_per_second": ${backup_rate}
  }
}
EOF

  # The completion marker asserts every database dumped AND verified; a
  # partial backup must never look restorable to the restore tooling.
  if [ ${#failed_dbs[@]} -eq 0 ]; then
    touch "$target_dir/.backup_complete"
  else
    alert "${tier_type} backup ${ts} INCOMPLETE - failed: ${failed_dbs[*]} (no completion marker written)"
  fi

  log "Backup complete: $target_dir (size ${size})"
  log "📊 Backup Statistics:"
  log "   • Total time: ${total_duration}s ($(printf '%02d:%02d:%02d' $((total_duration/3600)) $((total_duration%3600/60)) $((total_duration%60))))"
  log "   • Data processed: ${total_uncompressed_size}MB → ${total_compressed_size}MB"
  log "   • Compression: ${compression_ratio}% space saved"
  log "   • Throughput: ${backup_rate}MB/s"

  # Performance warnings
  if [[ $total_duration -gt 3600 ]]; then
    log "⚠️  Very slow backup detected: ${total_duration}s (>1 hour)"
    log "💡 Consider optimizing database or backup strategy"
  elif [[ $total_duration -gt 1800 ]]; then
    log "⚠️  Slow backup detected: ${total_duration}s (>30min)"
  fi
  if find "$target_dir" ! -user "$(id -un)" -o ! -group "$(id -gn)" -prune -print -quit >/dev/null 2>&1; then
    log "ℹ️  Ownership drift detected; correcting permissions in $target_dir"
    if chown -R "$(id -u):$(id -g)" "$target_dir" >/dev/null 2>&1; then
      chmod -R u+rwX,g+rX "$target_dir" >/dev/null 2>&1 || true
      log "✅ Ownership reset for $target_dir"
    else
      log "⚠️  Failed to adjust ownership for $target_dir"
    fi
  fi
}

cleanup_old() {
  find "$HOURLY_DIR" -mindepth 1 -maxdepth 1 -type d -mmin +$((RETENTION_HOURS*60)) -print -exec rm -rf {} + 2>/dev/null || true
  find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -print -exec rm -rf {} + 2>/dev/null || true
  find "$MONTHLY_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_MONTHS*31)) -print -exec rm -rf {} + 2>/dev/null || true
}

# Promote the first complete daily backup of each month into the monthly
# tier so the recovery horizon extends beyond daily retention.
promote_monthly() {
  local month; month=$(date '+%Y%m')
  if find "$MONTHLY_DIR" -mindepth 1 -maxdepth 1 -type d -name "${month}*" -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  local candidate
  candidate=$(find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -name "${month}*" 2>/dev/null | sort | while read -r d; do
    [ -f "$d/.backup_complete" ] && echo "$d" && break
  done)
  if [ -n "$candidate" ]; then
    if cp -a "$candidate" "$MONTHLY_DIR/$(basename "$candidate")"; then
      log "📦 Promoted $(basename "$candidate") to monthly tier"
    else
      log "⚠️  Failed to promote $(basename "$candidate") to monthly tier"
    fi
  fi
}

log "Backup scheduler starting: interval(${BACKUP_INTERVAL_MINUTES}m), daily(${RETENTION_DAYS}d at ${DAILY_TIME}:00), monthly(${RETENTION_MONTHS}mo)"

# Initialize last backup time to current time to prevent immediate backup on startup
last_backup=$(date +%s)
# Seed the daily tracker from disk so a container restart neither skips
# nor duplicates the day's daily backup.
last_daily_date=""
if find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -name "$(date '+%Y%m%d')_*" -print -quit 2>/dev/null | grep -q .; then
  last_daily_date=$(date '+%F')
fi
log "ℹ️  First backup will run in ${BACKUP_INTERVAL_MINUTES} minutes"

while true; do
  current_time=$(date +%s)
  hour=$(date '+%H')
  today=$(date '+%F')

  # Run interval backups (replacing hourly)
  interval_seconds=$((BACKUP_INTERVAL_MINUTES * 60))
  if [ $((current_time - last_backup)) -ge $interval_seconds ]; then
    run_backup "$HOURLY_DIR" "interval"
    last_backup=$current_time
  fi

  # Daily backup: fire once per day at-or-after DAILY_TIME. Tracking the
  # date instead of matching minute 00 exactly means a slow interval
  # backup spanning the top of the hour cannot skip the day's daily.
  if [ "$hour" -ge "$DAILY_TIME" ] 2>/dev/null && [ "$last_daily_date" != "$today" ]; then
    run_backup "$DAILY_DIR" "daily"
    last_daily_date="$today"
    promote_monthly
  fi

  cleanup_old
  sleep 60
done

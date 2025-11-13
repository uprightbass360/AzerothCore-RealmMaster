#!/bin/bash
# azerothcore-rm
set -e

BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-/backups}"
HOURLY_DIR="$BACKUP_DIR_BASE/hourly"
DAILY_DIR="$BACKUP_DIR_BASE/daily"
RETENTION_HOURS=${BACKUP_RETENTION_HOURS:-6}
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-3}
DAILY_TIME=${BACKUP_DAILY_TIME:-09}
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL_MINUTES:-60}
MYSQL_PORT=${MYSQL_PORT:-3306}

mkdir -p "$HOURLY_DIR" "$DAILY_DIR"

log() { echo "[$(date '+%F %T')] $*"; }

db_exists() {
  local name="$1"
  [ -z "$name" ] && return 1
  local sanitized="${name//\`/}"
  if mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "USE \`${sanitized}\`;" >/dev/null 2>&1; then
    return 0
  fi
  return 1
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
  mapfile -t dbs < <(database_list)
  local backup_start_time=$(date +%s)
  local total_uncompressed_size=0
  local total_compressed_size=0

  for db in "${dbs[@]}"; do
    local db_start_time=$(date +%s)
    log "Backing up database: $db"

    # Get database size before backup
    local db_size_mb=$(mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
      -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb FROM information_schema.tables WHERE table_schema = '$db';" \
      -s -N 2>/dev/null || echo "0")

    if mysqldump \
      -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
      --single-transaction --routines --triggers --events \
      --hex-blob --quick --lock-tables=false \
      --add-drop-database --databases "$db" \
      | gzip -c > "$target_dir/${db}.sql.gz"; then

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
      log "❌ Failed to back up $db"
    fi
  done

  # Calculate overall backup statistics
  local backup_end_time=$(date +%s)
  local total_duration=$((backup_end_time - backup_start_time))
  # Use awk for calculations (more portable than bc)
  local compression_ratio=$(awk "BEGIN {if($total_uncompressed_size > 0) printf \"%.1f\", ($total_uncompressed_size - $total_compressed_size) * 100 / $total_uncompressed_size; else print \"0\"}")
  local backup_rate=$(awk "BEGIN {if($total_duration > 0) printf \"%.2f\", $total_uncompressed_size / $total_duration; else print \"0\"}")

  # Create backup manifest (parity with scripts/backup.sh and backup-hourly.sh)
  local size; size=$(du -sh "$target_dir" | cut -f1)
  local mysql_ver; mysql_ver=$(mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e 'SELECT VERSION();' -s -N 2>/dev/null || echo "unknown")

  if [ "$tier_type" = "hourly" ]; then
    cat > "$target_dir/manifest.json" <<EOF
{
  "timestamp": "${ts}",
  "type": "hourly",
  "databases": [$(printf '"%s",' "${dbs[@]}" | sed 's/,$//')],
  "backup_size": "${size}",
  "retention_hours": ${RETENTION_HOURS},
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
  else
    cat > "$target_dir/manifest.json" <<EOF
{
  "timestamp": "${ts}",
  "type": "daily",
  "databases": [$(printf '"%s",' "${dbs[@]}" | sed 's/,$//')],
  "backup_size": "${size}",
  "retention_days": ${RETENTION_DAYS},
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
  fi

  # Create completion marker to indicate backup is finished
  touch "$target_dir/.backup_complete"

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
}

log "Backup scheduler starting: interval(${BACKUP_INTERVAL_MINUTES}m), daily($RETENTION_DAYS d at ${DAILY_TIME}:00)"

# Initialize last backup time
last_backup=0

while true; do
  current_time=$(date +%s)
  minute=$(date '+%M')
  hour=$(date '+%H')

  # Run interval backups (replacing hourly)
  interval_seconds=$((BACKUP_INTERVAL_MINUTES * 60))
  if [ $((current_time - last_backup)) -ge $interval_seconds ]; then
    run_backup "$HOURLY_DIR" "interval"
    last_backup=$current_time
  fi

  # Keep daily backup at specified time
  if [ "$hour" = "$DAILY_TIME" ] && [ "$minute" = "00" ]; then
    run_backup "$DAILY_DIR" "daily"
  fi

  cleanup_old
  sleep 60
done

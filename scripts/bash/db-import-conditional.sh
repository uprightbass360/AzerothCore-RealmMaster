#!/bin/bash
# azerothcore-rm
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

print_help() {
  cat <<'EOF'
Usage: db-import-conditional.sh [options]

Description:
  Conditionally restores AzerothCore databases from backups if available;
  otherwise creates fresh databases and runs the dbimport tool to populate
  schemas. Uses status markers to prevent overwriting restored data.

Options:
  -h, --help    Show this help message and exit

Environment variables:
  CONTAINER_MYSQL        Hostname of the MySQL container (default: ac-mysql)
  MYSQL_PORT             MySQL port (default: 3306)
  MYSQL_USER             MySQL user (default: root)
  MYSQL_ROOT_PASSWORD    MySQL password for the user above
  DB_AUTH_NAME           Auth DB name (default: acore_auth)
  DB_WORLD_NAME          World DB name (default: acore_world)
  DB_CHARACTERS_NAME     Characters DB name (default: acore_characters)
  BACKUP DIRS            Uses /backups/{daily,timestamped} if present
  STATUS MARKERS         Uses /var/lib/mysql-persistent/.restore-*

Notes:
  - If a valid backup is detected and successfully restored, schema import is skipped.
  - On fresh setups, the script creates databases and runs dbimport.
EOF
}

verify_databases_populated() {
  local mysql_host="${CONTAINER_MYSQL:-ac-mysql}"
  local mysql_port="${MYSQL_PORT:-3306}"
  local mysql_user="${MYSQL_USER:-root}"
  local mysql_pass="${MYSQL_ROOT_PASSWORD:-root}"
  local db_auth="${DB_AUTH_NAME:-acore_auth}"
  local db_world="${DB_WORLD_NAME:-acore_world}"
  local db_characters="${DB_CHARACTERS_NAME:-acore_characters}"

  if ! command -v mysql >/dev/null 2>&1; then
    echo "⚠️  mysql client is not available to verify restoration status"
    return 1
  fi

  local query="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('$db_auth','$db_world','$db_characters');"
  local table_count
  if ! table_count=$(MYSQL_PWD="$mysql_pass" mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" -N -B -e "$query" 2>/dev/null); then
    echo "⚠️  Unable to query MySQL at ${mysql_host}:${mysql_port} to verify restoration status"
    return 1
  fi

  if [ "${table_count:-0}" -gt 0 ]; then
    return 0
  fi

  echo "⚠️  MySQL is reachable but no AzerothCore tables were found"
  return 1
}

wait_for_mysql(){
  local mysql_host="${CONTAINER_MYSQL:-ac-mysql}"
  local mysql_port="${MYSQL_PORT:-3306}"
  local mysql_user="${MYSQL_USER:-root}"
  local mysql_pass="${MYSQL_ROOT_PASSWORD:-root}"
  local max_attempts=30
  local delay=2
  while [ $max_attempts -gt 0 ]; do
    if MYSQL_PWD="$mysql_pass" mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" -e "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    max_attempts=$((max_attempts - 1))
    sleep "$delay"
  done
  echo "❌ Unable to connect to MySQL at ${mysql_host}:${mysql_port} after multiple attempts"
  return 1
}

case "${1:-}" in
  -h|--help)
    print_help
    exit 0
    ;;
  "") ;;
  *)
    echo "Unknown option: $1" >&2
    print_help
    exit 1
    ;;
esac

echo "🔧 Conditional AzerothCore Database Import"
echo "========================================"

SEED_CONF_SCRIPT="${SEED_DBIMPORT_CONF_SCRIPT:-/tmp/seed-dbimport-conf.sh}"
if [ -f "$SEED_CONF_SCRIPT" ]; then
  # shellcheck source=/dev/null
  . "$SEED_CONF_SCRIPT"
elif ! command -v seed_dbimport_conf >/dev/null 2>&1; then
  seed_dbimport_conf(){
    local conf="/azerothcore/env/dist/etc/dbimport.conf"
    local dist="${conf}.dist"
    mkdir -p "$(dirname "$conf")"
    [ -f "$conf" ] && return 0
    if [ -f "$dist" ]; then
      cp "$dist" "$conf"
    else
      echo "⚠️  dbimport.conf missing and no dist available; using localhost defaults" >&2
      cat > "$conf" <<EOF
LoginDatabaseInfo = "localhost;3306;root;root;acore_auth"
WorldDatabaseInfo = "localhost;3306;root;root;acore_world"
CharacterDatabaseInfo = "localhost;3306;root;root;acore_characters"
PlayerbotsDatabaseInfo = "localhost;3306;root;root;acore_playerbots"
EnableDatabases = 15
Updates.AutoSetup = 1
MySQLExecutable = "/usr/bin/mysql"
TempDir = "/azerothcore/env/dist/etc/temp"
EOF
    fi
  }
fi

if ! wait_for_mysql; then
  echo "❌ MySQL service is unavailable; aborting database import"
  exit 1
fi

# Restoration status markers - use writable location
RESTORE_STATUS_DIR="/var/lib/mysql-persistent"
MARKER_STATUS_DIR="/tmp"
RESTORE_SUCCESS_MARKER="$RESTORE_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER="$RESTORE_STATUS_DIR/.restore-failed"
RESTORE_SUCCESS_MARKER_TMP="$MARKER_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER_TMP="$MARKER_STATUS_DIR/.restore-failed"

mkdir -p "$RESTORE_STATUS_DIR" 2>/dev/null || true
if ! touch "$RESTORE_STATUS_DIR/.test-write" 2>/dev/null; then
  echo "⚠️  Cannot write to $RESTORE_STATUS_DIR, using $MARKER_STATUS_DIR for markers"
  RESTORE_SUCCESS_MARKER="$RESTORE_SUCCESS_MARKER_TMP"
  RESTORE_FAILED_MARKER="$RESTORE_FAILED_MARKER_TMP"
else
  rm -f "$RESTORE_STATUS_DIR/.test-write" 2>/dev/null || true
fi

echo "🔍 Checking restoration status..."

if [ -f "$RESTORE_SUCCESS_MARKER" ]; then
  if verify_databases_populated; then
    echo "✅ Backup restoration completed successfully"
    cat "$RESTORE_SUCCESS_MARKER" || true
    echo "🚫 Skipping database import - data already restored from backup"
    exit 0
  fi

  echo "⚠️  Restoration marker found, but databases are empty - forcing re-import"
  rm -f "$RESTORE_SUCCESS_MARKER" 2>/dev/null || true
  rm -f "$RESTORE_SUCCESS_MARKER_TMP" 2>/dev/null || true
  rm -f "$RESTORE_FAILED_MARKER" 2>/dev/null || true
fi

if [ -f "$RESTORE_FAILED_MARKER" ]; then
  echo "ℹ️  No backup was restored - fresh databases detected"
  cat "$RESTORE_FAILED_MARKER" || true
  echo "▶️  Proceeding with database import to populate fresh databases"
else
  echo "⚠️  No restoration status found - assuming fresh installation"
  echo "▶️  Proceeding with database import"
fi

echo ""
echo "🔧 Starting database import process..."

echo "🔍 Checking for backups to restore..."

# Allow tolerant scanning; re-enable -e after search.
set +e
# Define backup search paths in priority order
BACKUP_SEARCH_PATHS=(
  "/backups"
  "/var/lib/mysql-persistent"
  "$PROJECT_ROOT/storage/backups"
  "$PROJECT_ROOT/manual-backups"
)

backup_path=""

echo "🔍 Checking for legacy backup file..."
if [ -f "/var/lib/mysql-persistent/backup.sql" ]; then
  echo "📄 Found legacy backup file, validating content..."
  if timeout 10 head -10 "/var/lib/mysql-persistent/backup.sql" 2>/dev/null | grep -q "CREATE DATABASE\|INSERT INTO\|CREATE TABLE"; then
    echo "✅ Legacy backup file validated"
    backup_path="/var/lib/mysql-persistent/backup.sql"
  else
    echo "⚠️  Legacy backup file exists but appears invalid or empty"
  fi
else
  echo "🔍 No legacy backup found"
fi

# Search through backup directories
if [ -z "$backup_path" ]; then
  for BACKUP_DIRS in "${BACKUP_SEARCH_PATHS[@]}"; do
    if [ ! -d "$BACKUP_DIRS" ]; then
      continue
    fi

    echo "📁 Checking backup directory: $BACKUP_DIRS"
    if [ -n "$(ls -A "$BACKUP_DIRS" 2>/dev/null)" ]; then
      # Check for daily backups first
      if [ -d "$BACKUP_DIRS/daily" ]; then
        echo "🔍 Checking for daily backups..."
        latest_daily=$(ls -1t "$BACKUP_DIRS/daily" 2>/dev/null | head -n 1)
        if [ -n "$latest_daily" ] && [ -d "$BACKUP_DIRS/daily/$latest_daily" ]; then
          echo "📦 Latest daily backup found: $latest_daily"
          for backup_file in "$BACKUP_DIRS/daily/$latest_daily"/*.sql.gz; do
            if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
              if timeout 10 gzip -t "$backup_file" >/dev/null 2>&1; then
                echo "✅ Valid daily backup file: $(basename "$backup_file")"
                backup_path="$BACKUP_DIRS/daily/$latest_daily"
                break 2
              else
                echo "⚠️  gzip validation failed for $(basename "$backup_file")"
              fi
            fi
          done
        fi
      fi

      # Check for hourly backups
      if [ -z "$backup_path" ] && [ -d "$BACKUP_DIRS/hourly" ]; then
        echo "🔍 Checking for hourly backups..."
        latest_hourly=$(ls -1t "$BACKUP_DIRS/hourly" 2>/dev/null | head -n 1)
        if [ -n "$latest_hourly" ] && [ -d "$BACKUP_DIRS/hourly/$latest_hourly" ]; then
          echo "📦 Latest hourly backup found: $latest_hourly"
          for backup_file in "$BACKUP_DIRS/hourly/$latest_hourly"/*.sql.gz; do
            if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
              if timeout 10 gzip -t "$backup_file" >/dev/null 2>&1; then
                echo "✅ Valid hourly backup file: $(basename "$backup_file")"
                backup_path="$BACKUP_DIRS/hourly/$latest_hourly"
                break 2
              else
                echo "⚠️  gzip validation failed for $(basename "$backup_file")"
              fi
            fi
          done
        fi
      fi

      # Check for timestamped backup directories (like ExportBackup_YYYYMMDD_HHMMSS)
      if [ -z "$backup_path" ]; then
        echo "🔍 Checking for timestamped backup directories..."
        timestamped_backups=$(ls -1t "$BACKUP_DIRS" 2>/dev/null | grep -E '^(ExportBackup_)?[0-9]{8}_[0-9]{6}$' | head -n 1)
        if [ -n "$timestamped_backups" ]; then
          latest_timestamped="$timestamped_backups"
          echo "📦 Found timestamped backup: $latest_timestamped"
          if [ -d "$BACKUP_DIRS/$latest_timestamped" ]; then
            if ls "$BACKUP_DIRS/$latest_timestamped"/*.sql.gz >/dev/null 2>&1; then
              echo "🔍 Validating timestamped backup content..."
              for backup_file in "$BACKUP_DIRS/$latest_timestamped"/*.sql.gz; do
                if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
                  if timeout 10 gzip -t "$backup_file" >/dev/null 2>&1; then
                    echo "✅ Valid timestamped backup found: $(basename "$backup_file")"
                    backup_path="$BACKUP_DIRS/$latest_timestamped"
                    break 2
                  else
                    echo "⚠️  gzip validation failed for $(basename "$backup_file")"
                  fi
                fi
              done
            fi
          fi
        fi
      fi

      # Check for manual backups (*.sql files)
      if [ -z "$backup_path" ]; then
        echo "🔍 Checking for manual backup files..."
        latest_manual=""
        if ls "$BACKUP_DIRS"/*.sql >/dev/null 2>&1; then
          latest_manual=$(ls -1t "$BACKUP_DIRS"/*.sql | head -n 1)
          if [ -n "$latest_manual" ] && [ -f "$latest_manual" ]; then
            echo "📦 Found manual backup: $(basename "$latest_manual")"
            if timeout 10 head -20 "$latest_manual" >/dev/null 2>&1; then
              echo "✅ Valid manual backup file: $(basename "$latest_manual")"
              backup_path="$latest_manual"
              break
            fi
          fi
        fi
      fi
    fi

    # If we found a backup in this directory, stop searching
    if [ -n "$backup_path" ]; then
      break
    fi
  done
fi

set -e
echo "🔄 Final backup path result: '$backup_path'"
if [ -n "$backup_path" ]; then
  echo "📦 Found backup: $(basename "$backup_path")"

  restore_backup() {
    local backup_path="$1"
    local restore_success=true

    if [ -d "$backup_path" ]; then
      echo "🔄 Restoring from backup directory: $backup_path"

      # Check for manifest file to understand backup structure
      if [ -f "$backup_path/manifest.json" ]; then
        echo "📋 Found manifest file, checking backup contents..."
        cat "$backup_path/manifest.json"
      fi

      # Restore compressed SQL files
      if ls "$backup_path"/*.sql.gz >/dev/null 2>&1; then
        for backup_file in "$backup_path"/*.sql.gz; do
          if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
            echo "🔄 Restoring $(basename "$backup_file")..."
            if timeout 300 zcat "$backup_file" | mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD}; then
              echo "✅ Restored $(basename "$backup_file")"
            else
              echo "❌ Failed to restore $(basename "$backup_file")"
              restore_success=false
            fi
          fi
        done
      fi

      # Also check for uncompressed SQL files
      if ls "$backup_path"/*.sql >/dev/null 2>&1; then
        for backup_file in "$backup_path"/*.sql; do
          if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
            echo "🔄 Restoring $(basename "$backup_file")..."
            if timeout 300 mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} < "$backup_file"; then
              echo "✅ Restored $(basename "$backup_file")"
            else
              echo "❌ Failed to restore $(basename "$backup_file")"
              restore_success=false
            fi
          fi
        done
      fi

    elif [ -f "$backup_path" ]; then
      echo "🔄 Restoring from backup file: $backup_path"
      case "$backup_path" in
        *.gz)
          if timeout 300 zcat "$backup_path" | mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD}; then
            echo "✅ Restored compressed backup"
          else
            echo "❌ Failed to restore compressed backup"
            restore_success=false
          fi
          ;;
        *.sql)
          if timeout 300 mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} < "$backup_path"; then
            echo "✅ Restored SQL backup"
          else
            echo "❌ Failed to restore SQL backup"
            restore_success=false
          fi
          ;;
        *)
          echo "⚠️  Unknown backup file format: $backup_path"
          restore_success=false
          ;;
      esac
    fi

    return $([ "$restore_success" = true ] && echo 0 || echo 1)
  }

  verify_and_update_restored_databases() {
    echo "🔍 Verifying restored database integrity..."

    # Check if dbimport is available
    if [ ! -f "/azerothcore/env/dist/bin/dbimport" ]; then
      echo "⚠️  dbimport not available, skipping verification"
      return 0
    fi

    seed_dbimport_conf

    cd /azerothcore/env/dist/bin
    echo "🔄 Running dbimport to apply any missing updates..."
    if ./dbimport; then
      echo "✅ Database verification complete - all updates current"
    else
      echo "⚠️  dbimport reported issues - check logs"
      return 1
    fi

    # Verify critical tables exist
    echo "🔍 Checking critical tables..."
    local critical_tables=("account" "characters" "creature" "quest_template")
    local missing_tables=0

    for table in "${critical_tables[@]}"; do
      local db_name="$DB_WORLD_NAME"
      case "$table" in
        account) db_name="$DB_AUTH_NAME" ;;
        characters) db_name="$DB_CHARACTERS_NAME" ;;
      esac

      if ! mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} \
              -e "SELECT 1 FROM ${db_name}.${table} LIMIT 1" >/dev/null 2>&1; then
        echo "⚠️  Critical table missing: ${db_name}.${table}"
        missing_tables=$((missing_tables + 1))
      fi
    done

    if [ "$missing_tables" -gt 0 ]; then
      echo "⚠️  ${missing_tables} critical tables missing after restore"
      return 1
    fi

    echo "✅ All critical tables verified"
    return 0
  }

  if restore_backup "$backup_path"; then
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🎉 Backup restoration completed successfully!"

    # Verify and apply missing updates
    verify_and_update_restored_databases

    if [ -x "/tmp/restore-and-stage.sh" ]; then
      echo "🔧 Running restore-time module SQL staging..."
      MODULES_DIR="/modules" \
      RESTORE_SOURCE_DIR="$backup_path" \
      /tmp/restore-and-stage.sh
    else
      echo "ℹ️  restore-and-stage helper not available; skipping automatic module SQL staging"
    fi

    exit 0
  else
    echo "$(date): Backup restoration failed - proceeding with fresh setup" > "$RESTORE_FAILED_MARKER"
    echo "⚠️  Backup restoration failed, will proceed with fresh database setup"
  fi
else
  echo "ℹ️  No valid SQL backups found - proceeding with fresh setup"
  echo "$(date): No backup found - fresh setup needed" > "$RESTORE_FAILED_MARKER"
fi

echo "🗄️ Creating fresh AzerothCore databases..."
mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
DROP DATABASE IF EXISTS ${DB_AUTH_NAME};
DROP DATABASE IF EXISTS ${DB_WORLD_NAME};
DROP DATABASE IF EXISTS ${DB_CHARACTERS_NAME};
DROP DATABASE IF EXISTS ${DB_PLAYERBOTS_NAME:-acore_playerbots};
CREATE DATABASE ${DB_AUTH_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE ${DB_WORLD_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE ${DB_CHARACTERS_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE ${DB_PLAYERBOTS_NAME:-acore_playerbots} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SHOW DATABASES;" || { echo "❌ Failed to create databases"; exit 1; }
echo "✅ Fresh databases created - proceeding with schema import"

echo "🚀 Running database import..."
cd /azerothcore/env/dist/bin
seed_dbimport_conf

maybe_run_base_import(){
  local mysql_host="${CONTAINER_MYSQL:-ac-mysql}"
  local mysql_port="${MYSQL_PORT:-3306}"
  local mysql_user="${MYSQL_USER:-root}"
  local mysql_pass="${MYSQL_ROOT_PASSWORD:-root}"

  import_dir(){
    local db="$1" dir="$2"
    [ -d "$dir" ] || return 0
    echo "🔧 Importing base schema for ${db} from $(basename "$dir")..."
    for f in $(ls "$dir"/*.sql 2>/dev/null | LC_ALL=C sort); do
      MYSQL_PWD="$mysql_pass" mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" "$db" < "$f" >/dev/null 2>&1 || true
    done
  }

  needs_import(){
    local db="$1"
    local count
    count="$(MYSQL_PWD="$mysql_pass" mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db}';" 2>/dev/null || echo 0)"
    [ "${count:-0}" -eq 0 ] && return 0
    local updates
    updates="$(MYSQL_PWD="$mysql_pass" mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db}' AND table_name='updates';" 2>/dev/null || echo 0)"
    [ "${updates:-0}" -eq 0 ]
  }

  if needs_import "${DB_WORLD_NAME:-acore_world}"; then
    import_dir "${DB_WORLD_NAME:-acore_world}" "/azerothcore/data/sql/base/db_world"
  fi
  if needs_import "${DB_AUTH_NAME:-acore_auth}"; then
    import_dir "${DB_AUTH_NAME:-acore_auth}" "/azerothcore/data/sql/base/db_auth"
  fi
  if needs_import "${DB_CHARACTERS_NAME:-acore_characters}"; then
    import_dir "${DB_CHARACTERS_NAME:-acore_characters}" "/azerothcore/data/sql/base/db_characters"
  fi
}

maybe_run_base_import
if ./dbimport; then
  echo "✅ Database import completed successfully!"
  import_marker_msg="$(date): Database import completed successfully"
  if [ -w "$RESTORE_STATUS_DIR" ]; then
    echo "$import_marker_msg" > "$RESTORE_STATUS_DIR/.import-completed"
  elif [ -w "$MARKER_STATUS_DIR" ]; then
    echo "$import_marker_msg" > "$MARKER_STATUS_DIR/.import-completed" 2>/dev/null || true
  fi
else
  echo "❌ Database import failed!"
  if [ -w "$RESTORE_STATUS_DIR" ]; then
    echo "$(date): Database import failed" > "$RESTORE_STATUS_DIR/.import-failed"
  elif [ -w "$MARKER_STATUS_DIR" ]; then
    echo "$(date): Database import failed" > "$MARKER_STATUS_DIR/.import-failed" 2>/dev/null || true
  fi
  exit 1
fi

echo "🎉 Database import process complete!"

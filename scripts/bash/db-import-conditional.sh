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
  echo "✅ Backup restoration completed successfully"
  cat "$RESTORE_SUCCESS_MARKER" || true
  echo "🚫 Skipping database import - data already restored from backup"
  exit 0
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
              if timeout 10 zcat "$backup_file" 2>/dev/null | head -20 | grep -q "CREATE DATABASE\|INSERT INTO\|CREATE TABLE"; then
                echo "✅ Valid daily backup file: $(basename "$backup_file")"
                backup_path="$BACKUP_DIRS/daily/$latest_daily"
                break 2
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
              if timeout 10 zcat "$backup_file" >/dev/null 2>&1; then
                echo "✅ Valid hourly backup file: $(basename "$backup_file")"
                backup_path="$BACKUP_DIRS/hourly/$latest_hourly"
                break 2
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
                  if timeout 10 zcat "$backup_file" >/dev/null 2>&1; then
                    echo "✅ Valid timestamped backup found: $(basename "$backup_file")"
                    backup_path="$BACKUP_DIRS/$latest_timestamped"
                    break 2
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
        latest_manual=$(ls -1t "$BACKUP_DIRS"/*.sql 2>/dev/null | head -n 1)
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

    # If we found a backup in this directory, stop searching
    if [ -n "$backup_path" ]; then
      break
    fi
  done
fi

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

  if restore_backup "$backup_path"; then
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🎉 Backup restoration completed successfully!"
    exit 0
  else
    echo "$(date): Backup restoration failed - proceeding with fresh setup" > "$RESTORE_FAILED_MARKER"
    echo "⚠️  Backup restoration failed, will proceed with fresh database setup"
  fi
else
  echo "ℹ️  No valid backups found - proceeding with fresh setup"
  echo "$(date): No backup found - fresh setup needed" > "$RESTORE_FAILED_MARKER"
fi

echo "🗄️ Creating fresh AzerothCore databases..."
mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
CREATE DATABASE IF NOT EXISTS ${DB_AUTH_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ${DB_WORLD_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ${DB_CHARACTERS_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS acore_playerbots DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SHOW DATABASES;" || { echo "❌ Failed to create databases"; exit 1; }
echo "✅ Fresh databases created - proceeding with schema import"

echo "📝 Creating dbimport configuration..."
mkdir -p /azerothcore/env/dist/etc
TEMP_DIR="/azerothcore/env/dist/temp"
mkdir -p "$TEMP_DIR"
MYSQL_EXECUTABLE="$(command -v mysql || echo '/usr/bin/mysql')"
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
Updates.EnableDatabases = 7
Updates.AutoSetup = 1
TempDir = "${TEMP_DIR}"
MySQLExecutable = "${MYSQL_EXECUTABLE}"
Updates.AllowedModules = "all"
LoginDatabase.WorkerThreads = 1
LoginDatabase.SynchThreads = 1
WorldDatabase.WorkerThreads = 1
WorldDatabase.SynchThreads = 1
CharacterDatabase.WorkerThreads = 1
CharacterDatabase.SynchThreads = 1
SourceDirectory = "/azerothcore"
Updates.ExceptionShutdownDelay = 10000
EOF

echo "🚀 Running database import..."
cd /azerothcore/env/dist/bin
if ./dbimport; then
  echo "✅ Database import completed successfully!"
  echo "$(date): Database import completed successfully" > "$RESTORE_STATUS_DIR/.import-completed" || echo "$(date): Database import completed successfully" > "$MARKER_STATUS_DIR/.import-completed"
else
  echo "❌ Database import failed!"
  echo "$(date): Database import failed" > "$RESTORE_STATUS_DIR/.import-failed" || echo "$(date): Database import failed" > "$MARKER_STATUS_DIR/.import-failed"
  exit 1
fi

echo "🎉 Database import process complete!"

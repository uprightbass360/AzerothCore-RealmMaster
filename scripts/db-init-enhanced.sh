#!/bin/bash
set -e

echo "🔧 Enhanced AzerothCore Database Initialization"
echo "=============================================="

# Restoration status markers
RESTORE_STATUS_DIR="/var/lib/mysql-persistent"
RESTORE_SUCCESS_MARKER="$RESTORE_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER="$RESTORE_STATUS_DIR/.restore-failed"
BACKUP_DIRS="/backups"

# Clean up old status markers
rm -f "$RESTORE_SUCCESS_MARKER" "$RESTORE_FAILED_MARKER"

echo "🔧 Waiting for MySQL to be ready..."

# Wait for MySQL to be responsive with longer timeout
for i in $(seq 1 ${DB_WAIT_RETRIES}); do
  if mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ MySQL is responsive"
    break
  fi
  echo "⏳ Waiting for MySQL... attempt $i/${DB_WAIT_RETRIES}"
  sleep ${DB_WAIT_SLEEP}
done

# Function to check if databases have data (not just schema)
check_database_populated() {
  local db_name="$1"
  local table_count=$(mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='$db_name' AND table_type='BASE TABLE';" -s -N 2>/dev/null || echo "0")

  if [ "$table_count" -gt 0 ]; then
    echo "🔍 Database $db_name has $table_count tables"
    return 0
  else
    echo "🔍 Database $db_name is empty or doesn't exist"
    return 1
  fi
}

# Function to validate backup integrity
validate_backup() {
  local backup_path="$1"
  echo "🔍 Validating backup: $backup_path"

  if [ -f "$backup_path" ]; then
    # Check if it's a valid SQL file
    if head -10 "$backup_path" | grep -q "CREATE DATABASE\|INSERT INTO\|CREATE TABLE"; then
      echo "✅ Backup appears valid"
      return 0
    fi
  fi

  echo "❌ Backup validation failed"
  return 1
}

# Function to find and validate the most recent backup
find_latest_backup() {
  echo "🔍 Searching for available backups..."

  # Priority 1: Legacy single backup file
  if [ -f "/var/lib/mysql-persistent/backup.sql" ]; then
    if validate_backup "/var/lib/mysql-persistent/backup.sql"; then
      echo "📦 Found valid legacy backup: backup.sql"
      echo "/var/lib/mysql-persistent/backup.sql"
      return 0
    fi
  fi

  # Priority 2: Modern timestamped backups
  if [ -d "$BACKUP_DIRS" ] && [ "$(ls -A $BACKUP_DIRS)" ]; then

    # Try daily backups first
    if [ -d "$BACKUP_DIRS/daily" ] && [ "$(ls -A $BACKUP_DIRS/daily)" ]; then
      local latest_daily=$(ls -1t $BACKUP_DIRS/daily | head -n 1)
      if [ -n "$latest_daily" ] && [ -d "$BACKUP_DIRS/daily/$latest_daily" ]; then
        echo "📦 Found daily backup: $latest_daily"
        echo "$BACKUP_DIRS/daily/$latest_daily"
        return 0
      fi
    fi

    # Try hourly backups second
    if [ -d "$BACKUP_DIRS/hourly" ] && [ "$(ls -A $BACKUP_DIRS/hourly)" ]; then
      local latest_hourly=$(ls -1t $BACKUP_DIRS/hourly | head -n 1)
      if [ -n "$latest_hourly" ] && [ -d "$BACKUP_DIRS/hourly/$latest_hourly" ]; then
        echo "📦 Found hourly backup: $latest_hourly"
        echo "$BACKUP_DIRS/hourly/$latest_hourly"
        return 0
      fi
    fi

    # Try legacy timestamped backups
    local latest_legacy=$(ls -1dt $BACKUP_DIRS/[0-9]* 2>/dev/null | head -n 1)
    if [ -n "$latest_legacy" ] && [ -d "$latest_legacy" ]; then
      echo "📦 Found legacy timestamped backup: $(basename $latest_legacy)"
      echo "$latest_legacy"
      return 0
    fi
  fi

  echo "ℹ️  No valid backups found"
  return 1
}

# Function to restore from timestamped backup directory
restore_from_directory() {
  local backup_dir="$1"
  echo "🔄 Restoring from backup directory: $backup_dir"

  local restore_success=true

  # Restore each database backup
  for backup_file in "$backup_dir"/*.sql.gz; do
    if [ -f "$backup_file" ]; then
      local db_name=$(basename "$backup_file" .sql.gz)
      echo "📥 Restoring database: $db_name"

      if zcat "$backup_file" | mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD}; then
        echo "✅ Successfully restored $db_name"
      else
        echo "❌ Failed to restore $db_name"
        restore_success=false
      fi
    fi
  done

  if [ "$restore_success" = true ]; then
    return 0
  else
    return 1
  fi
}

# Function to restore from single SQL file
restore_from_file() {
  local backup_file="$1"
  echo "🔄 Restoring from backup file: $backup_file"

  if mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} < "$backup_file"; then
    echo "✅ Successfully restored from $backup_file"
    return 0
  else
    echo "❌ Failed to restore from $backup_file"
    return 1
  fi
}

# Main backup detection and restoration logic
backup_restored=false

# Check if databases already have data
if check_database_populated "${DB_AUTH_NAME}" && check_database_populated "${DB_WORLD_NAME}"; then
  echo "✅ Databases already populated - skipping backup detection"
  backup_restored=true
else
  echo "🔍 Databases appear empty - checking for backups to restore..."

  backup_path=$(find_latest_backup)
  if [ $? -eq 0 ] && [ -n "$backup_path" ]; then
    echo "📦 Latest backup found: $backup_path"

    if [ -f "$backup_path" ]; then
      # Single file backup
      if restore_from_file "$backup_path"; then
        backup_restored=true
      fi
    elif [ -d "$backup_path" ]; then
      # Directory backup
      if restore_from_directory "$backup_path"; then
        backup_restored=true
      fi
    fi
  fi
fi

# Create databases if restore didn't happen or failed
if [ "$backup_restored" = false ]; then
  echo "🗄️ Creating fresh AzerothCore databases..."
  mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
CREATE DATABASE IF NOT EXISTS ${DB_AUTH_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
CREATE DATABASE IF NOT EXISTS ${DB_WORLD_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
CREATE DATABASE IF NOT EXISTS ${DB_CHARACTERS_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
SHOW DATABASES;
" || {
    echo "❌ Failed to create databases"
    exit 1
  }
  echo "✅ Fresh databases created!"
fi

# Set restoration status markers for db-import service
if [ "$backup_restored" = true ]; then
  echo "📝 Creating restoration success marker"
  touch "$RESTORE_SUCCESS_MARKER"
  echo "$(date): Backup successfully restored" > "$RESTORE_SUCCESS_MARKER"
  echo "🚫 DB import will be skipped - restoration completed successfully"
else
  echo "📝 Creating restoration failed marker"
  touch "$RESTORE_FAILED_MARKER"
  echo "$(date): No backup restored - fresh databases created" > "$RESTORE_FAILED_MARKER"
  echo "▶️  DB import will proceed - fresh databases need population"
fi

echo "✅ Database initialization complete!"
echo "   Backup restored: $backup_restored"
echo "   Status marker: $([ "$backup_restored" = true ] && echo "$RESTORE_SUCCESS_MARKER" || echo "$RESTORE_FAILED_MARKER")"
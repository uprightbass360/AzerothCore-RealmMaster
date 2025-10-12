#!/bin/bash
set -e

echo "🧪 Testing Enhanced Backup Detection Logic"
echo "========================================="

# Test configuration
RESTORE_STATUS_DIR="./storage/azerothcore/mysql-data"
RESTORE_SUCCESS_MARKER="$RESTORE_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER="$RESTORE_STATUS_DIR/.restore-failed"
BACKUP_DIRS="./storage/azerothcore/backups"

# Clean up old status markers
rm -f "$RESTORE_SUCCESS_MARKER" "$RESTORE_FAILED_MARKER"

echo "🔍 Test Environment:"
echo "   Backup directory: $BACKUP_DIRS"
echo "   Status directory: $RESTORE_STATUS_DIR"
echo ""

# Function to validate backup
validate_backup() {
  local backup_path="$1"
  echo "🔍 Validating backup: $backup_path"

  if [ -f "$backup_path" ]; then
    # Check if it's a valid SQL file
    if head -10 "$backup_path" | grep -q "CREATE DATABASE\|INSERT INTO\|CREATE TABLE\|DROP DATABASE"; then
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
  if [ -f "./storage/azerothcore/mysql-data/backup.sql" ]; then
    if validate_backup "./storage/azerothcore/mysql-data/backup.sql"; then
      echo "📦 Found valid legacy backup: backup.sql"
      echo "./storage/azerothcore/mysql-data/backup.sql"
      return 0
    fi
  fi

  # Priority 2: Modern timestamped backups
  if [ -d "$BACKUP_DIRS" ] && [ "$(ls -A $BACKUP_DIRS 2>/dev/null)" ]; then

    # Try daily backups first
    if [ -d "$BACKUP_DIRS/daily" ] && [ "$(ls -A $BACKUP_DIRS/daily 2>/dev/null)" ]; then
      local latest_daily=$(ls -1t $BACKUP_DIRS/daily 2>/dev/null | head -n 1)
      if [ -n "$latest_daily" ] && [ -d "$BACKUP_DIRS/daily/$latest_daily" ]; then
        echo "📦 Found daily backup: $latest_daily"
        echo "$BACKUP_DIRS/daily/$latest_daily"
        return 0
      fi
    fi

    # Try hourly backups second
    if [ -d "$BACKUP_DIRS/hourly" ] && [ "$(ls -A $BACKUP_DIRS/hourly 2>/dev/null)" ]; then
      local latest_hourly=$(ls -1t $BACKUP_DIRS/hourly 2>/dev/null | head -n 1)
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

    # Try individual SQL files in backup root
    local sql_files=$(ls -1t $BACKUP_DIRS/*.sql $BACKUP_DIRS/*.sql.gz 2>/dev/null | head -n 1)
    if [ -n "$sql_files" ]; then
      echo "📦 Found individual SQL backup: $(basename $sql_files)"
      echo "$sql_files"
      return 0
    fi
  fi

  echo "ℹ️  No valid backups found"
  return 1
}

# Function to simulate restore from timestamped backup directory
simulate_restore_from_directory() {
  local backup_dir="$1"
  echo "🔄 Simulating restore from backup directory: $backup_dir"

  local restore_success=true
  local file_count=0

  # Check each database backup
  for backup_file in "$backup_dir"/*.sql.gz "$backup_dir"/*.sql; do
    if [ -f "$backup_file" ]; then
      local db_name=$(basename "$backup_file" .sql.gz)
      db_name=$(basename "$db_name" .sql)
      echo "📥 Would restore database: $db_name from $(basename $backup_file)"
      file_count=$((file_count + 1))
    fi
  done

  if [ $file_count -gt 0 ]; then
    echo "✅ Would successfully restore $file_count database(s)"
    return 0
  else
    echo "❌ No database files found in backup directory"
    return 1
  fi
}

# Function to simulate restore from single SQL file
simulate_restore_from_file() {
  local backup_file="$1"
  echo "🔄 Simulating restore from backup file: $backup_file"

  if [ -f "$backup_file" ]; then
    echo "✅ Would successfully restore from $(basename $backup_file)"
    return 0
  else
    echo "❌ Backup file not found: $backup_file"
    return 1
  fi
}

# Main backup detection and restoration logic
echo "🧪 Running backup detection test..."
echo ""

backup_restored=false

backup_path=$(find_latest_backup)
if [ $? -eq 0 ] && [ -n "$backup_path" ]; then
  echo ""
  echo "📦 Latest backup found: $backup_path"
  echo ""

  if [ -f "$backup_path" ]; then
    # Single file backup
    if simulate_restore_from_file "$backup_path"; then
      backup_restored=true
    fi
  elif [ -d "$backup_path" ]; then
    # Directory backup
    if simulate_restore_from_directory "$backup_path"; then
      backup_restored=true
    fi
  fi
else
  echo ""
  echo "ℹ️  No backups found - would create fresh databases"
fi

echo ""
echo "📊 Test Results:"
echo "   Backup detected: $([ $? -eq 0 ] && echo "Yes" || echo "No")"
echo "   Backup path: ${backup_path:-"None"}"
echo "   Would restore: $backup_restored"

# Simulate status marker creation
if [ "$backup_restored" = true ]; then
  echo "📝 Would create restoration success marker: $RESTORE_SUCCESS_MARKER"
  mkdir -p "$(dirname $RESTORE_SUCCESS_MARKER)"
  echo "$(date): [TEST] Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
  echo "🚫 DB import would be SKIPPED - restoration completed successfully"
else
  echo "📝 Would create restoration failed marker: $RESTORE_FAILED_MARKER"
  mkdir -p "$(dirname $RESTORE_FAILED_MARKER)"
  echo "$(date): [TEST] No backup restored - fresh databases would be created" > "$RESTORE_FAILED_MARKER"
  echo "▶️  DB import would PROCEED - fresh databases need population"
fi

echo ""
echo "🏁 Test Complete!"
echo ""
echo "📁 Created status marker files:"
ls -la "$RESTORE_STATUS_DIR"/.restore-* "$RESTORE_STATUS_DIR"/.import-* 2>/dev/null || echo "   No marker files found"

echo ""
echo "📝 Status marker contents:"
for marker in "$RESTORE_SUCCESS_MARKER" "$RESTORE_FAILED_MARKER"; do
  if [ -f "$marker" ]; then
    echo "   $(basename $marker): $(cat $marker)"
  fi
done
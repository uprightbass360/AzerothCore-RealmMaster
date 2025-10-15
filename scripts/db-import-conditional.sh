#!/bin/bash
set -e

echo "🔧 Conditional AzerothCore Database Import"
echo "========================================"

# Restoration status markers - use writable location
RESTORE_STATUS_DIR="/var/lib/mysql-persistent"
MARKER_STATUS_DIR="/tmp"
RESTORE_SUCCESS_MARKER="$RESTORE_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER="$RESTORE_STATUS_DIR/.restore-failed"
RESTORE_SUCCESS_MARKER_TMP="$MARKER_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER_TMP="$MARKER_STATUS_DIR/.restore-failed"

# Ensure we can write to the status directory, fallback to tmp
mkdir -p "$RESTORE_STATUS_DIR" 2>/dev/null || true
if ! touch "$RESTORE_STATUS_DIR/.test-write" 2>/dev/null; then
  echo "⚠️  Cannot write to $RESTORE_STATUS_DIR, using $MARKER_STATUS_DIR for markers"
  RESTORE_SUCCESS_MARKER="$RESTORE_SUCCESS_MARKER_TMP"
  RESTORE_FAILED_MARKER="$RESTORE_FAILED_MARKER_TMP"
else
  rm -f "$RESTORE_STATUS_DIR/.test-write" 2>/dev/null || true
fi

echo "🔍 Checking restoration status..."

# Check if backup was successfully restored
if [ -f "$RESTORE_SUCCESS_MARKER" ]; then
  echo "✅ Backup restoration completed successfully"
  echo "📄 Restoration details:"
  cat "$RESTORE_SUCCESS_MARKER"
  echo ""
  echo "🚫 Skipping database import - data already restored from backup"
  echo "💡 This prevents overwriting restored data with fresh schema"
  exit 0
fi

# Check if restoration failed (fresh databases created)
if [ -f "$RESTORE_FAILED_MARKER" ]; then
  echo "ℹ️  No backup was restored - fresh databases detected"
  echo "📄 Database creation details:"
  cat "$RESTORE_FAILED_MARKER"
  echo ""
  echo "▶️  Proceeding with database import to populate fresh databases"
else
  echo "⚠️  No restoration status found - assuming fresh installation"
  echo "▶️  Proceeding with database import"
fi

echo ""
echo "🔧 Starting database import process..."

# First attempt backup restoration
echo "🔍 Checking for backups to restore..."

BACKUP_DIRS="/backups"


# Function to restore from backup (directory or single file)
restore_from_directory() {
  local backup_path="$1"
  echo "🔄 Restoring from backup: $backup_path"

  local restore_success=true

  # Handle single .sql file (legacy backup)
  if [ -f "$backup_path" ] && [[ "$backup_path" == *.sql ]]; then
    echo "📥 Restoring legacy backup file: $(basename "$backup_path")"
    if timeout 300 mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} < "$backup_path"; then
      echo "✅ Successfully restored legacy backup"
      return 0
    else
      echo "❌ Failed to restore legacy backup"
      return 1
    fi
  fi

  # Handle directory with .sql.gz files (modern timestamped backups)
  if [ -d "$backup_path" ]; then
    echo "🔄 Restoring from backup directory: $backup_path"
    # Restore each database backup
    for backup_file in "$backup_path"/*.sql.gz; do
    if [ -f "$backup_file" ]; then
      local db_name=$(basename "$backup_file" .sql.gz)
      echo "📥 Restoring database: $db_name"

      if timeout 300 zcat "$backup_file" | mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD}; then
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
  fi

  # If we get here, backup_path is neither a valid .sql file nor a directory
  echo "❌ Invalid backup path: $backup_path (not a .sql file or directory)"
  return 1
}

# Attempt backup restoration with full functionality restored
echo "🔄 Checking for backups..."
backup_path=""

# Priority 1: Legacy single backup file with content validation
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

# Priority 2: Modern timestamped backups (only if no legacy backup found)
if [ -z "$backup_path" ] && [ -d "$BACKUP_DIRS" ]; then
  echo "📁 Backup directory exists, checking for timestamped backups..."
  if [ "$(ls -A $BACKUP_DIRS 2>/dev/null | wc -l)" -gt 0 ]; then
    # Check daily backups first
    if [ -d "$BACKUP_DIRS/daily" ] && [ "$(ls -A $BACKUP_DIRS/daily 2>/dev/null | wc -l)" -gt 0 ]; then
      echo "📅 Found daily backup directory, finding latest..."
      latest_daily=$(ls -1t $BACKUP_DIRS/daily 2>/dev/null | head -n 1)
      if [ -n "$latest_daily" ] && [ -d "$BACKUP_DIRS/daily/$latest_daily" ]; then
        echo "📦 Checking backup directory: $latest_daily"
        # Check if directory has .sql.gz files
        if ls "$BACKUP_DIRS/daily/$latest_daily"/*.sql.gz >/dev/null 2>&1; then
          # Validate at least one backup file has content
          echo "🔍 Validating backup content..."
          for backup_file in "$BACKUP_DIRS/daily/$latest_daily"/*.sql.gz; do
            if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
              # Use timeout to prevent hanging on zcat
              if timeout 10 zcat "$backup_file" 2>/dev/null | head -20 | grep -q "CREATE DATABASE\|INSERT INTO\|CREATE TABLE"; then
                echo "✅ Valid backup found: $(basename $backup_file)"
                backup_path="$BACKUP_DIRS/daily/$latest_daily"
                break
              fi
            fi
          done
        else
          echo "⚠️  No .sql.gz files found in backup directory"
        fi
      fi
    else
      echo "📅 No daily backup directory found"
    fi
  else
    echo "📁 Backup directory is empty"
  fi
else
  echo "📁 No backup directory found or legacy backup already selected"
fi

echo "🔄 Final backup path result: '$backup_path'"
if [ -n "$backup_path" ]; then
  echo "📦 Found backup: $(basename $backup_path)"
  if restore_from_directory "$backup_path"; then
    echo "✅ Database restoration completed successfully!"
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🚫 Skipping schema import - data already restored from backup"
    exit 0
  else
    echo "❌ Backup restoration failed - proceeding with fresh setup"
    echo "$(date): Backup restoration failed - proceeding with fresh setup" > "$RESTORE_FAILED_MARKER"
  fi
else
  echo "ℹ️  No valid backups found - proceeding with fresh setup"
  echo "$(date): No backup found - fresh setup needed" > "$RESTORE_FAILED_MARKER"
fi

# Create fresh databases if restoration didn't happen
echo "🗄️ Creating fresh AzerothCore databases..."
mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
CREATE DATABASE IF NOT EXISTS ${DB_AUTH_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ${DB_WORLD_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ${DB_CHARACTERS_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SHOW DATABASES;" || {
  echo "❌ Failed to create databases"
  exit 1
}
echo "✅ Fresh databases created - proceeding with schema import"

# Wait for databases to be ready (they should exist now)
echo "⏳ Verifying databases are accessible..."
for i in $(seq 1 10); do
  if mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "USE ${DB_AUTH_NAME}; USE ${DB_WORLD_NAME}; USE ${DB_CHARACTERS_NAME};" >/dev/null 2>&1; then
    echo "✅ All databases accessible"
    break
  fi
  echo "⏳ Waiting for databases... attempt $i/10"
  sleep 2
done

# Verify databases are actually empty before importing
echo "🔍 Verifying databases are empty before import..."
check_table_count() {
  local db_name="$1"
  local count=$(mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='$db_name' AND table_type='BASE TABLE';" -s -N 2>/dev/null || echo "0")
  echo "$count"
}

auth_tables=$(check_table_count "${DB_AUTH_NAME}")
world_tables=$(check_table_count "${DB_WORLD_NAME}")
char_tables=$(check_table_count "${DB_CHARACTERS_NAME}")

echo "📊 Current table counts:"
echo "   ${DB_AUTH_NAME}: $auth_tables tables"
echo "   ${DB_WORLD_NAME}: $world_tables tables"
echo "   ${DB_CHARACTERS_NAME}: $char_tables tables"

# Warn if databases appear to have data
if [ "$auth_tables" -gt 5 ] || [ "$world_tables" -gt 50 ] || [ "$char_tables" -gt 5 ]; then
  echo "⚠️  WARNING: Databases appear to contain data!"
  echo "⚠️  Import may overwrite existing data. Consider backing up first."
  echo "⚠️  Continuing in 10 seconds... (Ctrl+C to cancel)"
  sleep 10
fi

echo "📝 Creating dbimport configuration..."
mkdir -p /azerothcore/env/dist/etc
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
Updates.EnableDatabases = 7
Updates.AutoSetup = 1

# Required configuration properties
MySQLExecutable = ""
TempDir = ""
SourceDirectory = ""
Updates.AllowedModules = "all"
LoginDatabase.WorkerThreads = 1
LoginDatabase.SynchThreads = 1
WorldDatabase.WorkerThreads = 1
WorldDatabase.SynchThreads = 1
CharacterDatabase.WorkerThreads = 1
CharacterDatabase.SynchThreads = 1
Updates.Redundancy = 1
Updates.AllowRehash = 1
Updates.ArchivedRedundancy = 0
Updates.CleanDeadRefMaxCount = 3

# Logging configuration
Appender.Console=1,3,6
Logger.root=3,Console
EOF

echo "🚀 Running database import..."
cd /azerothcore/env/dist/bin

# Run dbimport with error handling
if ./dbimport; then
  echo "✅ Database import completed successfully!"

  # Create import completion marker
  if touch "$RESTORE_STATUS_DIR/.import-completed" 2>/dev/null; then
    echo "$(date): Database import completed successfully" > "$RESTORE_STATUS_DIR/.import-completed"
  else
    echo "$(date): Database import completed successfully" > "$MARKER_STATUS_DIR/.import-completed"
    echo "⚠️  Using temporary location for completion marker"
  fi

  # Verify import was successful
  echo "🔍 Verifying import results..."
  auth_tables_after=$(check_table_count "${DB_AUTH_NAME}")
  world_tables_after=$(check_table_count "${DB_WORLD_NAME}")
  char_tables_after=$(check_table_count "${DB_CHARACTERS_NAME}")

  echo "📊 Post-import table counts:"
  echo "   ${DB_AUTH_NAME}: $auth_tables_after tables"
  echo "   ${DB_WORLD_NAME}: $world_tables_after tables"
  echo "   ${DB_CHARACTERS_NAME}: $char_tables_after tables"

  if [ "$auth_tables_after" -gt 0 ] && [ "$world_tables_after" -gt 0 ]; then
    echo "✅ Import verification successful - databases populated"
  else
    echo "⚠️  Import verification failed - databases may be empty"
  fi
else
  echo "❌ Database import failed!"
  if touch "$RESTORE_STATUS_DIR/.import-failed" 2>/dev/null; then
    echo "$(date): Database import failed" > "$RESTORE_STATUS_DIR/.import-failed"
  else
    echo "$(date): Database import failed" > "$MARKER_STATUS_DIR/.import-failed"
    echo "⚠️  Using temporary location for failed marker"
  fi
  exit 1
fi

echo "🎉 Database import process complete!"
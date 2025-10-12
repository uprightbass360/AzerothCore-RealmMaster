#!/bin/bash
set -e

echo "🔧 Conditional AzerothCore Database Import"
echo "========================================"

# Restoration status markers
RESTORE_STATUS_DIR="/var/lib/mysql-persistent"
RESTORE_SUCCESS_MARKER="$RESTORE_STATUS_DIR/.restore-completed"
RESTORE_FAILED_MARKER="$RESTORE_STATUS_DIR/.restore-failed"

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

# Wait for databases to be ready
echo "⏳ Waiting for databases to be accessible..."
for i in $(seq 1 120); do
  if mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "USE ${DB_AUTH_NAME}; USE ${DB_WORLD_NAME}; USE ${DB_CHARACTERS_NAME};" >/dev/null 2>&1; then
    echo "✅ All databases accessible"
    break
  fi
  echo "⏳ Waiting for databases... attempt $i/120"
  sleep 5
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
  echo "$(date): Database import completed successfully" > "$RESTORE_STATUS_DIR/.import-completed"

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
  echo "$(date): Database import failed" > "$RESTORE_STATUS_DIR/.import-failed"
  exit 1
fi

echo "🎉 Database import process complete!"
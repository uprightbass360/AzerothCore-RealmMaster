#!/bin/bash
# Copy user database files from database-import/ to backup system
set -e

# Source environment variables
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

IMPORT_DIR="./database-import"
STORAGE_PATH="${STORAGE_PATH:-./storage}"
STORAGE_PATH_LOCAL="${STORAGE_PATH_LOCAL:-./local-storage}"
BACKUP_DIR="${STORAGE_PATH}/backups/daily"
TIMESTAMP=$(date +%Y-%m-%d)

# Exit if no import directory or empty
if [ ! -d "$IMPORT_DIR" ] || [ -z "$(ls -A "$IMPORT_DIR" 2>/dev/null | grep -E '\.(sql|sql\.gz)$')" ]; then
  echo "📁 No database files found in $IMPORT_DIR - skipping import"
  exit 0
fi

# Exit if backup system already has databases restored
if [ -f "${STORAGE_PATH_LOCAL}/mysql-data/.restore-completed" ]; then
  echo "✅ Database already restored - skipping import"
  exit 0
fi

echo "📥 Found database files in $IMPORT_DIR"
echo "📂 Copying to backup system for import..."

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Copy files with smart naming
for file in "$IMPORT_DIR"/*.sql "$IMPORT_DIR"/*.sql.gz; do
  [ -f "$file" ] || continue

  filename=$(basename "$file")

  # Try to detect database type by filename
  if echo "$filename" | grep -qi "auth"; then
    target_name="acore_auth_${TIMESTAMP}.sql"
  elif echo "$filename" | grep -qi "world"; then
    target_name="acore_world_${TIMESTAMP}.sql"
  elif echo "$filename" | grep -qi "char"; then
    target_name="acore_characters_${TIMESTAMP}.sql"
  else
    # Fallback - use original name with timestamp
    base_name="${filename%.*}"
    ext="${filename##*.}"
    target_name="${base_name}_${TIMESTAMP}.${ext}"
  fi

  # Add .gz extension if source is compressed
  if [[ "$filename" == *.sql.gz ]]; then
    target_name="${target_name}.gz"
  fi

  target_path="$BACKUP_DIR/$target_name"

  echo "📋 Copying $filename → $target_name"
  cp "$file" "$target_path"
done

echo "✅ Database files copied to backup system"
echo "💡 Files will be automatically imported during deployment"
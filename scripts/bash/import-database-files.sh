#!/bin/bash
# Copy user database files or full backup archives from import/db/ or database-import/ to backup system
set -euo pipefail

# Source environment variables
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

# Support both new (import/db) and legacy (database-import) directories
IMPORT_DIR_NEW="./import/db"
IMPORT_DIR_LEGACY="./database-import"

# Prefer new directory if it has files, otherwise fall back to legacy
IMPORT_DIR="$IMPORT_DIR_NEW"
if [ ! -d "$IMPORT_DIR" ] || [ -z "$(ls -A "$IMPORT_DIR" 2>/dev/null)" ]; then
  IMPORT_DIR="$IMPORT_DIR_LEGACY"
fi
STORAGE_PATH="${STORAGE_PATH:-./storage}"
STORAGE_PATH_LOCAL="${STORAGE_PATH_LOCAL:-./local-storage}"
BACKUP_ROOT="${STORAGE_PATH}/backups"
MYSQL_DATA_VOLUME_NAME="${MYSQL_DATA_VOLUME_NAME:-mysql-data}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:latest}"

shopt -s nullglob
sql_files=("$IMPORT_DIR"/*.sql "$IMPORT_DIR"/*.sql.gz)
shopt -u nullglob

if [ ! -d "$IMPORT_DIR" ] || [ ${#sql_files[@]} -eq 0 ]; then
  echo "📁 No loose database files found in $IMPORT_DIR - skipping import"
  exit 0
fi

# Exit if backup system already has databases restored
has_restore_marker(){
  # Prefer Docker volume marker (post-migration), fall back to legacy host path
  if command -v docker >/dev/null 2>&1; then
    if docker volume inspect "$MYSQL_DATA_VOLUME_NAME" >/dev/null 2>&1; then
      if docker run --rm \
          -v "${MYSQL_DATA_VOLUME_NAME}:/var/lib/mysql-persistent" \
          "$ALPINE_IMAGE" \
          sh -c 'test -f /var/lib/mysql-persistent/.restore-completed' >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  if [ -f "${STORAGE_PATH_LOCAL}/mysql-data/.restore-completed" ]; then
    return 0
  fi
  return 1
}

if has_restore_marker; then
  echo "✅ Database already restored - skipping import"
  exit 0
fi

echo "📥 Found ${#sql_files[@]} database files in $IMPORT_DIR"
echo "📂 Bundling files for backup import..."

# Ensure backup directory exists
mkdir -p "$BACKUP_ROOT"

generate_unique_path(){
  local target="$1"
  local base="$target"
  local counter=2
  while [ -e "$target" ]; do
    target="${base}_${counter}"
    counter=$((counter + 1))
  done
  printf '%s\n' "$target"
}

stage_backup_directory(){
  local src_dir="$1"
  if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
    echo "⚠️  Invalid source directory: $src_dir"
    return 1
  fi
  local dirname
  dirname="$(basename "$src_dir")"
  local dest="$BACKUP_ROOT/$dirname"
  dest="$(generate_unique_path "$dest")"
  echo "📦 Copying backup directory $(basename "$src_dir") → $(basename "$dest")"
  if ! cp -a "$src_dir" "$dest"; then
    echo "❌ Failed to copy backup directory"
    return 1
  fi
  printf '%s\n' "$dest"
}

bundle_loose_files(){
  local batch_timestamp
  batch_timestamp="$(date +%Y%m%d_%H%M%S)"
  local batch_name="ImportBackup_${batch_timestamp}"
  local batch_dir="$IMPORT_DIR/$batch_name"
  local moved=0

  batch_dir="$(generate_unique_path "$batch_dir")"
  if ! mkdir -p "$batch_dir"; then
    echo "❌ Failed to create batch directory: $batch_dir"
    exit 1
  fi

  for file in "${sql_files[@]}"; do
    [ -f "$file" ] || continue
    echo "📦 Moving $(basename "$file") → $(basename "$batch_dir")/"
    if ! mv "$file" "$batch_dir/"; then
      echo "❌ Failed to move $file"
      exit 1
    fi
    moved=$((moved + 1))
  done

  echo "🗂️  Created import batch $(basename "$batch_dir") with $moved file(s)"
  local dest_path
  dest_path="$(stage_backup_directory "$batch_dir")"
  echo "✅ Backup batch copied to $(basename "$dest_path")"
  echo "💡 Files will be automatically imported during deployment"
}

bundle_loose_files

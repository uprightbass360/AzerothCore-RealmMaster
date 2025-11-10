#!/bin/bash
# Copy user database files or full backup archives from database-import/ to backup system
set -euo pipefail

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
FULL_BACKUP_DIR="${STORAGE_PATH}/backups/ImportBackup"
TIMESTAMP=$(date +%Y-%m-%d)

shopt -s nullglob

sql_files=("$IMPORT_DIR"/*.sql "$IMPORT_DIR"/*.sql.gz)
archive_files=("$IMPORT_DIR"/*.tar "$IMPORT_DIR"/*.tar.gz "$IMPORT_DIR"/*.tgz "$IMPORT_DIR"/*.zip)

declare -a full_backup_dirs=()
for dir in "$IMPORT_DIR"/*/; do
  dir="${dir%/}"
  # Skip if no dump-like files inside
  if compgen -G "$dir"/*.sql >/dev/null || compgen -G "$dir"/*.sql.gz >/dev/null; then
    full_backup_dirs+=("$dir")
  fi
done

if [ ! -d "$IMPORT_DIR" ] || { [ ${#sql_files[@]} -eq 0 ] && [ ${#archive_files[@]} -eq 0 ] && [ ${#full_backup_dirs[@]} -eq 0 ]; }; then
  echo "📁 No database files or full backups found in $IMPORT_DIR - skipping import"
  exit 0
fi

shopt -u nullglob

# Exit if backup system already has databases restored
if [ -f "${STORAGE_PATH_LOCAL}/mysql-data/.restore-completed" ]; then
  echo "✅ Database already restored - skipping import"
  exit 0
fi

echo "📥 Found database files in $IMPORT_DIR"
echo "📂 Copying to backup system for import..."

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR" "$FULL_BACKUP_DIR"

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

copied_sql=0
staged_dirs=0
staged_archives=0

# Copy files with smart naming
for file in "${sql_files[@]:-}"; do
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
  copied_sql=$((copied_sql + 1))
done

stage_backup_directory(){
  local src_dir="$1"
  local dirname
  dirname="$(basename "$src_dir")"
  local dest="$FULL_BACKUP_DIR/$dirname"
  dest="$(generate_unique_path "$dest")"
  echo "📦 Staging full backup directory $(basename "$src_dir") → $(basename "$dest")"
  cp -a "$src_dir" "$dest"
  staged_dirs=$((staged_dirs + 1))
}

extract_archive(){
  local archive="$1"
  local base_name
  base_name="$(basename "$archive")"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local extracted=0

  cleanup_tmp(){
    rm -rf "$tmp_dir"
  }

  case "$archive" in
    *.tar.gz|*.tgz)
      if tar -xzf "$archive" -C "$tmp_dir"; then
        extracted=1
      fi
      ;;
    *.tar)
      if tar -xf "$archive" -C "$tmp_dir"; then
        extracted=1
      fi
      ;;
    *.zip)
      if ! command -v unzip >/dev/null 2>&1; then
        echo "⚠️  unzip not found; cannot extract $base_name"
      elif unzip -q "$archive" -d "$tmp_dir"; then
        extracted=1
      fi
      ;;
    *)
      echo "⚠️  Unsupported archive format for $base_name"
      ;;
  esac

  if [ "$extracted" -ne 1 ]; then
    cleanup_tmp
    return
  fi

  mapfile -d '' entries < <(find "$tmp_dir" -mindepth 1 -maxdepth 1 -print0) || true
  local dest=""
  if [ ${#entries[@]} -eq 1 ] && [ -d "${entries[0]}" ]; then
    local inner_name
    inner_name="$(basename "${entries[0]}")"
    dest="$FULL_BACKUP_DIR/$inner_name"
    dest="$(generate_unique_path "$dest")"
    mv "${entries[0]}" "$dest"
  else
    local base="${base_name%.*}"
    base="${base%.*}" # handle double extensions like .tar.gz
    dest="$(generate_unique_path "$FULL_BACKUP_DIR/$base")"
    mkdir -p "$dest"
    if [ ${#entries[@]} -gt 0 ]; then
      mv "${entries[@]}" "$dest"/
    fi
  fi
  echo "🗂️  Extracted $base_name → $(basename "$dest")"
  staged_archives=$((staged_archives + 1))
  cleanup_tmp
}

for dir in "${full_backup_dirs[@]:-}"; do
  stage_backup_directory "$dir"
done

for archive in "${archive_files[@]:-}"; do
  extract_archive "$archive"
done

if [ "$copied_sql" -gt 0 ]; then
  echo "✅ $copied_sql database file(s) copied to $BACKUP_DIR"
fi
if [ "$staged_dirs" -gt 0 ]; then
  dir_label="directories"
  [ "$staged_dirs" -eq 1 ] && dir_label="directory"
  echo "✅ $staged_dirs full backup $dir_label staged in $FULL_BACKUP_DIR"
fi
if [ "$staged_archives" -gt 0 ]; then
  archive_label="archives"
  [ "$staged_archives" -eq 1 ] && archive_label="archive"
  echo "✅ $staged_archives backup $archive_label extracted to $FULL_BACKUP_DIR"
fi

if [ "$copied_sql" -eq 0 ] && [ "$staged_dirs" -eq 0 ] && [ "$staged_archives" -eq 0 ]; then
  echo "⚠️  No valid files or backups were staged. Ensure your dumps are .sql/.sql.gz or packaged in directories/archives."
else
  echo "💡 Files will be automatically imported during deployment"
fi

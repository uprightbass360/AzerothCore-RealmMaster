#!/bin/bash
# Restore auth/characters/world databases from a backup folder.
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 <backup_dir>
  <backup_dir> should contain acore_auth.sql.gz, acore_characters.sql.gz, acore_world.sql.gz
EOF
}

if [[ $# -ne 1 ]]; then
  usage; exit 1
fi

BACKUP_DIR="$1"
MYSQL_PW="${MYSQL_ROOT_PASSWORD:-azerothcore123}"
DB_AUTH="${DB_AUTH_NAME:-acore_auth}"
DB_CHAR="${DB_CHARACTERS_NAME:-acore_characters}"
DB_WORLD="${DB_WORLD_NAME:-acore_world}"

[[ -d "$BACKUP_DIR" ]] || { echo "Backup dir not found: $BACKUP_DIR" >&2; exit 1; }

restore(){
  local db="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "Skipping $db (missing $file)"; return
  fi
  echo "Importing $file into $db"
  case "$file" in
    *.sql.gz) gzip -dc "$file" ;; 
    *.sql) cat "$file" ;;
    *) echo "Unsupported file type: $file" >&2; return ;;
  esac | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$db"
}

restore "$DB_AUTH" "$BACKUP_DIR/acore_auth.sql.gz"
restore "$DB_CHAR" "$BACKUP_DIR/acore_characters.sql.gz"
# optional world restore
if [[ -f "$BACKUP_DIR/acore_world.sql.gz" ]]; then
  echo "World dump found. Restore? [y/N]"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    restore "$DB_WORLD" "$BACKUP_DIR/acore_world.sql.gz"
  fi
fi

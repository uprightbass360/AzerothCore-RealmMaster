#!/bin/bash
# Restore auth and character databases from ImportBackup/ and verify service health.
set -euo pipefail

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

log(){ printf '%b\n' "${COLOR_GREEN}$*${COLOR_RESET}"; }
warn(){ printf '%b\n' "${COLOR_YELLOW}$*${COLOR_RESET}"; }
err(){ printf '%b\n' "${COLOR_RED}$*${COLOR_RESET}"; }

usage(){
  cat <<EOF
Usage: ./backup-import.sh [backup_dir] <mysql_password> <auth_db> <characters_db> <world_db>

Restores user accounts and characters from a backup folder.

Arguments:
  [backup_dir] Backup directory (default: ImportBackup/)
  <mysql_password> MySQL root password (required)
  <auth_db> Auth database name (required)
  <characters_db> Characters database name (required)
  <world_db> World database name (required)

Required files:
  acore_auth.sql or acore_auth.sql.gz
  acore_characters.sql or acore_characters.sql.gz
Optional file (will prompt):
  acore_world.sql or acore_world.sql.gz

Steps performed:
  1. Stop world/auth services
  2. Back up current auth/character DBs to manual-backups/
  3. Import provided dumps
  4. Re-run module SQL to restore customizations
  5. Restart services and show status summary
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

BACKUP_DIR="${1:-ImportBackup}"
MYSQL_PW="$2"
DB_AUTH="$3"
DB_CHAR="$4"
DB_WORLD="$5"

# Check if required parameters are provided
if [[ -z "$MYSQL_PW" ]]; then
  err "MySQL password required as second argument."
  exit 1
fi

if [[ -z "$DB_AUTH" ]]; then
  err "Auth database name required as third argument."
  exit 1
fi

if [[ -z "$DB_CHAR" ]]; then
  err "Characters database name required as fourth argument."
  exit 1
fi

if [[ -z "$DB_WORLD" ]]; then
  err "World database name required as fifth argument."
  exit 1
fi

require_file(){
  local file="$1"
  [[ -f "$file" ]] || { err "Missing required backup file: $file"; exit 1; }
}

if [[ ! -d "$BACKUP_DIR" ]]; then
  err "Backup directory not found: $BACKUP_DIR"
  exit 1
fi

AUTH_DUMP=$(find "$BACKUP_DIR" -maxdepth 1 -name 'acore_auth.sql*' | head -n1 || true)
CHAR_DUMP=$(find "$BACKUP_DIR" -maxdepth 1 -name 'acore_characters.sql*' | head -n1 || true)
WORLD_DUMP=$(find "$BACKUP_DIR" -maxdepth 1 -name 'acore_world.sql*' | head -n1 || true)

require_file "$AUTH_DUMP"
require_file "$CHAR_DUMP"

timestamp(){ date +%Y%m%d_%H%M%S; }

backup_db(){
  local db="$1"
  local out="manual-backups/${db}-pre-import-$(timestamp).sql"
  mkdir -p manual-backups
  log "Backing up current $db to $out"
  docker exec ac-mysql mysqldump -uroot -p"$MYSQL_PW" "$db" > "$out"
}

restore(){
  local db="$1"
  local dump="$2"
  log "Importing $dump into $db"
  case "$dump" in
    *.gz) gzip -dc "$dump" ;;
    *.sql) cat "$dump" ;;
    *) err "Unsupported dump format: $dump"; exit 1;;
  esac | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$db"
}

log "Stopping world/auth services"
docker stop ac-worldserver ac-authserver >/dev/null || warn "Services already stopped"

backup_db "$DB_AUTH"
restore "$DB_AUTH" "$AUTH_DUMP"

backup_db "$DB_CHAR"
restore "$DB_CHAR" "$CHAR_DUMP"

if [[ -n "$WORLD_DUMP" ]]; then
  read -rp "World dump detected (${WORLD_DUMP##*/}). Restore it as well? [y/N]: " ANSWER
  if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
    backup_db "$DB_WORLD"
    restore "$DB_WORLD" "$WORLD_DUMP"
  else
    warn "Skipping world database restore"
  fi
fi

log "Reapplying module SQL patches"
docker compose --profile db --profile modules run --rm \
  --entrypoint /bin/sh ac-modules \
  -c 'apk add --no-cache bash curl >/dev/null && bash /tmp/scripts/manage-modules.sh >/tmp/mm.log && cat /tmp/mm.log' || warn "Module SQL run exited with non-zero status"

log "Restarting services"
docker start ac-authserver ac-worldserver >/dev/null

sleep 5

count_rows(){
  docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e "$1"
}

ACCOUNTS=$(count_rows "SELECT COUNT(*) FROM ${DB_AUTH}.account;")
CHARS=$(count_rows "SELECT COUNT(*) FROM ${DB_CHAR}.characters;")

log "Accounts: $ACCOUNTS"
log "Characters: $CHARS"

./status.sh --once || warn "status.sh reported issues; inspect manually."

log "Import completed."

#!/bin/bash
# Restore auth and character databases from ImportBackup/ and verify service health.
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Change to the script directory to ensure relative paths work correctly
cd "$SCRIPT_DIR"

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
  5. Restart services to reinitialize GUID generators
  6. Show status summary

Note: Service restart is required to ensure character GUID generators
are properly updated after importing characters.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

# Check if required parameters are provided (minimum 4: password, auth_db, char_db, world_db)
if [[ $# -lt 4 ]]; then
  err "Required parameters missing. Usage: ./backup-import.sh [backup_dir] <mysql_password> <auth_db> <characters_db> <world_db>"
  exit 1
fi

# Handle both cases: with and without backup_dir parameter
if [[ $# -eq 4 ]]; then
  # No backup_dir provided, use default
  BACKUP_DIR="ImportBackup"
  MYSQL_PW="$1"
  DB_AUTH="$2"
  DB_CHAR="$3"
  DB_WORLD="$4"
elif [[ $# -ge 5 ]]; then
  # backup_dir provided - convert to absolute path if relative
  BACKUP_DIR="$1"
  MYSQL_PW="$2"
  DB_AUTH="$3"
  DB_CHAR="$4"
  DB_WORLD="$5"
fi

# Convert backup directory to absolute path if it's relative
if [[ ! "$BACKUP_DIR" = /* ]]; then
  BACKUP_DIR="$SCRIPT_DIR/$BACKUP_DIR"
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

log "Restarting services to reinitialize GUID generators"
docker restart ac-authserver ac-worldserver >/dev/null

log "Waiting for services to fully initialize..."
sleep 10

# Wait for services to be healthy
for i in {1..30}; do
  if docker exec ac-worldserver pgrep worldserver >/dev/null 2>&1 && docker exec ac-authserver pgrep authserver >/dev/null 2>&1; then
    log "Services are running"
    break
  fi
  if [ $i -eq 30 ]; then
    warn "Services took longer than expected to start"
  fi
  sleep 2
done

count_rows(){
  docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e "$1"
}

ACCOUNTS=$(count_rows "SELECT COUNT(*) FROM ${DB_AUTH}.account;")
CHARS=$(count_rows "SELECT COUNT(*) FROM ${DB_CHAR}.characters;")
MAX_GUID=$(count_rows "SELECT COALESCE(MAX(guid), 0) FROM ${DB_CHAR}.characters;")

log "Accounts: $ACCOUNTS"
log "Characters: $CHARS"
if [ "$CHARS" -gt 0 ]; then
  log "Highest character GUID: $MAX_GUID"
  log "Next new character will receive GUID: $((MAX_GUID + 1))"
fi

./status.sh --once || warn "status.sh reported issues; inspect manually."

log "Import completed."

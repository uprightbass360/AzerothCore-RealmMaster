#!/bin/bash
# Fix item import for backup-merged characters
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

log(){ printf '%b\n' "${COLOR_GREEN}$*${COLOR_RESET}"; }
info(){ printf '%b\n' "${COLOR_CYAN}$*${COLOR_RESET}"; }
warn(){ printf '%b\n' "${COLOR_YELLOW}$*${COLOR_RESET}"; }
err(){ printf '%b\n' "${COLOR_RED}$*${COLOR_RESET}"; }
fatal(){ err "$*"; exit 1; }

MYSQL_PW="azerothcore123"
BACKUP_DIR="/nfs/containers/ac-backup"
AUTH_DB="acore_auth"
CHARACTERS_DB="acore_characters"

# Verify parameters
[[ -d "$BACKUP_DIR" ]] || fatal "Backup directory not found: $BACKUP_DIR"

# Setup temp directory
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# MySQL connection helper
mysql_exec(){
  local db="$1"
  docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$db" 2>/dev/null
}

mysql_query(){
  local db="$1"
  local query="$2"
  docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B "$db" -e "$query" 2>/dev/null
}

log "═══════════════════════════════════════════════════════════"
log "  FIXING ITEM IMPORT FOR BACKUP-MERGED CHARACTERS"
log "═══════════════════════════════════════════════════════════"

# Find characters that were imported from the backup (accounts 451, 452)
log "Finding characters that need item restoration..."
IMPORTED_CHARS=$(mysql_query "$CHARACTERS_DB" "SELECT name, guid FROM characters WHERE account IN (451, 452);")

if [[ -z "$IMPORTED_CHARS" ]]; then
  fatal "No imported characters found (accounts 451, 452)"
fi

info "Found imported characters:"
echo "$IMPORTED_CHARS" | while read -r char_name char_guid; do
  info "  $char_name (guid: $char_guid)"
done

# Check current item count for these characters
CURRENT_ITEM_COUNT=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM item_instance WHERE owner_guid IN (4501, 4502, 4503);")
info "Current items for imported characters: $CURRENT_ITEM_COUNT"

if [[ "$CURRENT_ITEM_COUNT" != "0" ]]; then
  warn "Characters already have items. Exiting."
  exit 0
fi

# Extract backup files
log "Extracting backup files..."
CHARACTERS_DUMP=""
for pattern in "acore_characters.sql.gz" "characters.sql.gz" "acore_characters.sql" "characters.sql"; do
  if [[ -f "$BACKUP_DIR/$pattern" ]]; then
    CHARACTERS_DUMP="$BACKUP_DIR/$pattern"
    break
  fi
done

[[ -n "$CHARACTERS_DUMP" ]] || fatal "Characters database dump not found in $BACKUP_DIR"

info "Found characters dump: ${CHARACTERS_DUMP##*/}"

# Extract dump to temp file
if [[ "$CHARACTERS_DUMP" == *.gz ]]; then
  zcat "$CHARACTERS_DUMP" > "$TEMP_DIR/characters.sql"
else
  cp "$CHARACTERS_DUMP" "$TEMP_DIR/characters.sql"
fi

# Create staging database
log "Creating staging database..."
STAGE_CHARS_DB="fix_stage_chars_$$"

# Drop any existing staging database
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true

# Create staging database
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "CREATE DATABASE $STAGE_CHARS_DB;" 2>/dev/null

# Cleanup staging database on exit
cleanup_staging(){
  if [[ -n "${STAGE_CHARS_DB:-}" ]]; then
    docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true
  fi
}
trap 'cleanup_staging; rm -rf "$TEMP_DIR"' EXIT

# Load backup into staging database
info "Loading backup into staging database..."
sed "s/\`acore_characters\`/\`$STAGE_CHARS_DB\`/g; s/USE \`acore_characters\`;/USE \`$STAGE_CHARS_DB\`;/g" "$TEMP_DIR/characters.sql" | \
  docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" 2>/dev/null

# Get current database state
CURRENT_MAX_ITEM_GUID=$(mysql_query "$CHARACTERS_DB" "SELECT COALESCE(MAX(guid), 0) FROM item_instance;")
ITEM_OFFSET=$((CURRENT_MAX_ITEM_GUID + 10000))

info "Current max item GUID: $CURRENT_MAX_ITEM_GUID"
info "Item GUID offset: +$ITEM_OFFSET"

# Create character mapping for the imported characters
log "Creating character mapping..."
mysql_exec "$STAGE_CHARS_DB" <<EOF
CREATE TABLE character_guid_map (
  old_guid INT UNSIGNED PRIMARY KEY,
  new_guid INT UNSIGNED,
  name VARCHAR(12)
);

INSERT INTO character_guid_map (old_guid, new_guid, name)
VALUES
  (1, 4501, 'Artimage'),
  (2, 4502, 'Flombey'),
  (3, 4503, 'Hammertime');
EOF

# Create item GUID mapping
mysql_exec "$STAGE_CHARS_DB" <<EOF
CREATE TABLE item_guid_map (
  old_guid INT UNSIGNED PRIMARY KEY,
  new_guid INT UNSIGNED,
  owner_guid INT UNSIGNED
);

INSERT INTO item_guid_map (old_guid, new_guid, owner_guid)
SELECT
  i.guid,
  i.guid + $ITEM_OFFSET,
  i.owner_guid
FROM item_instance i
INNER JOIN character_guid_map cm ON i.owner_guid = cm.old_guid;
EOF

# Check how many items will be imported
ITEMS_TO_IMPORT=$(mysql_query "$STAGE_CHARS_DB" "SELECT COUNT(*) FROM item_guid_map;")
info "Items to import: $ITEMS_TO_IMPORT"

if [[ "$ITEMS_TO_IMPORT" == "0" ]]; then
  warn "No items found for the imported characters in backup"
  exit 0
fi

# Stop services
log "Stopping world/auth services..."
docker stop ac-worldserver ac-authserver >/dev/null 2>&1 || warn "Services already stopped"

# Import items
log "Importing character items..."

# Import item_instance
ITEM_SQL=$(cat <<EOSQL
INSERT INTO item_instance (guid, itemEntry, owner_guid, creatorGuid, giftCreatorGuid, count,
                            duration, charges, flags, enchantments, randomPropertyId, durability,
                            playedTime, text)
SELECT
  im.new_guid,
  ii.itemEntry,
  cm.new_guid,
  ii.creatorGuid,
  ii.giftCreatorGuid,
  ii.count,
  ii.duration,
  ii.charges,
  ii.flags,
  ii.enchantments,
  ii.randomPropertyId,
  ii.durability,
  ii.playedTime,
  ii.text
FROM $STAGE_CHARS_DB.item_instance ii
INNER JOIN $STAGE_CHARS_DB.item_guid_map im ON ii.guid = im.old_guid
INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON ii.owner_guid = cm.old_guid;
EOSQL
)

ITEM_SQL_EXPANDED=$(echo "$ITEM_SQL" | sed "s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g")
ITEM_RESULT=$(echo "$ITEM_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1)
if echo "$ITEM_RESULT" | grep -q "ERROR"; then
  err "Item import failed:"
  echo "$ITEM_RESULT" | grep "ERROR" >&2
  fatal "Item import failed"
fi

# Import character_inventory
INV_SQL=$(cat <<EOSQL
INSERT INTO character_inventory (guid, bag, slot, item)
SELECT
  cm.new_guid,
  ci.bag,
  ci.slot,
  im.new_guid
FROM $STAGE_CHARS_DB.character_inventory ci
INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON ci.guid = cm.old_guid
INNER JOIN $STAGE_CHARS_DB.item_guid_map im ON ci.item = im.old_guid;
EOSQL
)

INV_SQL_EXPANDED=$(echo "$INV_SQL" | sed "s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g")
INV_RESULT=$(echo "$INV_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1)
if echo "$INV_RESULT" | grep -q "ERROR"; then
  err "Inventory import failed:"
  echo "$INV_RESULT" | grep "ERROR" >&2
  fatal "Inventory import failed"
fi

# Report counts
ITEMS_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM item_instance WHERE owner_guid IN (4501, 4502, 4503);")
INV_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM character_inventory WHERE guid IN (4501, 4502, 4503);")

info "Items imported: $ITEMS_IMPORTED"
info "Inventory slots imported: $INV_IMPORTED"

# Restart services
log "Restarting services..."
docker restart ac-authserver ac-worldserver >/dev/null 2>&1

log "Waiting for services to initialize..."
sleep 5

for i in {1..30}; do
  if docker exec ac-worldserver pgrep worldserver >/dev/null 2>&1 && docker exec ac-authserver pgrep authserver >/dev/null 2>&1; then
    log "✓ Services running"
    break
  fi
  if [ $i -eq 30 ]; then
    warn "Services took longer than expected to start"
  fi
  sleep 2
done

log ""
log "═══════════════════════════════════════════════════════════"
log "  ITEM IMPORT FIX COMPLETE"
log "═══════════════════════════════════════════════════════════"
log "Items successfully restored for imported characters!"
log "Players can now log in with their complete characters and items."
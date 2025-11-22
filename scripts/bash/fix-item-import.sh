#!/bin/bash
# Fix item import for backup-merged characters
#
# Usage:
#   fix-item-import.sh [OPTIONS]
#
# Options:
#   --backup-dir DIR       Path to backup directory (required)
#   --account-ids IDS      Comma-separated account IDs (e.g., "451,452")
#   --char-guids GUIDS     Comma-separated character GUIDs (e.g., "4501,4502,4503")
#   --mysql-password PW    MySQL root password (or use MYSQL_ROOT_PASSWORD env var)
#   --mysql-container NAME MySQL container name (default: ac-mysql)
#   --auth-db NAME         Auth database name (default: acore_auth)
#   --characters-db NAME   Characters database name (default: acore_characters)
#   -h, --help            Show this help message
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common library
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  source "$SCRIPT_DIR/lib/common.sh"
else
  echo "ERROR: Common library not found at $SCRIPT_DIR/lib/common.sh" >&2
  exit 1
fi

# Default values (can be overridden by environment or command line)
BACKUP_DIR="${BACKUP_DIR:-}"
ACCOUNT_IDS="${ACCOUNT_IDS:-}"
CHAR_GUIDS="${CHAR_GUIDS:-}"
MYSQL_PW="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-ac-mysql}"
AUTH_DB="${AUTH_DB:-acore_auth}"
CHARACTERS_DB="${CHARACTERS_DB:-acore_characters}"

# Show help message
show_help() {
  cat << EOF
Fix item import for backup-merged characters

Usage:
  fix-item-import.sh [OPTIONS]

Options:
  --backup-dir DIR       Path to backup directory (required)
  --account-ids IDS      Comma-separated account IDs (e.g., "451,452")
  --char-guids GUIDS     Comma-separated character GUIDs (e.g., "4501,4502,4503")
  --mysql-password PW    MySQL root password (or use MYSQL_ROOT_PASSWORD env var)
  --mysql-container NAME MySQL container name (default: ac-mysql)
  --auth-db NAME         Auth database name (default: acore_auth)
  --characters-db NAME   Characters database name (default: acore_characters)
  -h, --help            Show this help message

Environment Variables:
  BACKUP_DIR             Alternative to --backup-dir
  ACCOUNT_IDS            Alternative to --account-ids
  CHAR_GUIDS             Alternative to --char-guids
  MYSQL_ROOT_PASSWORD    Alternative to --mysql-password
  MYSQL_CONTAINER        Alternative to --mysql-container
  AUTH_DB                Alternative to --auth-db
  CHARACTERS_DB          Alternative to --characters-db

Example:
  fix-item-import.sh \\
    --backup-dir /path/to/backup \\
    --account-ids "451,452" \\
    --char-guids "4501,4502,4503" \\
    --mysql-password "azerothcore123"

EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --account-ids)
      ACCOUNT_IDS="$2"
      shift 2
      ;;
    --char-guids)
      CHAR_GUIDS="$2"
      shift 2
      ;;
    --mysql-password)
      MYSQL_PW="$2"
      shift 2
      ;;
    --mysql-container)
      MYSQL_CONTAINER="$2"
      shift 2
      ;;
    --auth-db)
      AUTH_DB="$2"
      shift 2
      ;;
    --characters-db)
      CHARACTERS_DB="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      fatal "Unknown option: $1\nUse --help for usage information"
      ;;
  esac
done

# Validate required parameters
if [ -z "$BACKUP_DIR" ]; then
  fatal "Backup directory not specified. Use --backup-dir or set BACKUP_DIR environment variable."
fi

if [ ! -d "$BACKUP_DIR" ]; then
  fatal "Backup directory not found: $BACKUP_DIR"
fi

if [ -z "$ACCOUNT_IDS" ]; then
  fatal "Account IDs not specified. Use --account-ids or set ACCOUNT_IDS environment variable."
fi

if [ -z "$CHAR_GUIDS" ]; then
  fatal "Character GUIDs not specified. Use --char-guids or set CHAR_GUIDS environment variable."
fi

if [ -z "$MYSQL_PW" ]; then
  fatal "MySQL password not specified. Use --mysql-password or set MYSQL_ROOT_PASSWORD environment variable."
fi

# Setup temp directory
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# MySQL connection helpers (override common.sh defaults with script-specific values)
mysql_exec_local(){
  local db="$1"
  docker exec -i "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" "$db" 2>/dev/null
}

mysql_query_local(){
  local db="$1"
  local query="$2"
  docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" -N -B "$db" -e "$query" 2>/dev/null
}

log "═══════════════════════════════════════════════════════════"
log "  FIXING ITEM IMPORT FOR BACKUP-MERGED CHARACTERS"
log "═══════════════════════════════════════════════════════════"

# Find characters that were imported from the backup
log "Finding characters that need item restoration..."
info "Looking for characters with account IDs: $ACCOUNT_IDS"
IMPORTED_CHARS=$(mysql_query_local "$CHARACTERS_DB" "SELECT name, guid FROM characters WHERE account IN ($ACCOUNT_IDS);")

if [[ -z "$IMPORTED_CHARS" ]]; then
  fatal "No imported characters found with account IDs: $ACCOUNT_IDS"
fi

info "Found imported characters:"
echo "$IMPORTED_CHARS" | while read -r char_name char_guid; do
  info "  $char_name (guid: $char_guid)"
done

# Check current item count for these characters
info "Checking existing items for character GUIDs: $CHAR_GUIDS"
CURRENT_ITEM_COUNT=$(mysql_query_local "$CHARACTERS_DB" "SELECT COUNT(*) FROM item_instance WHERE owner_guid IN ($CHAR_GUIDS);")
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
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true

# Create staging database
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" -e "CREATE DATABASE $STAGE_CHARS_DB;" 2>/dev/null

# Cleanup staging database on exit
cleanup_staging(){
  if [[ -n "${STAGE_CHARS_DB:-}" ]]; then
    docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true
  fi
}
trap 'cleanup_staging; rm -rf "$TEMP_DIR"' EXIT

# Load backup into staging database
info "Loading backup into staging database..."
sed "s/\`$CHARACTERS_DB\`/\`$STAGE_CHARS_DB\`/g; s/USE \`$CHARACTERS_DB\`;/USE \`$STAGE_CHARS_DB\`;/g" "$TEMP_DIR/characters.sql" | \
  docker exec -i "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" 2>/dev/null

# Get current database state
CURRENT_MAX_ITEM_GUID=$(mysql_query_local "$CHARACTERS_DB" "SELECT COALESCE(MAX(guid), 0) FROM item_instance;")
ITEM_OFFSET=$((CURRENT_MAX_ITEM_GUID + 10000))

info "Current max item GUID: $CURRENT_MAX_ITEM_GUID"
info "Item GUID offset: +$ITEM_OFFSET"

# Create character mapping for the imported characters
log "Creating character mapping..."
info "Building character GUID mapping from staging database..."

# Create mapping table dynamically based on imported characters
mysql_exec_local "$STAGE_CHARS_DB" <<EOF
CREATE TABLE character_guid_map (
  old_guid INT UNSIGNED PRIMARY KEY,
  new_guid INT UNSIGNED,
  name VARCHAR(12)
);
EOF

# Populate mapping by matching character names from staging to current database
# This assumes character names are unique identifiers
mysql_exec_local "$STAGE_CHARS_DB" <<EOF
INSERT INTO character_guid_map (old_guid, new_guid, name)
SELECT
  s.guid as old_guid,
  c.guid as new_guid,
  c.name
FROM $STAGE_CHARS_DB.characters s
JOIN $CHARACTERS_DB.characters c ON s.name = c.name
WHERE c.account IN ($ACCOUNT_IDS);
EOF

# Create item GUID mapping
mysql_exec_local "$STAGE_CHARS_DB" <<EOF
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
ITEMS_TO_IMPORT=$(mysql_query_local "$STAGE_CHARS_DB" "SELECT COUNT(*) FROM item_guid_map;")
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
ITEM_RESULT=$(echo "$ITEM_SQL_EXPANDED" | docker exec -i "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1)
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
INV_RESULT=$(echo "$INV_SQL_EXPANDED" | docker exec -i "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1)
if echo "$INV_RESULT" | grep -q "ERROR"; then
  err "Inventory import failed:"
  echo "$INV_RESULT" | grep "ERROR" >&2
  fatal "Inventory import failed"
fi

# Report counts
ITEMS_IMPORTED=$(mysql_query_local "$CHARACTERS_DB" "SELECT COUNT(*) FROM item_instance WHERE owner_guid IN ($CHAR_GUIDS);")
INV_IMPORTED=$(mysql_query_local "$CHARACTERS_DB" "SELECT COUNT(*) FROM character_inventory WHERE guid IN ($CHAR_GUIDS);")

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
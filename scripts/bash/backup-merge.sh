#!/bin/bash
# Merge accounts and characters from a backup into an existing ACore database
# This script handles ID remapping to avoid conflicts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/common.sh"

MYSQL_PW=""
BACKUP_DIR=""
AUTH_DB="acore_auth"
CHARACTERS_DB="acore_characters"
DRY_RUN=false
AUTO_CONFIRM=false
IMPORT_ACCOUNTS=()
IMPORT_CHARACTERS=()
IMPORT_ALL_ACCOUNTS=false
IMPORT_ALL_CHARACTERS=false
SKIP_CONFLICTS=false
EXCLUDE_BOTS=false
TEMP_DIR=""
MERGE_LOG=""

usage(){
  cat <<'EOF'
Usage: ./backup-merge.sh [options]

Merges accounts and characters from a backup into the current database.
Automatically handles ID remapping to avoid conflicts.

Options:
  -b, --backup-dir DIR         Backup directory containing SQL dumps (required)
  -p, --password PASS          MySQL root password (required)
      --auth-db NAME           Auth database name (default: acore_auth)
      --characters-db NAME     Characters database name (default: acore_characters)
      --account USERNAME       Import specific account by username (repeatable)
      --character NAME         Import specific character by name (repeatable)
      --all-accounts           Import all accounts from backup
      --all-characters         Import all characters from backup
      --skip-conflicts         Skip accounts/characters that already exist
      --exclude-bots           Exclude bot accounts/characters (RNDBOT*, playerbots)
      --dry-run                Show what would be imported without making changes
      --yes                    Skip confirmation prompt
  -h, --help                   Show this help and exit

Examples:
  # Dry-run to see what would be imported
  ./backup-merge.sh --backup-dir ../ac-backup --password azerothcore123 --all-accounts --all-characters --dry-run

  # Import all accounts and characters, excluding bots
  ./backup-merge.sh --backup-dir ../ac-backup --password azerothcore123 --all-accounts --all-characters --exclude-bots

  # Import specific accounts
  ./backup-merge.sh --backup-dir ../ac-backup --password azerothcore123 --account ARTIMAGE --account HAMSAMMY

  # Import specific character (imports its account too)
  ./backup-merge.sh --backup-dir ../ac-backup --password azerothcore123 --character Artimage

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--backup-dir)
      [[ $# -ge 2 ]] || fatal "--backup-dir requires a value"
      BACKUP_DIR="$2"
      shift 2
      ;;
    -p|--password)
      [[ $# -ge 2 ]] || fatal "--password requires a value"
      MYSQL_PW="$2"
      shift 2
      ;;
    --auth-db)
      [[ $# -ge 2 ]] || fatal "--auth-db requires a value"
      AUTH_DB="$2"
      shift 2
      ;;
    --characters-db)
      [[ $# -ge 2 ]] || fatal "--characters-db requires a value"
      CHARACTERS_DB="$2"
      shift 2
      ;;
    --account)
      [[ $# -ge 2 ]] || fatal "--account requires a value"
      IMPORT_ACCOUNTS+=("$2")
      shift 2
      ;;
    --character)
      [[ $# -ge 2 ]] || fatal "--character requires a value"
      IMPORT_CHARACTERS+=("$2")
      shift 2
      ;;
    --all-accounts)
      IMPORT_ALL_ACCOUNTS=true
      shift
      ;;
    --all-characters)
      IMPORT_ALL_CHARACTERS=true
      shift
      ;;
    --skip-conflicts)
      SKIP_CONFLICTS=true
      shift
      ;;
    --exclude-bots)
      EXCLUDE_BOTS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      AUTO_CONFIRM=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fatal "Unknown option: $1"
      ;;
  esac
done

# Validation
[[ -n "$BACKUP_DIR" ]] || fatal "Backup directory is required (use --backup-dir)"
[[ -d "$BACKUP_DIR" ]] || fatal "Backup directory not found: $BACKUP_DIR"
[[ -n "$MYSQL_PW" ]] || fatal "MySQL password is required (use --password)"

if [[ ${#IMPORT_ACCOUNTS[@]} -eq 0 ]] && [[ ${#IMPORT_CHARACTERS[@]} -eq 0 ]] && ! $IMPORT_ALL_ACCOUNTS && ! $IMPORT_ALL_CHARACTERS; then
  fatal "Must specify what to import: --account, --character, --all-accounts, or --all-characters"
fi

# Setup temp directory
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

MERGE_LOG="$TEMP_DIR/merge.log"
touch "$MERGE_LOG"

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

# Extract SQL dumps
log "Extracting backup files..."

AUTH_DUMP=""
CHARACTERS_DUMP=""

# Find auth dump
for pattern in "acore_auth.sql.gz" "auth.sql.gz" "acore_auth.sql" "auth.sql"; do
  if [[ -f "$BACKUP_DIR/$pattern" ]]; then
    AUTH_DUMP="$BACKUP_DIR/$pattern"
    break
  fi
done

# Find characters dump
for pattern in "acore_characters.sql.gz" "characters.sql.gz" "acore_characters.sql" "characters.sql"; do
  if [[ -f "$BACKUP_DIR/$pattern" ]]; then
    CHARACTERS_DUMP="$BACKUP_DIR/$pattern"
    break
  fi
done

[[ -n "$AUTH_DUMP" ]] || fatal "Auth database dump not found in $BACKUP_DIR"
[[ -n "$CHARACTERS_DUMP" ]] || fatal "Characters database dump not found in $BACKUP_DIR"

log "Found auth dump: ${AUTH_DUMP##*/}"
log "Found characters dump: ${CHARACTERS_DUMP##*/}"

# Extract dumps to temp files
info "Decompressing backup files..."
if [[ "$AUTH_DUMP" == *.gz ]]; then
  zcat "$AUTH_DUMP" > "$TEMP_DIR/auth.sql"
else
  cp "$AUTH_DUMP" "$TEMP_DIR/auth.sql"
fi

if [[ "$CHARACTERS_DUMP" == *.gz ]]; then
  zcat "$CHARACTERS_DUMP" > "$TEMP_DIR/characters.sql"
else
  cp "$CHARACTERS_DUMP" "$TEMP_DIR/characters.sql"
fi

# Load backup data into temp database
log "Creating temporary staging database..."

STAGE_AUTH_DB="merge_stage_auth_$$"
STAGE_CHARS_DB="merge_stage_chars_$$"

# Drop any existing staging databases
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_AUTH_DB;" 2>/dev/null || true
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true

# Create staging databases
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "CREATE DATABASE $STAGE_AUTH_DB;" 2>/dev/null
docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "CREATE DATABASE $STAGE_CHARS_DB;" 2>/dev/null

# Cleanup staging databases on exit
cleanup_staging(){
  if [[ -n "${STAGE_AUTH_DB:-}" ]]; then
    docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_AUTH_DB;" 2>/dev/null || true
  fi
  if [[ -n "${STAGE_CHARS_DB:-}" ]]; then
    docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "DROP DATABASE IF EXISTS $STAGE_CHARS_DB;" 2>/dev/null || true
  fi
}
trap 'cleanup_staging; rm -rf "$TEMP_DIR"' EXIT

info "Loading backup into staging database..."

# Modify SQL to use staging database names
sed "s/\`acore_auth\`/\`$STAGE_AUTH_DB\`/g; s/USE \`acore_auth\`;/USE \`$STAGE_AUTH_DB\`;/g" "$TEMP_DIR/auth.sql" | \
  docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" 2>/dev/null

sed "s/\`acore_characters\`/\`$STAGE_CHARS_DB\`/g; s/USE \`acore_characters\`;/USE \`$STAGE_CHARS_DB\`;/g" "$TEMP_DIR/characters.sql" | \
  docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" 2>/dev/null

log "Backup loaded into staging databases"

# Analysis phase
info ""
info "═══════════════════════════════════════════════════════════"
info "  ANALYSIS PHASE"
info "═══════════════════════════════════════════════════════════"

# Get current database state
CURRENT_MAX_ACCOUNT_ID=$(mysql_query "$AUTH_DB" "SELECT COALESCE(MAX(id), 0) FROM account;")
CURRENT_MAX_CHAR_GUID=$(mysql_query "$CHARACTERS_DB" "SELECT COALESCE(MAX(guid), 0) FROM characters;")
CURRENT_MAX_ITEM_GUID=$(mysql_query "$CHARACTERS_DB" "SELECT COALESCE(MAX(guid), 0) FROM item_instance;")

info "Current database state:"
info "  Max account ID: $CURRENT_MAX_ACCOUNT_ID"
info "  Max character GUID: $CURRENT_MAX_CHAR_GUID"
info "  Max item GUID: $CURRENT_MAX_ITEM_GUID"

# Get backup database state
BACKUP_ACCOUNT_COUNT=$(mysql_query "$STAGE_AUTH_DB" "SELECT COUNT(*) FROM account;")
BACKUP_CHAR_COUNT=$(mysql_query "$STAGE_CHARS_DB" "SELECT COUNT(*) FROM characters;")

info ""
info "Backup contains:"
info "  Accounts: $BACKUP_ACCOUNT_COUNT"
info "  Characters: $BACKUP_CHAR_COUNT"

# Build list of accounts to import
info ""
info "Building import list..."

if $IMPORT_ALL_ACCOUNTS; then
  if $EXCLUDE_BOTS; then
    # Exclude bot accounts (RNDBOT%, bot%, etc.)
    mysql_query "$STAGE_AUTH_DB" "
      SELECT username FROM account
      WHERE username NOT LIKE 'RNDBOT%'
        AND username NOT LIKE 'bot%'
        AND username NOT LIKE 'BOT%'
    " > "$TEMP_DIR/accounts_to_import.txt"
  else
    mysql_query "$STAGE_AUTH_DB" "SELECT username FROM account;" > "$TEMP_DIR/accounts_to_import.txt"
  fi
else
  > "$TEMP_DIR/accounts_to_import.txt"
  for username in "${IMPORT_ACCOUNTS[@]}"; do
    echo "$username" >> "$TEMP_DIR/accounts_to_import.txt"
  done
fi

# Build list of characters to import
if $IMPORT_ALL_CHARACTERS; then
  if $EXCLUDE_BOTS; then
    # Check if playerbots DB exists in backup
    PLAYERBOTS_DB_EXISTS=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "SHOW DATABASES LIKE 'merge_stage_playerbots_%';" 2>/dev/null | wc -l)

    if [[ $PLAYERBOTS_DB_EXISTS -gt 1 ]]; then
      # Exclude characters linked to playerbots_random_bots table
      STAGE_PLAYERBOTS_DB=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -e "SHOW DATABASES LIKE 'merge_stage_playerbots_%';" 2>/dev/null | tail -1)
      mysql_query "$STAGE_CHARS_DB" "
        SELECT c.name
        FROM characters c
        INNER JOIN account a ON c.account = a.id
        LEFT JOIN $STAGE_PLAYERBOTS_DB.playerbots_random_bots pb ON c.guid = pb.bot
        WHERE pb.bot IS NULL
          AND a.username NOT LIKE 'RNDBOT%'
          AND a.username NOT LIKE 'bot%'
          AND a.username NOT LIKE 'BOT%'
      " > "$TEMP_DIR/characters_to_import.txt" 2>/dev/null || {
        # Fallback if playerbots DB structure is different
        mysql_query "$STAGE_CHARS_DB" "
          SELECT c.name
          FROM characters c
          INNER JOIN $STAGE_AUTH_DB.account a ON c.account = a.id
          WHERE a.username NOT LIKE 'RNDBOT%'
            AND a.username NOT LIKE 'bot%'
            AND a.username NOT LIKE 'BOT%'
        " > "$TEMP_DIR/characters_to_import.txt"
      }
    else
      # No playerbots DB, just exclude characters from bot accounts
      mysql_query "$STAGE_CHARS_DB" "
        SELECT c.name
        FROM characters c
        INNER JOIN $STAGE_AUTH_DB.account a ON c.account = a.id
        WHERE a.username NOT LIKE 'RNDBOT%'
          AND a.username NOT LIKE 'bot%'
          AND a.username NOT LIKE 'BOT%'
      " > "$TEMP_DIR/characters_to_import.txt"
    fi
  else
    mysql_query "$STAGE_CHARS_DB" "SELECT name FROM characters;" > "$TEMP_DIR/characters_to_import.txt"
  fi
else
  > "$TEMP_DIR/characters_to_import.txt"
  for charname in "${IMPORT_CHARACTERS[@]}"; do
    echo "$charname" >> "$TEMP_DIR/characters_to_import.txt"
  done
fi

# If importing specific characters, also import their accounts
if [[ -s "$TEMP_DIR/characters_to_import.txt" ]] && ! $IMPORT_ALL_ACCOUNTS; then
  while IFS= read -r charname; do
    account_id=$(mysql_query "$STAGE_CHARS_DB" "SELECT account FROM characters WHERE name='$charname';" || echo "")
    if [[ -n "$account_id" ]]; then
      username=$(mysql_query "$STAGE_AUTH_DB" "SELECT username FROM account WHERE id=$account_id;" || echo "")
      if [[ -n "$username" ]]; then
        echo "$username" >> "$TEMP_DIR/accounts_to_import.txt"
      fi
    fi
  done < "$TEMP_DIR/characters_to_import.txt"

  # Remove duplicates
  sort -u "$TEMP_DIR/accounts_to_import.txt" -o "$TEMP_DIR/accounts_to_import.txt"
fi

ACCOUNTS_TO_IMPORT=$(wc -l < "$TEMP_DIR/accounts_to_import.txt" | tr -d ' ')
CHARACTERS_TO_IMPORT=$(wc -l < "$TEMP_DIR/characters_to_import.txt" | tr -d ' ')

if $EXCLUDE_BOTS; then
  BOT_ACCOUNTS_EXCLUDED=$((BACKUP_ACCOUNT_COUNT - ACCOUNTS_TO_IMPORT))
  BOT_CHARS_EXCLUDED=$((BACKUP_CHAR_COUNT - CHARACTERS_TO_IMPORT))
  info ""
  info "Bot filtering enabled:"
  info "  Bot accounts excluded: $BOT_ACCOUNTS_EXCLUDED"
  info "  Bot characters excluded: $BOT_CHARS_EXCLUDED"
fi

info ""
info "Accounts to import: $ACCOUNTS_TO_IMPORT"
info "Characters to import: $CHARACTERS_TO_IMPORT"

if [[ $ACCOUNTS_TO_IMPORT -eq 0 ]] && [[ $CHARACTERS_TO_IMPORT -eq 0 ]]; then
  fatal "No accounts or characters selected for import"
fi

# Conflict detection
info ""
info "Checking for conflicts..."

ACCOUNT_CONFLICTS=0
CHARACTER_CONFLICTS=0

# Check account username conflicts
> "$TEMP_DIR/account_conflicts.txt"
while IFS= read -r username; do
  existing=$(mysql_query "$AUTH_DB" "SELECT COUNT(*) FROM account WHERE username='$username';" || echo "0")
  if [[ "$existing" != "0" ]]; then
    echo "$username" >> "$TEMP_DIR/account_conflicts.txt"
    ((ACCOUNT_CONFLICTS++)) || true
  fi
done < "$TEMP_DIR/accounts_to_import.txt"

# Check character name conflicts
> "$TEMP_DIR/character_conflicts.txt"
while IFS= read -r charname; do
  existing=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM characters WHERE name='$charname';" || echo "0")
  if [[ "$existing" != "0" ]]; then
    echo "$charname" >> "$TEMP_DIR/character_conflicts.txt"
    ((CHARACTER_CONFLICTS++)) || true
  fi
done < "$TEMP_DIR/characters_to_import.txt"

if [[ $ACCOUNT_CONFLICTS -gt 0 ]] || [[ $CHARACTER_CONFLICTS -gt 0 ]]; then
  warn "Found conflicts:"
  if [[ $ACCOUNT_CONFLICTS -gt 0 ]]; then
    warn "  $ACCOUNT_CONFLICTS account username(s) already exist:"
    while IFS= read -r username; do
      warn "    - $username"
    done < "$TEMP_DIR/account_conflicts.txt"
  fi
  if [[ $CHARACTER_CONFLICTS -gt 0 ]]; then
    warn "  $CHARACTER_CONFLICTS character name(s) already exist:"
    while IFS= read -r charname; do
      warn "    - $charname"
    done < "$TEMP_DIR/character_conflicts.txt"
  fi

  if $SKIP_CONFLICTS; then
    warn "Skipping conflicting entries (--skip-conflicts enabled)"
    # Remove conflicts from import lists
    if [[ -s "$TEMP_DIR/account_conflicts.txt" ]]; then
      grep -vxF -f "$TEMP_DIR/account_conflicts.txt" "$TEMP_DIR/accounts_to_import.txt" > "$TEMP_DIR/accounts_to_import_filtered.txt" || true
      mv "$TEMP_DIR/accounts_to_import_filtered.txt" "$TEMP_DIR/accounts_to_import.txt"
    fi
    if [[ -s "$TEMP_DIR/character_conflicts.txt" ]]; then
      grep -vxF -f "$TEMP_DIR/character_conflicts.txt" "$TEMP_DIR/characters_to_import.txt" > "$TEMP_DIR/characters_to_import_filtered.txt" || true
      mv "$TEMP_DIR/characters_to_import_filtered.txt" "$TEMP_DIR/characters_to_import.txt"
    fi

    ACCOUNTS_TO_IMPORT=$(wc -l < "$TEMP_DIR/accounts_to_import.txt" | tr -d ' ')
    CHARACTERS_TO_IMPORT=$(wc -l < "$TEMP_DIR/characters_to_import.txt" | tr -d ' ')

    if [[ $ACCOUNTS_TO_IMPORT -eq 0 ]] && [[ $CHARACTERS_TO_IMPORT -eq 0 ]]; then
      warn "All entries had conflicts. Nothing to import."
      exit 0
    fi
  else
    err ""
    err "Conflicts detected. Options:"
    err "  1. Use --skip-conflicts to skip existing entries"
    err "  2. Manually rename conflicting accounts/characters in the backup"
    err "  3. Delete conflicting entries from current database"
    exit 1
  fi
else
  log "No conflicts detected"
fi

# Calculate ID offsets with proper spacing
ACCOUNT_OFFSET=$CURRENT_MAX_ACCOUNT_ID
CHAR_OFFSET=$CURRENT_MAX_CHAR_GUID
ITEM_OFFSET=$((CURRENT_MAX_ITEM_GUID + 10000))

info ""
info "ID remapping offsets:"
info "  Account ID offset: +$ACCOUNT_OFFSET"
info "  Character GUID offset: +$CHAR_OFFSET"
info "  Item GUID offset: +$ITEM_OFFSET"

# Generate mapping tables
info ""
info "Generating ID mapping tables..."

# Account ID mapping
mysql_exec "$STAGE_AUTH_DB" <<EOF
CREATE TABLE IF NOT EXISTS account_id_map (
  old_id INT UNSIGNED PRIMARY KEY,
  new_id INT UNSIGNED,
  username VARCHAR(32)
);

INSERT INTO account_id_map (old_id, new_id, username)
SELECT
  id,
  id + $ACCOUNT_OFFSET,
  username
FROM account
WHERE username IN ($(printf "'%s'," $(cat "$TEMP_DIR/accounts_to_import.txt") | sed 's/,$//'));
EOF

# Character GUID mapping
mysql_exec "$STAGE_CHARS_DB" <<EOF
CREATE TABLE IF NOT EXISTS character_guid_map (
  old_guid INT UNSIGNED PRIMARY KEY,
  new_guid INT UNSIGNED,
  name VARCHAR(12),
  account INT UNSIGNED
);

INSERT INTO character_guid_map (old_guid, new_guid, name, account)
SELECT
  guid,
  guid + $CHAR_OFFSET,
  name,
  account
FROM characters
WHERE name IN ($(printf "'%s'," $(cat "$TEMP_DIR/characters_to_import.txt") | sed 's/,$//'));
EOF

# Item GUID mapping
mysql_exec "$STAGE_CHARS_DB" <<EOF
CREATE TABLE IF NOT EXISTS item_guid_map (
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

log "ID mapping tables created"

# Debug: Show mapping table counts
CHAR_MAP_COUNT=$(mysql_query "$STAGE_CHARS_DB" "SELECT COUNT(*) FROM character_guid_map;")
ITEM_MAP_COUNT=$(mysql_query "$STAGE_CHARS_DB" "SELECT COUNT(*) FROM item_guid_map;")
info "  Character mappings created: $CHAR_MAP_COUNT"
info "  Item mappings created: $ITEM_MAP_COUNT"

# Summary
info ""
info "═══════════════════════════════════════════════════════════"
info "  IMPORT SUMMARY"
info "═══════════════════════════════════════════════════════════"

mysql_query "$STAGE_AUTH_DB" "SELECT CONCAT('  ', username, ' (account id: ', old_id, ' → ', new_id, ')') FROM account_id_map;" | while read -r line; do
  info "$line"
done

if [[ $CHARACTERS_TO_IMPORT -gt 0 ]]; then
  info ""
  info "Characters to import:"
  mysql_query "$STAGE_CHARS_DB" "SELECT CONCAT('  ', name, ' (guid: ', old_guid, ' → ', new_guid, ', account: ', account, ')') FROM character_guid_map;" | while read -r line; do
    info "$line"
  done
fi

if $DRY_RUN; then
  warn ""
  warn "═══════════════════════════════════════════════════════════"
  warn "  DRY RUN MODE - No changes will be made"
  warn "═══════════════════════════════════════════════════════════"
  log ""
  log "Review complete. Remove --dry-run to perform the actual import."
  exit 0
fi

# Confirmation prompt
if ! $AUTO_CONFIRM; then
  info ""
  read -p "Proceed with import? [y/N]: " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Import cancelled"
    exit 0
  fi
fi

# Import phase
log ""
log "═══════════════════════════════════════════════════════════"
log "  IMPORT PHASE"
log "═══════════════════════════════════════════════════════════"

log "Stopping world/auth services..."
docker stop ac-worldserver ac-authserver >/dev/null 2>&1 || warn "Services already stopped"

log "Starting import..."

# Import accounts
if [[ $ACCOUNTS_TO_IMPORT -gt 0 ]]; then
  log "Importing $ACCOUNTS_TO_IMPORT account(s)..."

  # Import main account table
  info "  Importing main account table..."
  ACCOUNT_SQL=$(cat <<EOSQL
INSERT INTO account (id, username, salt, verifier, session_key, totp_secret, email, reg_mail,
                     joindate, last_ip, last_attempt_ip, failed_logins, locked, lock_country,
                     last_login, online, expansion, Flags, mutetime, mutereason, muteby, locale,
                     os, recruiter, totaltime)
SELECT
  m.new_id,
  a.username,
  a.salt,
  a.verifier,
  a.session_key,
  a.totp_secret,
  a.email,
  a.reg_mail,
  a.joindate,
  a.last_ip,
  a.last_attempt_ip,
  a.failed_logins,
  a.locked,
  a.lock_country,
  a.last_login,
  0 as online,
  a.expansion,
  a.Flags,
  a.mutetime,
  a.mutereason,
  a.muteby,
  a.locale,
  a.os,
  a.recruiter,
  a.totaltime
FROM $STAGE_AUTH_DB.account a
INNER JOIN $STAGE_AUTH_DB.account_id_map m ON a.id = m.old_id;
EOSQL
)
  ACCOUNT_SQL_EXPANDED=$(echo "$ACCOUNT_SQL" | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g")
  ACCOUNT_RESULT=$(echo "$ACCOUNT_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$AUTH_DB" 2>&1 || true)
  if echo "$ACCOUNT_RESULT" | grep -q "ERROR"; then
    err "  ✗ Account import failed:"
    echo "$ACCOUNT_RESULT" | grep "ERROR" >&2
    fatal "Account import failed. Check errors above."
  fi
  info "  ✓ Main account table imported"

  # Import account_access
  info "  Importing account_access..."
  ACCESS_SQL=$(cat <<EOSQL
INSERT INTO account_access (id, gmlevel, RealmID, comment)
SELECT
  m.new_id,
  aa.gmlevel,
  aa.RealmID,
  aa.comment
FROM STAGE_AUTH_DB.account_access aa
INNER JOIN STAGE_AUTH_DB.account_id_map m ON aa.id = m.old_id;
EOSQL
)
  ACCESS_SQL_EXPANDED=$(echo "$ACCESS_SQL" | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g")
  ACCESS_RESULT=$(echo "$ACCESS_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$AUTH_DB" 2>&1 || true)
  if echo "$ACCESS_RESULT" | grep -q "ERROR"; then
    err "  ✗ account_access import failed:"
    echo "$ACCESS_RESULT" | grep "ERROR" >&2
  fi
  info "  ✓ account_access imported"

  # Import account_banned
  info "  Importing account_banned..."
  BANNED_SQL=$(cat <<EOSQL
INSERT INTO account_banned (id, bandate, unbandate, bannedby, banreason, active)
SELECT
  m.new_id,
  ab.bandate,
  ab.unbandate,
  ab.bannedby,
  ab.banreason,
  ab.active
FROM STAGE_AUTH_DB.account_banned ab
INNER JOIN STAGE_AUTH_DB.account_id_map m ON ab.id = m.old_id;
EOSQL
)
  BANNED_SQL_EXPANDED=$(echo "$BANNED_SQL" | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g")
  BANNED_RESULT=$(echo "$BANNED_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$AUTH_DB" 2>&1 || true)
  if echo "$BANNED_RESULT" | grep -q "ERROR"; then
    err "  ✗ account_banned import failed:"
    echo "$BANNED_RESULT" | grep "ERROR" >&2
  fi
  info "  ✓ account_banned imported"

  # Import account_muted
  info "  Importing account_muted..."
  MUTED_SQL=$(cat <<EOSQL
INSERT INTO account_muted (guid, mutedate, mutetime, mutedby, mutereason)
SELECT
  m.new_id,
  am.mutedate,
  am.mutetime,
  am.mutedby,
  am.mutereason
FROM STAGE_AUTH_DB.account_muted am
INNER JOIN STAGE_AUTH_DB.account_id_map m ON am.guid = m.old_id;
EOSQL
)
  MUTED_SQL_EXPANDED=$(echo "$MUTED_SQL" | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g")
  MUTED_RESULT=$(echo "$MUTED_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$AUTH_DB" 2>&1 || true)
  if echo "$MUTED_RESULT" | grep -q "ERROR"; then
    err "  ✗ account_muted import failed:"
    echo "$MUTED_RESULT" | grep "ERROR" >&2
  fi
  info "  ✓ account_muted imported"

  log "✓ Accounts imported successfully"
fi

# Import characters
if [[ $CHARACTERS_TO_IMPORT -gt 0 ]]; then
  log "Importing $CHARACTERS_TO_IMPORT character(s) and their data..."

  # Import account_data (from characters DB, linked to account)
  cat <<EOSQL | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g; s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g" | mysql_exec "$CHARACTERS_DB"
INSERT INTO account_data (accountId, type, time, data)
SELECT
  m.new_id,
  ad.type,
  ad.time,
  ad.data
FROM $STAGE_CHARS_DB.account_data ad
INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON ad.accountId = cm.account
INNER JOIN $STAGE_AUTH_DB.account_id_map m ON ad.accountId = m.old_id
ON DUPLICATE KEY UPDATE time=VALUES(time), data=VALUES(data);
EOSQL

  # Import account_tutorial
  cat <<EOSQL | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g; s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g" | mysql_exec "$CHARACTERS_DB"
INSERT INTO account_tutorial (accountId, tut0, tut1, tut2, tut3, tut4, tut5, tut6, tut7)
SELECT
  m.new_id,
  at.tut0,
  at.tut1,
  at.tut2,
  at.tut3,
  at.tut4,
  at.tut5,
  at.tut6,
  at.tut7
FROM $STAGE_CHARS_DB.account_tutorial at
INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON at.accountId = cm.account
INNER JOIN $STAGE_AUTH_DB.account_id_map m ON at.accountId = m.old_id
ON DUPLICATE KEY UPDATE tut0=VALUES(tut0), tut1=VALUES(tut1), tut2=VALUES(tut2),
                         tut3=VALUES(tut3), tut4=VALUES(tut4), tut5=VALUES(tut5),
                         tut6=VALUES(tut6), tut7=VALUES(tut7);
EOSQL

  # Import main characters table
  CHAR_SQL=$(cat <<EOSQL
INSERT INTO characters (guid, account, name, race, class, gender, level, xp, money, skin, face,
                        hairStyle, hairColor, facialStyle, bankSlots, restState, playerFlags,
                        position_x, position_y, position_z, map, instance_id, instance_mode_mask,
                        orientation, taximask, online, cinematic, totaltime, leveltime, logout_time,
                        is_logout_resting, rest_bonus, resettalents_cost, resettalents_time,
                        trans_x, trans_y, trans_z, trans_o, transguid, extra_flags, stable_slots,
                        at_login, zone, death_expire_time, taxi_path, arenaPoints, totalHonorPoints,
                        todayHonorPoints, yesterdayHonorPoints, totalKills, todayKills, yesterdayKills,
                        chosenTitle, knownCurrencies, watchedFaction, drunk, health, power1, power2,
                        power3, power4, power5, power6, power7, latency, talentGroupsCount,
                        activeTalentGroup, exploredZones, equipmentCache, ammoId, knownTitles,
                        actionBars, grantableLevels, \`order\`, creation_date, deleteInfos_Account,
                        deleteInfos_Name, deleteDate, innTriggerId, extraBonusTalentCount)
SELECT
  cm.new_guid,
  am.new_id,
  c.name,
  c.race,
  c.class,
  c.gender,
  c.level,
  c.xp,
  c.money,
  c.skin,
  c.face,
  c.hairStyle,
  c.hairColor,
  c.facialStyle,
  c.bankSlots,
  c.restState,
  c.playerFlags,
  c.position_x,
  c.position_y,
  c.position_z,
  c.map,
  c.instance_id,
  c.instance_mode_mask,
  c.orientation,
  c.taximask,
  0 as online,
  c.cinematic,
  c.totaltime,
  c.leveltime,
  c.logout_time,
  c.is_logout_resting,
  c.rest_bonus,
  c.resettalents_cost,
  c.resettalents_time,
  c.trans_x,
  c.trans_y,
  c.trans_z,
  c.trans_o,
  c.transguid,
  c.extra_flags,
  c.stable_slots,
  c.at_login,
  c.zone,
  c.death_expire_time,
  c.taxi_path,
  c.arenaPoints,
  c.totalHonorPoints,
  c.todayHonorPoints,
  c.yesterdayHonorPoints,
  c.totalKills,
  c.todayKills,
  c.yesterdayKills,
  c.chosenTitle,
  c.knownCurrencies,
  c.watchedFaction,
  c.drunk,
  c.health,
  c.power1,
  c.power2,
  c.power3,
  c.power4,
  c.power5,
  c.power6,
  c.power7,
  c.latency,
  c.talentGroupsCount,
  c.activeTalentGroup,
  c.exploredZones,
  c.equipmentCache,
  c.ammoId,
  c.knownTitles,
  c.actionBars,
  c.grantableLevels,
  c.\`order\`,
  c.creation_date,
  c.deleteInfos_Account,
  c.deleteInfos_Name,
  c.deleteDate,
  c.innTriggerId,
  c.extraBonusTalentCount
FROM $STAGE_CHARS_DB.characters c
INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON c.guid = cm.old_guid
INNER JOIN $STAGE_AUTH_DB.account_id_map am ON c.account = am.old_id;
EOSQL
)
  CHAR_SQL_EXPANDED=$(echo "$CHAR_SQL" | sed "s/STAGE_AUTH_DB/$STAGE_AUTH_DB/g; s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g")
  CHAR_RESULT=$(echo "$CHAR_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1 | tee /tmp/char-import-result.log)
  if echo "$CHAR_RESULT" | grep -q "ERROR"; then
    err "✗ Character import failed with errors:"
    echo "$CHAR_RESULT" >&2
    fatal "Character import SQL failed. See /tmp/char-import-result.log for details."
  fi
  CHARS_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM characters WHERE account IN (101, 102);")
  info "  Characters imported: $CHARS_IMPORTED"

  log "✓ Main character data imported"

  # Import items
  log "Importing character items..."

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
  ITEM_COUNT=$(echo "$ITEM_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1 | tee /dev/stderr | grep -c "ERROR" || echo "0")
  if [[ "$ITEM_COUNT" != "0" ]]; then
    warn "  Warning: Errors occurred during item_instance import"
  fi

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
  INV_COUNT=$(echo "$INV_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1 | tee /dev/stderr | grep -c "ERROR" || echo "0")
  if [[ "$INV_COUNT" != "0" ]]; then
    warn "  Warning: Errors occurred during character_inventory import"
  fi

  # Report counts
  ITEMS_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM item_instance WHERE owner_guid IN (SELECT new_guid FROM $STAGE_CHARS_DB.character_guid_map);")
  INV_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM character_inventory WHERE guid IN (SELECT new_guid FROM $STAGE_CHARS_DB.character_guid_map);")
  info "  Items imported: $ITEMS_IMPORTED"
  info "  Inventory slots imported: $INV_IMPORTED"

  log "✓ Items imported"

  # Import character sub-tables
  log "Importing character progression data..."

  # List of character tables to import (guid-based)
  CHAR_TABLES=(
    "character_account_data"
    "character_achievement"
    "character_achievement_progress"
    "character_action"
    "character_arena_stats"
    "character_aura"
    "character_banned"
    "character_battleground_random"
    "character_brew_of_the_month"
    "character_declinedname"
    "character_entry_point"
    "character_equipmentsets"
    "character_gifts"
    "character_glyphs"
    "character_homebind"
    "character_instance"
    "character_pet"
    "character_pet_declinedname"
    "character_queststatus"
    "character_queststatus_daily"
    "character_queststatus_monthly"
    "character_queststatus_rewarded"
    "character_queststatus_seasonal"
    "character_queststatus_weekly"
    "character_reputation"
    "character_settings"
    "character_skills"
    "character_social"
    "character_spell"
    "character_spell_cooldown"
    "character_stats"
    "character_talent"
    "character_void_storage"
  )

  for table in "${CHAR_TABLES[@]}"; do
    # Check if table exists in staging DB
    table_exists=$(mysql_query "$STAGE_CHARS_DB" "SHOW TABLES LIKE '$table';" || echo "")
    if [[ -z "$table_exists" ]]; then
      continue
    fi

    # Count rows for this character in the table
    row_count=$(mysql_query "$STAGE_CHARS_DB" "
      SELECT COUNT(*)
      FROM $table t
      INNER JOIN character_guid_map cm ON t.guid = cm.old_guid
    " 2>/dev/null || echo "0")

    if [[ "$row_count" == "0" ]]; then
      continue
    fi

    # Get all columns except guid
    columns=$(mysql_query "$STAGE_CHARS_DB" "
      SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION SEPARATOR ', ')
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = '$STAGE_CHARS_DB' AND TABLE_NAME = '$table'
    ")

    # Build select list with guid remapping
    select_list=$(echo "$columns" | sed 's/\bguid\b/cm.new_guid/g')

    # Import with guid remapping
    PROG_SQL="INSERT IGNORE INTO $table ($columns) SELECT $select_list FROM $STAGE_CHARS_DB.$table t INNER JOIN $STAGE_CHARS_DB.character_guid_map cm ON t.guid = cm.old_guid;"
    PROG_SQL_EXPANDED=$(echo "$PROG_SQL" | sed "s/STAGE_CHARS_DB/$STAGE_CHARS_DB/g")
    PROG_RESULT=$(echo "$PROG_SQL_EXPANDED" | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" 2>&1)
    if echo "$PROG_RESULT" | grep -q "ERROR"; then
      warn "  Warning: Errors importing $table:"
      echo "$PROG_RESULT" | grep "ERROR" >&2
    else
      ROWS_IMPORTED=$(mysql_query "$CHARACTERS_DB" "SELECT COUNT(*) FROM $table WHERE guid IN (SELECT new_guid FROM $STAGE_CHARS_DB.character_guid_map);")
      info "    $table: $ROWS_IMPORTED rows"
    fi

  done

  log "✓ Character progression data imported"
fi

# Restart services
log ""
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

# Final report
log ""
log "═══════════════════════════════════════════════════════════"
log "  IMPORT COMPLETE"
log "═══════════════════════════════════════════════════════════"

if [[ $ACCOUNTS_TO_IMPORT -gt 0 ]]; then
  log ""
  log "Imported accounts:"
  while IFS= read -r username; do
    new_id=$(mysql_query "$AUTH_DB" "SELECT id FROM account WHERE username='$username';" || echo "?")
    log "  ✓ $username (account id: $new_id)"
  done < "$TEMP_DIR/accounts_to_import.txt"
fi

if [[ $CHARACTERS_TO_IMPORT -gt 0 ]]; then
  log ""
  log "Imported characters:"
  while IFS= read -r charname; do
    new_guid=$(mysql_query "$CHARACTERS_DB" "SELECT guid FROM characters WHERE name='$charname';" || echo "?")
    log "  ✓ $charname (guid: $new_guid)"
  done < "$TEMP_DIR/characters_to_import.txt"
fi

log ""
log "Merge complete! All accounts and characters have been imported."
log "Players can now log in with their restored accounts."

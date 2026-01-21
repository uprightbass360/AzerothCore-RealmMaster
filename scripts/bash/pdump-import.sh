#!/bin/bash
# Import character pdump files into AzerothCore database
set -euo pipefail

INVOCATION_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/common.sh"

MYSQL_PW=""
PDUMP_FILE=""
TARGET_ACCOUNT=""
NEW_CHARACTER_NAME=""
FORCE_GUID=""
AUTH_DB="acore_auth"
CHARACTERS_DB="acore_characters"
DRY_RUN=false
BACKUP_BEFORE=true

usage(){
  cat <<'EOF'
Usage: ./pdump-import.sh [options]

Import character pdump files into AzerothCore database.

Required Options:
  -f, --file FILE           Pdump file to import (.pdump or .sql format)
  -a, --account ACCOUNT     Target account name or ID for character import
  -p, --password PASS       MySQL root password

Optional:
  -n, --name NAME           New character name (if different from dump)
  -g, --guid GUID           Force specific character GUID
      --auth-db NAME        Auth database schema name (default: acore_auth)
      --characters-db NAME  Characters database schema name (default: acore_characters)
      --dry-run             Validate pdump without importing
      --no-backup           Skip pre-import backup (not recommended)
  -h, --help                Show this help and exit

Examples:
  # Import character from pdump file
  ./pdump-import.sh --file character.pdump --account testaccount --password azerothcore123

  # Import with new character name
  ./pdump-import.sh --file oldchar.pdump --account newaccount --name "NewCharName" --password azerothcore123

  # Validate pdump file without importing
  ./pdump-import.sh --file character.pdump --account testaccount --password azerothcore123 --dry-run

Notes:
  - Account must exist in the auth database before import
  - Character names must be unique across the server
  - Pre-import backup is created automatically (can be disabled with --no-backup)
  - Use --dry-run to validate pdump structure before actual import
EOF
}

validate_account(){
  local account="$1"
  if [[ "$account" =~ ^[0-9]+$ ]]; then
    # Account ID provided
    local count
    count=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
      "SELECT COUNT(*) FROM ${AUTH_DB}.account WHERE id = $account;")
    [[ "$count" -eq 1 ]] || fatal "Account ID $account not found in auth database"
  else
    # Account name provided
    local count
    count=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
      "SELECT COUNT(*) FROM ${AUTH_DB}.account WHERE username = '$account';")
    [[ "$count" -eq 1 ]] || fatal "Account '$account' not found in auth database"
  fi
}

get_account_id(){
  local account="$1"
  if [[ "$account" =~ ^[0-9]+$ ]]; then
    echo "$account"
  else
    docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
      "SELECT id FROM ${AUTH_DB}.account WHERE username = '$account';"
  fi
}

validate_character_name(){
  local name="$1"
  # Check character name format (WoW naming rules)
  if [[ ! "$name" =~ ^[A-Za-z]{2,12}$ ]]; then
    fatal "Invalid character name: '$name'. Must be 2-12 letters, no numbers or special characters."
  fi

  # Check if character name already exists
  local count
  count=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
    "SELECT COUNT(*) FROM ${CHARACTERS_DB}.characters WHERE name = '$name';")
  [[ "$count" -eq 0 ]] || fatal "Character name '$name' already exists in database"
}

get_next_guid(){
  docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
    "SELECT COALESCE(MAX(guid), 0) + 1 FROM ${CHARACTERS_DB}.characters;"
}

validate_pdump_format(){
  local file="$1"
  if [[ ! -f "$file" ]]; then
    fatal "Pdump file not found: $file"
  fi

  # Check if file is readable and has SQL-like content
  if ! head -10 "$file" | grep -q -i "INSERT\|UPDATE\|CREATE\|ALTER"; then
    warn "File does not appear to contain SQL statements. Continuing anyway..."
  fi

  info "Pdump file validation: OK"
}

backup_characters(){
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="manual-backups/characters-pre-pdump-import-${timestamp}.sql"
  mkdir -p manual-backups

  log "Creating backup: $backup_file"
  docker exec ac-mysql mysqldump -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" > "$backup_file"
  echo "$backup_file"
}

process_pdump_sql(){
  local file="$1"
  local account_id="$2"
  local new_guid="${3:-}"
  local new_name="${4:-}"

  # Create temporary processed file
  local temp_file
  temp_file=$(mktemp)

  # Process the pdump SQL file
  # Replace account references and optionally GUID/name
  if [[ -n "$new_guid" && -n "$new_name" ]]; then
    sed -e "s/\([^0-9]\)[0-9]\+\([^0-9].*account.*=\)/\1${account_id}\2/g" \
        -e "s/\([^0-9]\)[0-9]\+\([^0-9].*guid.*=\)/\1${new_guid}\2/g" \
        -e "s/'[^']*'\([^']*name.*=\)/'${new_name}'\1/g" \
        "$file" > "$temp_file"
  elif [[ -n "$new_guid" ]]; then
    sed -e "s/\([^0-9]\)[0-9]\+\([^0-9].*account.*=\)/\1${account_id}\2/g" \
        -e "s/\([^0-9]\)[0-9]\+\([^0-9].*guid.*=\)/\1${new_guid}\2/g" \
        "$file" > "$temp_file"
  elif [[ -n "$new_name" ]]; then
    sed -e "s/\([^0-9]\)[0-9]\+\([^0-9].*account.*=\)/\1${account_id}\2/g" \
        -e "s/'[^']*'\([^']*name.*=\)/'${new_name}'\1/g" \
        "$file" > "$temp_file"
  else
    sed -e "s/\([^0-9]\)[0-9]\+\([^0-9].*account.*=\)/\1${account_id}\2/g" \
        "$file" > "$temp_file"
  fi

  echo "$temp_file"
}

import_pdump(){
  local processed_file="$1"

  log "Importing character data into $CHARACTERS_DB database"
  if docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$CHARACTERS_DB" < "$processed_file"; then
    log "Character import completed successfully"
  else
    fatal "Character import failed. Check MySQL logs for details."
  fi
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

# Parse command line arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -ge 2 ]] || fatal "--file requires a file path"
      PDUMP_FILE="$2"
      shift 2
      ;;
    -a|--account)
      [[ $# -ge 2 ]] || fatal "--account requires an account name or ID"
      TARGET_ACCOUNT="$2"
      shift 2
      ;;
    -p|--password)
      [[ $# -ge 2 ]] || fatal "--password requires a value"
      MYSQL_PW="$2"
      shift 2
      ;;
    -n|--name)
      [[ $# -ge 2 ]] || fatal "--name requires a character name"
      NEW_CHARACTER_NAME="$2"
      shift 2
      ;;
    -g|--guid)
      [[ $# -ge 2 ]] || fatal "--guid requires a GUID number"
      FORCE_GUID="$2"
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
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-backup)
      BACKUP_BEFORE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      break
      ;;
    -*)
      fatal "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Validate required arguments
[[ -n "$PDUMP_FILE" ]] || fatal "Pdump file is required. Use --file FILE"
[[ -n "$TARGET_ACCOUNT" ]] || fatal "Target account is required. Use --account ACCOUNT"
[[ -n "$MYSQL_PW" ]] || fatal "MySQL password is required. Use --password PASS"

# Resolve relative paths
if [[ ! "$PDUMP_FILE" =~ ^/ ]]; then
  PDUMP_FILE="$INVOCATION_DIR/$PDUMP_FILE"
fi

# Validate inputs
log "Validating pdump file..."
validate_pdump_format "$PDUMP_FILE"

log "Validating target account..."
validate_account "$TARGET_ACCOUNT"
ACCOUNT_ID=$(get_account_id "$TARGET_ACCOUNT")
log "Target account ID: $ACCOUNT_ID"

if [[ -n "$NEW_CHARACTER_NAME" ]]; then
  log "Validating new character name..."
  validate_character_name "$NEW_CHARACTER_NAME"
fi

# Determine GUID
if [[ -n "$FORCE_GUID" ]]; then
  CHARACTER_GUID="$FORCE_GUID"
  log "Using forced GUID: $CHARACTER_GUID"
else
  CHARACTER_GUID=$(get_next_guid)
  log "Using next available GUID: $CHARACTER_GUID"
fi

# Process pdump file
log "Processing pdump file..."
PROCESSED_FILE=$(process_pdump_sql "$PDUMP_FILE" "$ACCOUNT_ID" "$CHARACTER_GUID" "$NEW_CHARACTER_NAME")

if $DRY_RUN; then
  info "DRY RUN: Pdump processing completed successfully"
  info "Processed file saved to: $PROCESSED_FILE"
  info "Account ID: $ACCOUNT_ID"
  info "Character GUID: $CHARACTER_GUID"
  [[ -n "$NEW_CHARACTER_NAME" ]] && info "Character name: $NEW_CHARACTER_NAME"
  info "Run without --dry-run to perform actual import"
  rm -f "$PROCESSED_FILE"
  exit 0
fi

# Create backup before import
BACKUP_FILE=""
if $BACKUP_BEFORE; then
  BACKUP_FILE=$(backup_characters)
fi

# Stop world server to prevent issues during import
log "Stopping world server for safe import..."
docker stop ac-worldserver >/dev/null 2>&1 || warn "World server was not running"

# Perform import
trap 'rm -f "$PROCESSED_FILE"' EXIT
import_pdump "$PROCESSED_FILE"

# Restart world server
log "Restarting world server..."
docker start ac-worldserver >/dev/null 2>&1

# Wait for server to initialize
log "Waiting for world server to initialize..."
for i in {1..30}; do
  if docker exec ac-worldserver pgrep worldserver >/dev/null 2>&1; then
    log "World server is running"
    break
  fi
  if [ $i -eq 30 ]; then
    warn "World server took longer than expected to start"
  fi
  sleep 2
done

# Verify import
CHARACTER_COUNT=$(docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e \
  "SELECT COUNT(*) FROM ${CHARACTERS_DB}.characters WHERE account = $ACCOUNT_ID;")

log "Import completed successfully!"
log "Characters on account $TARGET_ACCOUNT: $CHARACTER_COUNT"
[[ -n "$BACKUP_FILE" ]] && log "Backup created: $BACKUP_FILE"

info "Character import from pdump completed. You can now log in and play!"

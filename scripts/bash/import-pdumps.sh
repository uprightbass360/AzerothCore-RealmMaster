#!/bin/bash
# Process and import character pdump files from import/pdumps/ directory
set -euo pipefail

INVOCATION_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."  # Go to project root

source "$SCRIPT_DIR/lib/common.sh"

# Source environment variables
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

IMPORT_DIR="./import/pdumps"
MYSQL_PW="${MYSQL_ROOT_PASSWORD:-}"
AUTH_DB="${ACORE_DB_AUTH_NAME:-acore_auth}"
CHARACTERS_DB="${ACORE_DB_CHARACTERS_NAME:-acore_characters}"
DEFAULT_ACCOUNT="${DEFAULT_IMPORT_ACCOUNT:-}"
INTERACTIVE=${INTERACTIVE:-true}

usage(){
  cat <<'EOF'
Usage: ./import-pdumps.sh [options]

Automatically process and import all character pdump files from import/pdumps/ directory.

Options:
  --password PASS           MySQL root password (overrides env)
  --account ACCOUNT         Default account for imports (overrides env)
  --auth-db NAME           Auth database name (overrides env)
  --characters-db NAME     Characters database name (overrides env)
  --non-interactive        Don't prompt for missing information
  -h, --help               Show this help and exit

Directory Structure:
  import/pdumps/
  ├── character1.pdump     # Will be imported with default settings
  ├── character2.sql       # SQL dump files also supported
  └── configs/             # Optional: per-file configuration
      ├── character1.conf  # account=testuser, name=NewName
      └── character2.conf  # account=12345, guid=5000

Configuration File Format (.conf):
  account=target_account_name_or_id
  name=new_character_name      # Optional: rename character
  guid=force_specific_guid     # Optional: force GUID

Environment Variables:
  MYSQL_ROOT_PASSWORD      # MySQL root password
  DEFAULT_IMPORT_ACCOUNT   # Default account for imports
  ACORE_DB_AUTH_NAME      # Auth database name
  ACORE_DB_CHARACTERS_NAME # Characters database name

Examples:
  # Import all pdumps with environment settings
  ./import-pdumps.sh

  # Import with specific password and account
  ./import-pdumps.sh --password mypass --account testuser

EOF
}

check_dependencies(){
  if ! docker ps >/dev/null 2>&1; then
    fatal "Docker is not running or accessible"
  fi

  if ! docker exec ac-mysql mysql --version >/dev/null 2>&1; then
    fatal "MySQL container (ac-mysql) is not running or accessible"
  fi
}

parse_config_file(){
  local config_file="$1"
  local -A config=()

  if [[ -f "$config_file" ]]; then
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$key" ]] && continue

      # Remove leading/trailing whitespace
      key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      config["$key"]="$value"
    done < "$config_file"
  fi

  # Export as variables for the calling function
  export CONFIG_ACCOUNT="${config[account]:-}"
  export CONFIG_NAME="${config[name]:-}"
  export CONFIG_GUID="${config[guid]:-}"
}

prompt_for_account(){
  local filename="$1"
  if [[ "$INTERACTIVE" != "true" ]]; then
    fatal "No account specified for $filename and running in non-interactive mode"
  fi

  echo ""
  warn "No account specified for: $filename"
  echo "Available options:"
  echo "  1. Provide account name or ID"
  echo "  2. Skip this file"
  echo ""

  while true; do
    read -p "Enter account name/ID (or 'skip'): " account_input
    case "$account_input" in
      skip|Skip|SKIP)
        return 1
        ;;
      "")
        warn "Please enter an account name/ID or 'skip'"
        continue
        ;;
      *)
        echo "$account_input"
        return 0
        ;;
    esac
  done
}

process_pdump_file(){
  local pdump_file="$1"
  local filename
  filename=$(basename "$pdump_file")
  local config_file="$IMPORT_DIR/configs/${filename%.*}.conf"

  info "Processing: $filename"

  # Parse configuration file if it exists
  parse_config_file "$config_file"

  # Determine account
  local target_account="${CONFIG_ACCOUNT:-$DEFAULT_ACCOUNT}"
  if [[ -z "$target_account" ]]; then
    if ! target_account=$(prompt_for_account "$filename"); then
      warn "Skipping $filename (no account provided)"
      return 0
    fi
  fi

  # Build command arguments
  local cmd_args=(
    --file "$pdump_file"
    --account "$target_account"
    --password "$MYSQL_PW"
    --auth-db "$AUTH_DB"
    --characters-db "$CHARACTERS_DB"
  )

  # Add optional parameters if specified in config
  [[ -n "$CONFIG_NAME" ]] && cmd_args+=(--name "$CONFIG_NAME")
  [[ -n "$CONFIG_GUID" ]] && cmd_args+=(--guid "$CONFIG_GUID")

  log "Importing $filename to account $target_account"
  [[ -n "$CONFIG_NAME" ]] && log "  Character name: $CONFIG_NAME"
  [[ -n "$CONFIG_GUID" ]] && log "  Forced GUID: $CONFIG_GUID"

  # Execute the import
  if "./scripts/bash/pdump-import.sh" "${cmd_args[@]}"; then
    log "✅ Successfully imported: $filename"

    # Move processed file to processed/ subdirectory
    local processed_dir="$IMPORT_DIR/processed"
    mkdir -p "$processed_dir"
    mv "$pdump_file" "$processed_dir/"
    [[ -f "$config_file" ]] && mv "$config_file" "$processed_dir/"

  else
    err "❌ Failed to import: $filename"
    return 1
  fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --password)
      [[ $# -ge 2 ]] || fatal "--password requires a value"
      MYSQL_PW="$2"
      shift 2
      ;;
    --account)
      [[ $# -ge 2 ]] || fatal "--account requires a value"
      DEFAULT_ACCOUNT="$2"
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
    --non-interactive)
      INTERACTIVE=false
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

# Validate required parameters
[[ -n "$MYSQL_PW" ]] || fatal "MySQL password required (use --password or set MYSQL_ROOT_PASSWORD)"

# Check dependencies
check_dependencies

# Check if import directory exists and has files
if [[ ! -d "$IMPORT_DIR" ]]; then
  info "Import directory doesn't exist: $IMPORT_DIR"
  info "Create the directory and place your .pdump or .sql files there."
  exit 0
fi

# Find pdump files
shopt -s nullglob
pdump_files=("$IMPORT_DIR"/*.pdump "$IMPORT_DIR"/*.sql)
shopt -u nullglob

if [[ ${#pdump_files[@]} -eq 0 ]]; then
  info "No pdump files found in $IMPORT_DIR"
  info "Place your .pdump or .sql files in this directory to import them."
  exit 0
fi

log "Found ${#pdump_files[@]} pdump file(s) to process"

# Create configs directory if it doesn't exist
mkdir -p "$IMPORT_DIR/configs"

# Process each file
processed=0
failed=0

for pdump_file in "${pdump_files[@]}"; do
  if process_pdump_file "$pdump_file"; then
    ((processed++))
  else
    ((failed++))
  fi
done

echo ""
log "Import summary:"
log "  ✅ Processed: $processed"
[[ $failed -gt 0 ]] && err "  ❌ Failed: $failed"

if [[ $processed -gt 0 ]]; then
  log ""
  log "Character imports completed! Processed files moved to $IMPORT_DIR/processed/"
  log "You can now log in and access your imported characters."
fi

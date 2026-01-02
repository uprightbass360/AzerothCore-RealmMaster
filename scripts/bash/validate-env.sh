#!/bin/bash
# Validate environment configuration for AzerothCore RealmMaster
# Usage: ./scripts/bash/validate-env.sh [--strict] [--quiet]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_FILE="$PROJECT_ROOT/.env.template"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
STRICT_MODE=false
QUIET_MODE=false
EXIT_CODE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT_MODE=true
      shift
      ;;
    --quiet)
      QUIET_MODE=true
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: $0 [OPTIONS]

Validates environment configuration for required variables.

OPTIONS:
  --strict    Fail on missing optional variables
  --quiet     Only show errors, suppress info/success messages
  -h, --help  Show this help

EXIT CODES:
  0 - All required variables present
  1 - Missing required variables
  2 - Missing optional variables (only in --strict mode)

REQUIRED VARIABLES:
  Project Configuration:
    COMPOSE_PROJECT_NAME       - Project name for containers/images
    NETWORK_NAME              - Docker network name

  Repository Configuration:
    ACORE_REPO_STANDARD       - Standard AzerothCore repository URL
    ACORE_BRANCH_STANDARD     - Standard AzerothCore branch name
    ACORE_REPO_PLAYERBOTS     - Playerbots repository URL
    ACORE_BRANCH_PLAYERBOTS   - Playerbots branch name

  Storage Paths:
    STORAGE_PATH              - Main storage path
    STORAGE_PATH_LOCAL        - Local storage path

  Database Configuration:
    MYSQL_ROOT_PASSWORD       - MySQL root password
    MYSQL_USER                - MySQL user (typically root)
    MYSQL_PORT                - MySQL port (typically 3306)
    MYSQL_HOST                - MySQL hostname
    DB_AUTH_NAME              - Auth database name
    DB_WORLD_NAME             - World database name
    DB_CHARACTERS_NAME        - Characters database name
    DB_PLAYERBOTS_NAME        - Playerbots database name

  Container Configuration:
    CONTAINER_MYSQL           - MySQL container name
    CONTAINER_USER            - Container user (format: uid:gid)

OPTIONAL VARIABLES (checked with --strict):
  MySQL Performance:
    MYSQL_INNODB_BUFFER_POOL_SIZE - InnoDB buffer pool size
    MYSQL_INNODB_LOG_FILE_SIZE    - InnoDB log file size
    MYSQL_INNODB_REDO_LOG_CAPACITY - InnoDB redo log capacity

  Database Connection:
    DB_RECONNECT_SECONDS      - Database reconnection delay
    DB_RECONNECT_ATTEMPTS     - Database reconnection attempts

  Build Configuration:
    MODULES_REBUILD_SOURCE_PATH - Path to source for module builds

  Backup Configuration:
    BACKUP_PATH               - Backup storage path
    BACKUP_RETENTION_DAYS     - Daily backup retention
    BACKUP_RETENTION_HOURS    - Hourly backup retention

  Image Configuration:
    AC_AUTHSERVER_IMAGE       - Auth server Docker image
    AC_WORLDSERVER_IMAGE      - World server Docker image
    AC_DB_IMPORT_IMAGE        - Database import Docker image

EXAMPLES:
  $0                  # Basic validation
  $0 --strict         # Strict validation (check optional vars)
  $0 --quiet          # Only show errors
EOF
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      exit 1
      ;;
  esac
done

log_info() {
  $QUIET_MODE || echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
  $QUIET_MODE || echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $*${NC}" >&2
}

log_error() {
  echo -e "${RED}❌ $*${NC}" >&2
}

# Load environment
load_env() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$file" 2>/dev/null || return 1
  set +a
  return 0
}

# Check if variable is set and non-empty
check_var() {
  local var_name="$1"
  local var_value="${!var_name:-}"

  if [[ -z "$var_value" ]]; then
    return 1
  fi
  return 0
}

# Validate required variables
validate_required() {
  local missing=()

  local required_vars=(
    # Project Configuration
    "COMPOSE_PROJECT_NAME"
    "NETWORK_NAME"
    # Repository Configuration
    "ACORE_REPO_STANDARD"
    "ACORE_BRANCH_STANDARD"
    "ACORE_REPO_PLAYERBOTS"
    "ACORE_BRANCH_PLAYERBOTS"
    # Storage Paths
    "STORAGE_PATH"
    "STORAGE_PATH_LOCAL"
    # Database Configuration
    "MYSQL_ROOT_PASSWORD"
    "MYSQL_USER"
    "MYSQL_PORT"
    "MYSQL_HOST"
    "DB_AUTH_NAME"
    "DB_WORLD_NAME"
    "DB_CHARACTERS_NAME"
    "DB_PLAYERBOTS_NAME"
    # Container Configuration
    "CONTAINER_MYSQL"
    "CONTAINER_USER"
  )

  log_info "Checking required variables..."

  for var in "${required_vars[@]}"; do
    if check_var "$var"; then
      log_success "$var=${!var}"
    else
      log_error "$var is not set"
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required variables: ${missing[*]}"
    return 1
  fi

  log_success "All required variables are set"
  return 0
}

# Validate optional variables (strict mode)
validate_optional() {
  local missing=()

  local optional_vars=(
    # MySQL Performance Tuning
    "MYSQL_INNODB_BUFFER_POOL_SIZE"
    "MYSQL_INNODB_LOG_FILE_SIZE"
    "MYSQL_INNODB_REDO_LOG_CAPACITY"
    # Database Connection Settings
    "DB_RECONNECT_SECONDS"
    "DB_RECONNECT_ATTEMPTS"
    # Build Configuration
    "MODULES_REBUILD_SOURCE_PATH"
    # Backup Configuration
    "BACKUP_PATH"
    "BACKUP_RETENTION_DAYS"
    "BACKUP_RETENTION_HOURS"
    # Image Configuration
    "AC_AUTHSERVER_IMAGE"
    "AC_WORLDSERVER_IMAGE"
    "AC_DB_IMPORT_IMAGE"
  )

  log_info "Checking optional variables..."

  for var in "${optional_vars[@]}"; do
    if check_var "$var"; then
      log_success "$var is set"
    else
      log_warning "$var is not set (using default)"
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warning "Optional variables not set: ${missing[*]}"
    return 2
  fi

  log_success "All optional variables are set"
  return 0
}

# Main validation
main() {
  log_info "Validating environment configuration..."
  echo ""

  # Check if .env exists
  if [[ ! -f "$ENV_FILE" ]]; then
    log_error ".env file not found at $ENV_FILE"
    log_info "Copy .env.template to .env and configure it:"
    log_info "  cp $TEMPLATE_FILE $ENV_FILE"
    exit 1
  fi

  # Load environment
  if ! load_env "$ENV_FILE"; then
    log_error "Failed to load $ENV_FILE"
    exit 1
  fi

  log_success "Loaded environment from $ENV_FILE"
  echo ""

  # Validate required variables
  if ! validate_required; then
    EXIT_CODE=1
  fi

  echo ""

  # Validate optional variables if strict mode
  if $STRICT_MODE; then
    if ! validate_optional; then
      [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=2
    fi
    echo ""
  fi

  # Final summary
  if [[ $EXIT_CODE -eq 0 ]]; then
    log_success "Environment validation passed ✨"
  elif [[ $EXIT_CODE -eq 1 ]]; then
    log_error "Environment validation failed (missing required variables)"
  elif [[ $EXIT_CODE -eq 2 ]]; then
    log_warning "Environment validation passed with warnings (missing optional variables)"
  fi

  exit $EXIT_CODE
}

main "$@"

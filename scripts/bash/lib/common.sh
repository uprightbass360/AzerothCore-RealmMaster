#!/bin/bash
#
# Common utilities library for AzerothCore RealmMaster scripts
# This library provides shared functions for environment variable reading,
# logging, error handling, and other common operations.
#
# Usage: source /path/to/scripts/bash/lib/common.sh

# Prevent multiple sourcing
if [ -n "${_COMMON_LIB_LOADED:-}" ]; then
  return 0
fi
_COMMON_LIB_LOADED=1

# =============================================================================
# COLOR DEFINITIONS (Standardized across all scripts)
# =============================================================================

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# Legacy color names for backward compatibility
COLOR_BLUE="$BLUE"
COLOR_GREEN="$GREEN"
COLOR_YELLOW="$YELLOW"
COLOR_RED="$RED"
COLOR_CYAN="$CYAN"
COLOR_RESET="$NC"

# =============================================================================
# LOGGING FUNCTIONS (Standardized with emoji)
# =============================================================================

# Log informational messages (blue with info icon)
info() {
  printf '%b\n' "${BLUE}ℹ️  $*${NC}"
}

# Log success messages (green with checkmark)
ok() {
  printf '%b\n' "${GREEN}✅ $*${NC}"
}

# Log general messages (green, no icon - for clean output)
log() {
  printf '%b\n' "${GREEN}$*${NC}"
}

# Log warning messages (yellow with warning icon)
warn() {
  printf '%b\n' "${YELLOW}⚠️  $*${NC}"
}

# Log error messages (red with error icon, continues execution)
err() {
  printf '%b\n' "${RED}❌ $*${NC}" >&2
}

# Log fatal error and exit (red with error icon, exits with code 1)
fatal() {
  printf '%b\n' "${RED}❌ $*${NC}" >&2
  exit 1
}

# =============================================================================
# ENVIRONMENT VARIABLE READING
# =============================================================================

# Read environment variable from .env file with fallback to default
# Handles various quote styles, comments, and whitespace
#
# Usage:
#   read_env KEY [DEFAULT_VALUE]
#   value=$(read_env "MYSQL_PASSWORD" "default_password")
#
# Features:
# - Reads from file specified by $ENV_PATH (or $DEFAULT_ENV_PATH)
# - Strips leading/trailing whitespace
# - Removes inline comments (everything after #)
# - Handles double quotes, single quotes, and unquoted values
# - Returns default value if key not found
# - Returns value from environment variable if already set
#
read_env() {
  local key="$1"
  local default="${2:-}"
  local value=""

  # Check if variable is already set in environment (takes precedence)
  if [ -n "${!key:-}" ]; then
    echo "${!key}"
    return 0
  fi

  # Determine which .env file to use
  local env_file="${ENV_PATH:-${DEFAULT_ENV_PATH:-}}"

  # Read from .env file if it exists
  if [ -f "$env_file" ]; then
    # Extract value using grep and cut, handling various formats
    value="$(grep -E "^${key}=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"

    # Remove inline comments (everything after # that's not inside quotes)
    # This is a simplified approach - doesn't handle quotes perfectly but works for most cases
    value="$(echo "$value" | sed 's/[[:space:]]*#.*//' | sed 's/[[:space:]]*$//')"

    # Strip quotes if present
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      # Double quotes
      value="${value:1:-1}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      # Single quotes
      value="${value:1:-1}"
    fi
  fi

  # Use default if still empty
  if [ -z "${value:-}" ]; then
    value="$default"
  fi

  printf '%s\n' "${value}"
}

# Read value from .env.template file (used during setup)
# This is similar to read_env but specifically for template files.
#
# Usage:
#   get_template_value KEY [TEMPLATE_FILE] [DEFAULT]
#   value=$(get_template_value "MYSQL_PASSWORD")
#   value=$(get_template_value "DOCKER_IMAGE_TAG" ".env.template" "latest")
#
get_template_value() {
  local key="$1"
  local template_file="${2:-${TEMPLATE_FILE:-${TEMPLATE_PATH:-.env.template}}}"
  local fallback="${3:-}"

  if [ ! -f "$template_file" ]; then
    if [ -n "$fallback" ]; then
      echo "$fallback"
      return 0
    fi
    fatal "Template file not found: $template_file"
  fi

  # Extract value, handling variable expansion syntax like ${VAR:-default}
  local value
  local raw_line
  raw_line=$(grep "^${key}=" "$template_file" 2>/dev/null | head -1)

  if [ -z "$raw_line" ]; then
    if [ -n "$fallback" ]; then
      echo "$fallback"
      return 0
    fi
    fatal "Key '$key' not found in template: $template_file"
  fi

  value="${raw_line#*=}"
  value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')

  # Handle ${VAR:-default} syntax by extracting the default value
  if [[ "$value" =~ ^\$\{[^}]*:-([^}]*)\}$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi

  if [ -z "$value" ] && [ -n "$fallback" ]; then
    value="$fallback"
  fi

  echo "$value"
}

# Update or add environment variable in .env file
# Creates file if it doesn't exist
#
# Usage:
#   update_env_value KEY VALUE [ENV_FILE]
#   update_env_value "MYSQL_PASSWORD" "new_password"
#
update_env_value() {
  local key="$1"
  local value="$2"
  local env_file="${3:-${ENV_PATH:-${DEFAULT_ENV_PATH:-.env}}}"

  [ -n "$env_file" ] || return 0

  # Create file if it doesn't exist
  if [ ! -f "$env_file" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
    return 0
  fi

  # Update existing or append new
  if grep -q "^${key}=" "$env_file"; then
    # Use platform-appropriate sed in-place editing
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    fi
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

# =============================================================================
# VALIDATION & REQUIREMENTS
# =============================================================================

# Require command to be available in PATH, exit with error if not found
#
# Usage:
#   require_cmd docker
#   require_cmd python3 jq git
#
require_cmd() {
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fatal "Missing required command: $cmd"
    fi
  done
}

# Check if command exists (returns 0 if exists, 1 if not)
#
# Usage:
#   if has_cmd docker; then
#     echo "Docker is available"
#   fi
#
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# MYSQL/DATABASE HELPERS
# =============================================================================

# Execute MySQL command in Docker container
# Reads MYSQL_PW and container name from environment
#
# Usage:
#   mysql_exec DATABASE_NAME < script.sql
#   echo "SELECT 1;" | mysql_exec acore_auth
#
mysql_exec() {
  local db="$1"
  local mysql_pw="${MYSQL_ROOT_PASSWORD:-${MYSQL_PW:-azerothcore}}"
  local container="${MYSQL_CONTAINER:-ac-mysql}"

  docker exec -i "$container" mysql -uroot -p"$mysql_pw" "$db"
}

# Execute MySQL query and return result
# Outputs in non-tabular format suitable for parsing
#
# Usage:
#   count=$(mysql_query "acore_characters" "SELECT COUNT(*) FROM characters")
#
mysql_query() {
  local db="$1"
  local query="$2"
  local mysql_pw="${MYSQL_ROOT_PASSWORD:-${MYSQL_PW:-azerothcore}}"
  local container="${MYSQL_CONTAINER:-ac-mysql}"

  docker exec "$container" mysql -uroot -p"$mysql_pw" -N -B "$db" -e "$query" 2>/dev/null
}

# Check if MySQL container is healthy and accepting connections
#
# Usage:
#   if mysql_is_ready; then
#     echo "MySQL is ready"
#   fi
#
mysql_is_ready() {
  local container="${MYSQL_CONTAINER:-ac-mysql}"
  local mysql_pw="${MYSQL_ROOT_PASSWORD:-${MYSQL_PW:-azerothcore}}"

  docker exec "$container" mysqladmin ping -uroot -p"$mysql_pw" >/dev/null 2>&1
}

# Wait for MySQL to be ready with timeout
#
# Usage:
#   mysql_wait_ready 60  # Wait up to 60 seconds
#
mysql_wait_ready() {
  local timeout="${1:-30}"
  local elapsed=0

  info "Waiting for MySQL to be ready..."

  while [ $elapsed -lt $timeout ]; do
    if mysql_is_ready; then
      ok "MySQL is ready"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  err "MySQL did not become ready within ${timeout}s"
  return 1
}

# =============================================================================
# FILE & DIRECTORY HELPERS
# =============================================================================

# Ensure directory exists and is writable
# Creates directory if needed and sets permissions
#
# Usage:
#   ensure_writable_dir /path/to/directory
#
ensure_writable_dir() {
  local dir="$1"

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" 2>/dev/null || {
      err "Failed to create directory: $dir"
      return 1
    }
  fi

  if [ ! -w "$dir" ]; then
    chmod u+w "$dir" 2>/dev/null || {
      err "Directory not writable: $dir"
      return 1
    }
  fi

  return 0
}

# Create backup of file before modification
#
# Usage:
#   backup_file /path/to/important.conf
#   # Creates /path/to/important.conf.backup.TIMESTAMP
#
backup_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    warn "File does not exist, skipping backup: $file"
    return 0
  fi

  local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$file" "$backup" || {
    err "Failed to create backup: $backup"
    return 1
  }

  info "Created backup: $backup"
  return 0
}

# =============================================================================
# GIT HELPERS
# =============================================================================

# Configure git identity if not already set
#
# Usage:
#   setup_git_config [USERNAME] [EMAIL]
#
setup_git_config() {
  local git_user="${1:-${GIT_USERNAME:-AzerothCore RealmMaster}}"
  local git_email="${2:-${GIT_EMAIL:-noreply@azerothcore.org}}"

  if ! git config --global user.name >/dev/null 2>&1; then
    info "Configuring git identity: $git_user <$git_email>"
    git config --global user.name "$git_user" || true
    git config --global user.email "$git_email" || true
  fi
}

# =============================================================================
# ERROR HANDLING UTILITIES
# =============================================================================

# Retry command with exponential backoff
#
# Usage:
#   retry 5 docker pull myimage:latest
#   retry 3 2 mysql_query "acore_auth" "SELECT 1"  # 3 retries with 2s initial delay
#
retry() {
  local max_attempts="$1"
  shift
  local delay="${1:-1}"

  # Check if delay is a number, if not treat it as part of the command
  if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
    delay=1
  else
    shift
  fi

  local attempt=1
  local exit_code=0

  while [ $attempt -le "$max_attempts" ]; do
    if "$@"; then
      return 0
    fi

    exit_code=$?

    if [ $attempt -lt "$max_attempts" ]; then
      warn "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi

    attempt=$((attempt + 1))
  done

  err "Command failed after $max_attempts attempts"
  return $exit_code
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Library loaded successfully
# Scripts can check for $_COMMON_LIB_LOADED to verify library is loaded

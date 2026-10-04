#!/bin/bash
# Updates the realmlist table in the database with current SERVER_ADDRESS and REALM_PORT from .env
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source colors and functions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { printf '%b\n' "${BLUE}ℹ️  $*${NC}"; }
ok() { printf '%b\n' "${GREEN}✅ $*${NC}"; }
warn() { printf '%b\n' "${YELLOW}⚠️  $*${NC}"; }
err() { printf '%b\n' "${RED}❌ $*${NC}"; }

# Load environment variables from .env
if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT_DIR/.env"
  set +a
else
  err "No .env file found at $ROOT_DIR/.env"
  exit 1
fi

# Check required variables
if [ -z "$SERVER_ADDRESS" ]; then
  err "SERVER_ADDRESS not set in .env"
  exit 1
fi

if [ -z "$REALM_PORT" ]; then
  err "REALM_PORT not set in .env"
  exit 1
fi

if [ -z "$MYSQL_USER" ]; then
  err "MYSQL_USER not set in .env"
  exit 1
fi

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
  err "MYSQL_ROOT_PASSWORD not set in .env"
  exit 1
fi

if [ -z "$DB_AUTH_NAME" ]; then
  err "DB_AUTH_NAME not set in .env"
  exit 1
fi

info "Updating realmlist table..."
info "  Address: $SERVER_ADDRESS"
info "  Port: $REALM_PORT"

# Run the queries inside the MySQL container: the MySQL host name (ac-mysql)
# only resolves on the compose network, and the host may have no mysql client.
mysql_container="${CONTAINER_MYSQL:-ac-mysql}"
run_sql(){
  docker exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "$mysql_container" \
    mysql -u"${MYSQL_USER}" "${DB_AUTH_NAME}" -e "$1"
}

# Try to update the database
if run_sql "UPDATE realmlist SET address='${SERVER_ADDRESS}', port=${REALM_PORT} WHERE id=1;" 2>/dev/null; then
  ok "Realmlist updated successfully"

  # Show the current realmlist entry
  run_sql "SELECT id, name, address, port FROM realmlist WHERE id=1;" 2>/dev/null || true

  exit 0
else
  warn "Could not update realmlist table"
  warn "This is normal if the database is not yet initialized or MySQL is not running"
  exit 1
fi

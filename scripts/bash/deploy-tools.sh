#!/bin/bash

# azerothcore-rm helper to deploy phpMyAdmin and Keira3 tooling.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
DEFAULT_COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"
TEMPLATE_FILE="$ROOT_DIR/.env.template"
source "$ROOT_DIR/scripts/bash/project_name.sh"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"
source "$ROOT_DIR/scripts/bash/compose_overrides.sh"
declare -a COMPOSE_FILE_ARGS=()

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info(){ echo -e "${BLUE}ℹ️  $*${NC}"; }
ok(){ echo -e "${GREEN}✅ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${NC}"; }
err(){ echo -e "${RED}❌ $*${NC}"; }

read_env(){
  local key="$1" default="${2:-}" value=""
  if [ -f "$ENV_FILE" ]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

resolve_project_name(){
  local raw_name sanitized
  raw_name="$(read_env COMPOSE_PROJECT_NAME "$DEFAULT_PROJECT_NAME")"
  project_name::sanitize "$raw_name"
}

init_compose_files(){
  compose_overrides::build_compose_args "$ROOT_DIR" "$ENV_FILE" "$DEFAULT_COMPOSE_FILE" COMPOSE_FILE_ARGS
}

init_compose_files

compose(){
  docker compose --project-name "$PROJECT_NAME" "${COMPOSE_FILE_ARGS[@]}" "$@"
}

show_header(){
  echo -e "\n${BLUE}    🛠️  TOOLING DEPLOYMENT  🛠️${NC}"
  echo -e "${BLUE}    ═══════════════════════════${NC}"
  echo -e "${BLUE}        📊 Enabling Management UIs 📊${NC}\n"
}

ensure_command(){
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found in PATH."
    exit 1
  fi
}

ensure_mysql_running(){
  local mysql_service="ac-mysql"
  local mysql_container
  mysql_container="$(read_env CONTAINER_MYSQL "ac-mysql")"
  if docker ps --format '{{.Names}}' | grep -qx "$mysql_container"; then
    info "MySQL container '$mysql_container' already running."
    return
  fi
  info "Starting database service '$mysql_service'..."
  compose --profile db up -d "$mysql_service" >/dev/null
  ok "Database service ready."
}

start_tools(){
  info "Starting phpMyAdmin and Keira3..."
  compose --profile tools up --detach --quiet-pull >/dev/null
  ok "Tooling services are online."
}

show_endpoints(){
  local pma_port keira_port
  pma_port="$(read_env PMA_EXTERNAL_PORT 8081)"
  keira_port="$(read_env KEIRA3_EXTERNAL_PORT 4201)"
  echo ""
  echo -e "${GREEN}Accessible endpoints:${NC}"
  echo "  • phpMyAdmin : http://localhost:${pma_port}"
  echo "  • Keira3     : http://localhost:${keira_port}"
  echo ""
}

main(){
  if [[ "${1:-}" == "--help" ]]; then
    cat <<EOF
Usage: $(basename "$0")

Ensures the database service is running and launches the tooling profile
containing phpMyAdmin and Keira3 dashboards.
EOF
    exit 0
  fi

  ensure_command docker
  docker info >/dev/null 2>&1 || { err "Docker daemon unavailable."; exit 1; }

  PROJECT_NAME="$(resolve_project_name)"

  show_header
  ensure_mysql_running
  start_tools
  show_endpoints
}

main "$@"

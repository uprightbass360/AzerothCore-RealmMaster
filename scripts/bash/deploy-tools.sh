#!/bin/bash

# azerothcore-rm helper to deploy phpMyAdmin and Keira3 tooling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"
TEMPLATE_FILE="$ROOT_DIR/.env.template"
ENV_PATH="$ENV_FILE"
DEFAULT_ENV_PATH="$ENV_FILE"
source "$ROOT_DIR/scripts/bash/project_name.sh"
source "$ROOT_DIR/scripts/bash/lib/common.sh"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"
source "$ROOT_DIR/scripts/bash/compose_overrides.sh"
declare -a COMPOSE_FILE_ARGS=()

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

  require_cmd docker
  docker info >/dev/null 2>&1 || { err "Docker daemon unavailable."; exit 1; }

  PROJECT_NAME="$(resolve_project_name)"

  show_header
  ensure_mysql_running
  start_tools
  show_endpoints
}

main "$@"

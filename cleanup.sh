#!/bin/bash

# ==============================================
# ac-compose Cleanup Script (project-scoped)
# ==============================================
# Usage: ./cleanup.sh [--soft] [--hard] [--nuclear] [--dry-run] [--force] [--preserve-backups]
# Project: ac-compose

set -e

# Resolve project dir and compose
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
COMPOSE_FILE="${PROJECT_DIR}/compose.yml"
ENV_FILE="${PROJECT_DIR}/.env"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'

print_status() {
  case "$1" in
    INFO)    echo -e "${BLUE}ℹ️  ${2}${NC}";;
    SUCCESS) echo -e "${GREEN}✅ ${2}${NC}";;
    WARNING) echo -e "${YELLOW}⚠️  ${2}${NC}";;
    ERROR)   echo -e "${RED}❌ ${2}${NC}";;
    DANGER)  echo -e "${RED}💀 ${2}${NC}";;
    HEADER)  echo -e "\n${MAGENTA}=== ${2} ===${NC}";;
  esac
}

usage(){
  cat <<EOF
Usage: $0 [CLEANUP_LEVEL] [OPTIONS]

CLEANUP LEVELS:
  --soft             Stop project containers (preserves data)
  --hard             Remove containers + networks (preserves volumes/images)
  --nuclear          Complete removal: containers, networks, volumes, images (DESTROYS DATA)

OPTIONS:
  --dry-run          Show actions without executing
  --force            Skip confirmation prompts
  --preserve-backups Keep backups when nuking storage (moves them aside and restores)
  -h, --help         Show this help
EOF
}

# Flags
CLEANUP_LEVEL=""
DRY_RUN=false
FORCE=false
PRESERVE_BACKUPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --soft|--hard|--nuclear) CLEANUP_LEVEL="${1#--}"; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --force) FORCE=true; shift;;
    --preserve-backups) PRESERVE_BACKUPS=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

execute_command() {
  local description="$1"; shift
  local cmd="$*"
  if $DRY_RUN; then
    print_status INFO "[DRY RUN] $description"
    echo "  $cmd"
  else
    print_status INFO "$description"
    eval "$cmd" || print_status WARNING "Command failed or no action needed"
  fi
}

confirm() {
  local msg="$1"
  if $FORCE; then
    print_status INFO "Force enabled; skipping confirmation"
    return 0
  fi
  echo -e "${YELLOW}⚠️  ${msg}${NC}"
  read -p "Are you sure? (yes/no): " ans
  [[ "$ans" =~ ^(yes|y|YES|Y)$ ]] || { print_status INFO "Cancelled"; exit 0; }
}

show_resources() {
  print_status HEADER "CURRENT PROJECT RESOURCES"
  echo -e "${BLUE}Containers:${NC}"
  docker compose -f "$COMPOSE_FILE" ps -a || true
  echo -e "${BLUE}Networks:${NC}"
  docker network ls --format 'table {{.Name}}\t{{.Driver}}' | grep -E "(^|\s)$(grep -oE '^NETWORK_NAME=.+$' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo 'azerothcore')($|\s)" || true
  echo -e "${BLUE}Volumes:${NC}"
  docker volume ls --format 'table {{.Name}}\t{{.Driver}}' | grep -E 'ac_|acore|azerothcore' || true
}

# Load env for STORAGE_PATH etc.
STORAGE_PATH_DEFAULT="${PROJECT_DIR}/storage"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi
STORAGE_PATH="${STORAGE_PATH:-$STORAGE_PATH_DEFAULT}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ac-compose}"

remove_storage_dir(){
  local path="$1"
  if [ -d "$path" ]; then
    rm -rf "$path" 2>/dev/null || sudo rm -rf "$path" 2>/dev/null || true
  fi
}

remove_project_volumes(){
  docker volume ls --format '{{.Name}}' \
    | grep -E "^${PROJECT_NAME}|^azerothcore" \
    | xargs -r docker volume rm >/dev/null 2>&1 || true
}

soft_cleanup() {
  print_status HEADER "SOFT CLEANUP - Stop runtime stack"
  confirm "This will stop all project containers (data preserved)."
  local profiles=(
    --profile services-standard
    --profile services-playerbots
    --profile services-modules
    --profile client-data
    --profile client-data-bots
    --profile modules
    --profile tools
    --profile db
  )
  execute_command "Stopping runtime profiles" docker compose -f "$COMPOSE_FILE" "${profiles[@]}" down
  print_status SUCCESS "Soft cleanup complete"
}

hard_cleanup() {
  print_status HEADER "HARD CLEANUP - Remove containers + networks"
  confirm "This will remove containers and networks (volumes/images preserved)."
  local profiles=(
    --profile services-standard
    --profile services-playerbots
    --profile services-modules
    --profile client-data
    --profile client-data-bots
    --profile modules
    --profile tools
    --profile db
  )
  execute_command "Removing containers and networks" docker compose -f "$COMPOSE_FILE" "${profiles[@]}" down --remove-orphans
  execute_command "Remove project volumes" remove_project_volumes
  # Remove straggler containers matching project name (defensive)
  execute_command "Remove stray project containers" "docker ps -a --format '{{.Names}}' | grep -E '^ac-' | xargs -r docker rm -f"
  # Remove project network if present and not automatically removed
  if [ -n "${NETWORK_NAME:-}" ]; then
    execute_command "Remove project network ${NETWORK_NAME}" "docker network rm ${NETWORK_NAME} 2>/dev/null || true"
  fi
  print_status SUCCESS "Hard cleanup complete"
}

nuclear_cleanup() {
  print_status HEADER "NUCLEAR CLEANUP - COMPLETE REMOVAL"
  print_status DANGER "THIS WILL DESTROY ALL PROJECT DATA"
  confirm "Proceed with complete removal?"

  # Down with volumes
  local profiles=(
    --profile services-standard
    --profile services-playerbots
    --profile services-modules
    --profile client-data
    --profile client-data-bots
    --profile modules
    --profile tools
    --profile db
  )
  execute_command "Removing containers, networks and volumes" docker compose -f "$COMPOSE_FILE" "${profiles[@]}" down --volumes --remove-orphans
  execute_command "Remove leftover volumes" remove_project_volumes

  # Remove project images (server/tool images typical to this project)
  execute_command "Remove acore images" "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^acore/' | xargs -r docker rmi"
  execute_command "Remove playerbots images" "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^uprightbass360/azerothcore-wotlk-playerbots' | xargs -r docker rmi"
  execute_command "Remove tool images" "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'phpmyadmin|uprightbass360/keira3' | xargs -r docker rmi"

  # Storage cleanup (preserve backups if requested)
  if $PRESERVE_BACKUPS; then
    print_status INFO "Preserving backups under ${STORAGE_PATH}/backups"
    TMP_PRESERVE="${PROJECT_DIR}/.preserve-backups"
    if [ -d "${STORAGE_PATH}/backups" ]; then
      execute_command "Staging backups" "mkdir -p '${TMP_PRESERVE}' && cp -a '${STORAGE_PATH}/backups' '${TMP_PRESERVE}/'"
    fi
    execute_command "Removing storage" "remove_storage_dir '${STORAGE_PATH}'"
    if [ -d "${TMP_PRESERVE}/backups" ]; then
      execute_command "Restoring backups" "mkdir -p '${STORAGE_PATH}' && mv '${TMP_PRESERVE}/backups' '${STORAGE_PATH}/backups' && rm -rf '${TMP_PRESERVE}'"
      print_status SUCCESS "Backups preserved at ${STORAGE_PATH}/backups"
    fi
  else
    execute_command "Removing storage and local backups" "remove_storage_dir '${STORAGE_PATH}'; remove_storage_dir '${PROJECT_DIR}/backups'"
  fi

  # Optional system prune for project context
  execute_command "Docker system prune (dangling)" "docker system prune -af --volumes"
  print_status SUCCESS "Nuclear cleanup completed"
}

show_summary() {
  local lvl="$1"
  print_status HEADER "CLEANUP SUMMARY"
  case "$lvl" in
    soft)
      echo -e "${GREEN}✅ Containers: Stopped${NC}"; echo -e "${BLUE}ℹ️  Networks/Volumes/Images: Preserved${NC}";;
    hard)
      echo -e "${GREEN}✅ Containers/Networks: Removed${NC}"; echo -e "${BLUE}ℹ️  Volumes/Images: Preserved${NC}";;
    nuclear)
      echo -e "${RED}💀 Containers/Networks/Volumes/Images: DESTROYED${NC}";;
  esac
}

main(){
  print_status HEADER "ac-compose CLEANUP"

  if ! command -v docker >/dev/null 2>&1; then
    print_status ERROR "Docker not found"
    exit 1
  fi
  if [ ! -f "$COMPOSE_FILE" ]; then
    print_status ERROR "Compose file not found at $COMPOSE_FILE"
    exit 1
  fi
  if [ -z "$CLEANUP_LEVEL" ]; then
    usage; exit 1
  fi

  show_resources

  case "$CLEANUP_LEVEL" in
    soft)   soft_cleanup;;
    hard)   hard_cleanup;;
    nuclear) nuclear_cleanup;;
    *) usage; exit 1;;
  esac

  show_summary "$CLEANUP_LEVEL"
  print_status SUCCESS "🧹 Cleanup completed"
}

main "$@"

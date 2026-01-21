#!/bin/bash
# Project: azerothcore-rm
set -e

# Simple profile-aware deploy + health check for profiles-verify/docker-compose.yml

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
ENV_FILE=""
TEMPLATE_FILE="$PROJECT_DIR/.env.template"
source "$PROJECT_DIR/scripts/bash/project_name.sh"
source "$PROJECT_DIR/scripts/bash/compose_overrides.sh"
source "$PROJECT_DIR/scripts/bash/lib/common.sh"
PROFILES=(db services-standard client-data modules tools)
SKIP_DEPLOY=false
QUICK=false

usage(){
  cat <<EOF
Usage: $0 [--profiles p1,p2,...] [--env-file path] [--skip-deploy] [--quick]
Default profiles: db,services-standard,client-data,modules,tools
Examples:
  $0 --profiles db,services-standard,client-data --env-file ./services.env
  $0 --profiles db,services-playerbots,client-data-bots,modules,tools
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profiles) IFS=',' read -r -a PROFILES <<< "$2"; shift 2;;
    --env-file) ENV_FILE="$2"; shift 2;;
    --skip-deploy) SKIP_DEPLOY=true; shift;;
    --quick) QUICK=true; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 1;;
  esac
done

resolve_project_name(){
  local env_path
  if [ -n "$ENV_FILE" ]; then
    env_path="$ENV_FILE"
  else
    env_path="$(dirname "$COMPOSE_FILE")/.env"
  fi
  local raw_name
  raw_name="$(project_name::resolve "$env_path" "$TEMPLATE_FILE")"
  local sanitized
  sanitized="$(echo "$raw_name" | tr '[:upper:]' '[:lower:]')"
  sanitized="${sanitized// /-}"
  sanitized="$(echo "$sanitized" | tr -cd 'a-z0-9_-')"
  if [[ -z "$sanitized" ]]; then
    echo "Error: COMPOSE_PROJECT_NAME is invalid" >&2
    exit 1
  fi
  if [[ ! "$sanitized" =~ ^[a-z0-9] ]]; then
    sanitized="ac${sanitized}"
  fi
  echo "$sanitized"
}

run_compose(){
  local compose_args=()
  local project_name
  project_name="$(resolve_project_name)"
  compose_args+=(--project-name "$project_name")
  if [ -n "$ENV_FILE" ]; then
    compose_args+=(--env-file "$ENV_FILE")
  fi
  compose_args+=(-f "$COMPOSE_FILE")
  local env_path
  env_path="$(env_file_path)"
  declare -a enabled_overrides=()
  compose_overrides::list_enabled_files "$PROJECT_DIR" "$env_path" enabled_overrides
  for file in "${enabled_overrides[@]}"; do
    compose_args+=(-f "$file")
  done
  docker compose "${compose_args[@]}" "$@"
}

env_file_path(){
  if [ -n "$ENV_FILE" ]; then
    echo "$ENV_FILE"
  else
    echo "$(dirname "$COMPOSE_FILE")/.env"
  fi
}

read_env_value(){
  local key="$1" default="${2:-}"
  local env_path value
  env_path="$(env_file_path)"
  if [ -f "$env_path" ]; then
    value="$(grep -E "^${key}=" "$env_path" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  # Fallback to template defaults if not set in the chosen env file
  if [ -z "$value" ] && [ -f "$TEMPLATE_FILE" ]; then
    value="$(grep -E "^${key}=" "$TEMPLATE_FILE" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

MYSQL_EXTERNAL_PORT="$(read_env_value MYSQL_EXTERNAL_PORT 64306)"
AUTH_EXTERNAL_PORT="$(read_env_value AUTH_EXTERNAL_PORT 3784)"
WORLD_EXTERNAL_PORT="$(read_env_value WORLD_EXTERNAL_PORT 8215)"
SOAP_EXTERNAL_PORT="$(read_env_value SOAP_EXTERNAL_PORT 7778)"
PMA_EXTERNAL_PORT="$(read_env_value PMA_EXTERNAL_PORT 8081)"
KEIRA3_EXTERNAL_PORT="$(read_env_value KEIRA3_EXTERNAL_PORT 4201)"

handle_auto_rebuild(){
  local storage_path
  storage_path="$(read_env_value STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$storage_path" != /* ]]; then
    # Remove leading ./ if present
    storage_path="${storage_path#./}"
    storage_path="$(dirname "$COMPOSE_FILE")/$storage_path"
  fi
  local sentinel="$storage_path/modules/.requires_rebuild"
  [ -f "$sentinel" ] || return 0

  info "Module rebuild required (detected $(realpath "$sentinel" 2>/dev/null || echo "$sentinel"))."
  local auto_rebuild
  auto_rebuild="$(read_env_value AUTO_REBUILD_ON_DEPLOY "0")"
  if [ "$auto_rebuild" != "1" ]; then
    warn "Run ./scripts/bash/rebuild-with-modules.sh after preparing your source tree."
    return 0
  fi

  local rebuild_source
  rebuild_source="$(read_env_value MODULES_REBUILD_SOURCE_PATH "")"
  info "AUTO_REBUILD_ON_DEPLOY=1; invoking ./scripts/bash/rebuild-with-modules.sh."
  local cmd=(./scripts/bash/rebuild-with-modules.sh --yes)
  if [ -n "$rebuild_source" ]; then
    cmd+=(--source "$rebuild_source")
  fi
  if "${cmd[@]}"; then
    info "Module rebuild completed."
  else
    warn "Automatic rebuild failed; run ./scripts/bash/rebuild-with-modules.sh manually."
  fi
}

check_health(){
  local name="$1"
  local status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "no-health-check")
  if [ "$status" = "healthy" ]; then ok "$name: healthy"; return 0; fi
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then ok "$name: running"; return 0; fi
  err "$name: not running"; return 1
}

wait_log(){
  local name="$1"; local needle="$2"; local attempts="${3:-360}"; local interval=5
  info "Waiting for $name log: '$needle' ... (timeout: $((attempts*interval))s)"
  for i in $(seq 1 "$attempts"); do
    if docker logs "$name" 2>/dev/null | grep -q "$needle"; then ok "$name ready"; return 0; fi
    sleep "$interval"
  done
  warn "$name did not report '$needle'"
  return 1
}

deploy(){
  info "Deploying profiles: ${PROFILES[*]}"
  local args=()
  for p in "${PROFILES[@]}"; do args+=(--profile "$p"); done
  run_compose "${args[@]}" up -d
}

health_checks(){
  info "Checking container health"
  local failures=0
  check_health ac-mysql || ((failures++))
  check_health ac-authserver || ((failures++))
  check_health ac-worldserver || ((failures++))
  if [ "$QUICK" = false ]; then
    info "Port checks"
    for port in "$MYSQL_EXTERNAL_PORT" "$AUTH_EXTERNAL_PORT" "$WORLD_EXTERNAL_PORT" "$SOAP_EXTERNAL_PORT" "$PMA_EXTERNAL_PORT" "$KEIRA3_EXTERNAL_PORT"; do
      if timeout 3 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then ok "port $port: open"; else warn "port $port: closed"; fi
    done
  fi
  if [ $failures -eq 0 ]; then ok "All core services healthy"; else err "$failures service checks failed"; return 1; fi
}

main(){
  if [ "$SKIP_DEPLOY" = false ]; then
    deploy
    # Wait for client-data completion if profile active
    if printf '%s\n' "${PROFILES[@]}" | grep -q '^client-data$\|^client-data-bots$'; then
      wait_log ac-client-data "Game data setup complete" || true
    fi
    # Give worldserver time to boot
    sleep 10
  fi
  health_checks
  handle_auto_rebuild
  info "Endpoints: MySQL:${MYSQL_EXTERNAL_PORT}, Auth:${AUTH_EXTERNAL_PORT}, World:${WORLD_EXTERNAL_PORT}, SOAP:${SOAP_EXTERNAL_PORT}, phpMyAdmin:${PMA_EXTERNAL_PORT}, Keira3:${KEIRA3_EXTERNAL_PORT}"
}

main "$@"

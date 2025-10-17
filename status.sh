#!/bin/bash
# ac-compose condensed status view

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
ENV_FILE="$PROJECT_DIR/.env"

cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

WATCH_MODE=false
LOG_LINES=5
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch|-w) WATCH_MODE=true; shift;;
    --logs|-l) SHOW_LOGS=true; shift;;
    --lines) LOG_LINES="$2"; shift 2;;
    -h|--help)
      cat <<EOF
ac-compose status

Usage: $0 [options]
  -w, --watch        Continuously refresh every 3s
  -l, --logs         Show trailing logs for each service
      --lines N      Number of log lines when --logs is used (default 5)
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "Docker CLI not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon unavailable" >&2; exit 1; }

read_env(){
  local key="$1" default="$2" value
  if [ -f "$ENV_FILE" ]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

PROJECT_NAME="$(read_env COMPOSE_PROJECT_NAME ac-compose)"
NETWORK_NAME="$(read_env NETWORK_NAME azerothcore)"
AUTH_PORT="$(read_env AUTH_EXTERNAL_PORT 3784)"
WORLD_PORT="$(read_env WORLD_EXTERNAL_PORT 8215)"
SOAP_PORT="$(read_env SOAP_EXTERNAL_PORT 7778)"
MYSQL_PORT="$(read_env MYSQL_EXTERNAL_PORT 64306)"
PMA_PORT="$(read_env PMA_EXTERNAL_PORT 8081)"
KEIRA_PORT="$(read_env KEIRA3_EXTERNAL_PORT 4201)"
ELUNA_ENABLED="$(read_env AC_ELUNA_ENABLED 1)"

container_exists(){
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

container_running(){
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

format_state(){
  local status="$1" health="$2" started="$3" exit_code="$4"
  case "$status" in
    running)
      local desc="running" colour="$GREEN"
      if [ "$health" = "healthy" ]; then
        desc="healthy"
      elif [ "$health" = "none" ]; then
        desc="running"
      else
        desc="$health"; colour="$YELLOW"
        [ "$health" = "unhealthy" ] && colour="$RED"
      fi
      echo -e "${colour}●${NC} ${desc} (since ${started%:*})"
      ;;
    exited)
      local colour="$YELLOW"
      [ "$exit_code" != "0" ] && colour="$RED"
      echo -e "${colour}○${NC} completed"
      ;;
    restarting)
      echo -e "${YELLOW}●${NC} restarting"
      ;;
    created)
      echo -e "${CYAN}○${NC} created"
      ;;
    *)
      echo -e "${RED}○${NC} $status"
      ;;
  esac
}

short_image(){
  local img="$1"
  if [[ "$img" != */* ]]; then
    echo "$img"
    return
  fi
  local repo="${img%%/*}"
  local rest="${img#*/}"
  local name="${rest%%:*}"
  local tag="${img##*:}"
  local has_tag="true"
  [[ "$img" != *":"* ]] && has_tag="false"
  local last="${name##*/}"
  if [ "$has_tag" = "true" ]; then
    if [[ "$tag" =~ ^[0-9] ]] || [ "$tag" = "latest" ]; then
      echo "$repo/$last"
    else
      echo "$repo/$tag"
    fi
  else
    echo "$repo/$last"
  fi
}

print_service(){
  local container="$1" label="$2"
  if container_exists "$container"; then
    local status health started exit_code image
    status="$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")"
    health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "none")"
    started="$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | cut -c12-19 2>/dev/null || echo "--:--:--")"
    exit_code="$(docker inspect --format='{{.State.ExitCode}}' "$container" 2>/dev/null || echo "?")"
    image="$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null || echo "-")"
    printf "%-20s %-28s %s\n" "$label" "$(format_state "$status" "$health" "$started" "$exit_code")" "$(short_image "$image")"
    if [ "$SHOW_LOGS" = true ]; then
      docker logs "$container" --tail "$LOG_LINES" 2>/dev/null | sed 's/^/    /' || printf "    (no logs available)\n"
    fi
  else
    printf "%-20s ${RED}○${NC} missing               -\n" "$label"
  fi
}

module_summary(){
  if [ ! -f "$ENV_FILE" ]; then
    echo "MODULES: (env not found)"
    return
  fi
  local module_vars
  module_vars="$(grep -E '^MODULE_[A-Z_]+=1' "$ENV_FILE" 2>/dev/null | cut -d'=' -f1)"
  if [ -n "$module_vars" ]; then
    local arr=()
    while IFS= read -r mod; do
      [ -z "$mod" ] && continue
      local pretty="${mod#MODULE_}"
      pretty="$(echo "$pretty" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')"
      arr+=("$pretty")
    done <<< "$module_vars"
    local joined=""
    for item in "${arr[@]}"; do
      joined+="$item, "
    done
    joined="${joined%, }"
    echo "MODULES: $joined"
  else
    echo "MODULES: none"
  fi

  if container_running "ac-worldserver"; then
    local ws_image="$(docker inspect --format='{{.Config.Image}}' ac-worldserver 2>/dev/null || echo "")"
    local playerbot="disabled"
    [[ "$ws_image" == *playerbots* ]] && playerbot="running"
    local eluna="disabled"
    [ "$ELUNA_ENABLED" = "1" ] && eluna="running"
    echo "RUNTIME: playerbots $playerbot | eluna $eluna"
  fi
}

ports_summary(){
  local names=("Auth" "World" "SOAP" "MySQL" "phpMyAdmin" "Keira3")
  local ports=("$AUTH_PORT" "$WORLD_PORT" "$SOAP_PORT" "$MYSQL_PORT" "$PMA_PORT" "$KEIRA_PORT")
  printf "PORTS:\n"
  for i in "${!names[@]}"; do
    local svc="${names[$i]}"
    local port="${ports[$i]}"
    if timeout 1 bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1; then
      printf "  %-10s %-6s %b●%b reachable\n" "$svc" "$port" "$GREEN" "$NC"
    else
      printf "  %-10s %-6s %b○%b unreachable\n" "$svc" "$port" "$RED" "$NC"
    fi
  done
}

network_summary(){
  if docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
    echo "DOCKER NET: $NETWORK_NAME"
  else
    echo "DOCKER NET: missing ($NETWORK_NAME)"
  fi
}

print_status(){
  clear 2>/dev/null || printf '\033[2J\033[H'
  printf "TIME %s  PROJECT %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$PROJECT_NAME"
  printf "%-20s %-28s %s\n" "SERVICE" "STATE" "IMAGE"
  printf "%-20s %-28s %s\n" "--------------------" "----------------------------" "------------------------------"
  print_service ac-mysql "MySQL"
  print_service ac-backup "Backup"
  print_service ac-db-init "DB Init"
  print_service ac-db-import "DB Import"
  print_service ac-authserver "Auth Server"
  print_service ac-worldserver "World Server"
  print_service ac-client-data "Client Data"
  print_service ac-modules "Module Manager"
  print_service ac-post-install "Post Install"
  print_service ac-phpmyadmin "phpMyAdmin"
  print_service ac-keira3 "Keira3"
  echo ""
  module_summary
  echo ""
  echo "$(ports_summary)"
  echo "$(network_summary)"
}

if [ "$WATCH_MODE" = true ]; then
  while true; do
    print_status
    sleep 3
  done
else
  print_status
fi

#!/bin/bash
# ac-compose condensed realm status view

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
ENV_FILE="$PROJECT_DIR/.env"

cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'

WATCH_MODE=true
LOG_LINES=5
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch|-w) WATCH_MODE=true; shift;;
    --once) WATCH_MODE=false; shift;;
    --logs|-l) SHOW_LOGS=true; shift;;
    --lines) LOG_LINES="$2"; shift 2;;
    -h|--help)
      cat <<EOF
ac-compose realm status

Usage: $0 [options]
  -w, --watch        Continuously refresh every 3s (default)
      --once         Show a single snapshot then exit
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
  local key="$1" value=""
  if [ -f "$ENV_FILE" ]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  echo "$value"
}

PROJECT_NAME="$(read_env COMPOSE_PROJECT_NAME)"
NETWORK_NAME="$(read_env NETWORK_NAME)"
AUTH_PORT="$(read_env AUTH_EXTERNAL_PORT)"
WORLD_PORT="$(read_env WORLD_EXTERNAL_PORT)"
SOAP_PORT="$(read_env SOAP_EXTERNAL_PORT)"
MYSQL_PORT="$(read_env MYSQL_EXTERNAL_PORT)"
PMA_PORT="$(read_env PMA_EXTERNAL_PORT)"
KEIRA_PORT="$(read_env KEIRA3_EXTERNAL_PORT)"
ELUNA_ENABLED="$(read_env AC_ELUNA_ENABLED)"

container_exists(){
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

container_running(){
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

is_one_shot(){
  case "$1" in
    ac-db-import|ac-db-init|ac-modules|ac-post-install|ac-client-data|ac-client-data-playerbots)
      return 0;;
    *)
      return 1;;
  esac
}

format_state(){
  local status="$1" health="$2" started="$3" exit_code="$4"
  local started_fmt
  if [ -n "$started" ] && [[ "$started" != "--:--:--" ]]; then
    started_fmt="$(date -d "$started" '+%H:%M:%S' 2>/dev/null || echo "")"
    if [ -z "$started_fmt" ]; then
      started_fmt="$(echo "$started" | cut -c12-19)"
    fi
    [ -z "$started_fmt" ] && started_fmt="--:--:--"
  else
    started_fmt="--:--:--"
  fi
  case "$status" in
    running)
      local desc="running (since $started_fmt)" colour="$GREEN"
      if [ "$health" = "healthy" ]; then
        desc="healthy (since $started_fmt)"
      elif [ "$health" = "none" ]; then
        desc="running (since $started_fmt)"
      else
        desc="$health (since $started_fmt)"; colour="$YELLOW"
        [ "$health" = "unhealthy" ] && colour="$RED"
      fi
      echo "${colour}|● ${desc}"
      ;;
    exited)
      local colour="$YELLOW"
      [ "$exit_code" != "0" ] && colour="$RED"
      echo "${colour}|○ exited (code $exit_code)"
      ;;
    restarting)
      echo "${YELLOW}|● restarting"
      ;;
    created)
      echo "${CYAN}|○ created"
      ;;
    *)
      echo "${RED}|○ $status"
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
    local state_info colour text
    if [ "$status" = "exited" ] && is_one_shot "$container"; then
      local finished
      finished="$(docker inspect --format='{{.State.FinishedAt}}' "$container" 2>/dev/null | cut -c12-19 2>/dev/null || echo "--:--:--")"
      if [ "$exit_code" = "0" ]; then
        state_info="${GREEN}|○ completed (at $finished)"
      else
        state_info="${RED}|○ failed (code $exit_code)"
      fi
    else
      state_info="$(format_state "$status" "$health" "$started" "$exit_code")"
    fi
    colour="${state_info%%|*}"
    text="${state_info#*|}"
    printf "%-20s %-15s %b%-30s%b %s\n" "$label" "$container" "$colour" "$text" "$NC" "$(short_image "$image")"
    if [ "$SHOW_LOGS" = true ]; then
      docker logs "$container" --tail "$LOG_LINES" 2>/dev/null | sed 's/^/    /' || printf "    (no logs available)\n"
    fi
  else
    printf "%-20s %-15s %b%-30s%b %s\n" "$label" "$container" "$RED" "○ missing" "$NC" "-"
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
    local playerbot="disabled"
    local module_playerbots
    module_playerbots="$(read_env MODULE_PLAYERBOTS)"
    if [ "$module_playerbots" = "1" ]; then
      playerbot="enabled"
      if docker inspect --format='{{.State.Status}}' ac-worldserver 2>/dev/null | grep -q "running"; then
        playerbot="running"
      fi
    fi
    local eluna="disabled"
    [ "$ELUNA_ENABLED" = "1" ] && eluna="running"
    echo "RUNTIME: playerbots $playerbot | eluna $eluna"
  fi
}

user_stats(){
  if ! container_running "ac-mysql"; then
    printf "USERS: %sDatabase offline%s\n" "$RED" "$NC"
    return
  fi

  local mysql_pw db_auth db_characters
  mysql_pw="$(read_env MYSQL_ROOT_PASSWORD)"
  db_auth="$(read_env DB_AUTH_NAME)"
  db_characters="$(read_env DB_CHARACTERS_NAME)"

  if [ -z "$mysql_pw" ] || [ -z "$db_auth" ] || [ -z "$db_characters" ]; then
    printf "USERS: %sMissing MySQL configuration in .env%s\n" "$YELLOW" "$NC"
    return
  fi

  local exec_mysql
  exec_mysql(){
    local database="$1" query="$2"
    docker exec ac-mysql mysql -N -B -u root -p"${mysql_pw}" "$database" -e "$query" 2>/dev/null | tail -n1
  }

  local account_total account_online character_total last_week
  account_total="$(exec_mysql "$db_auth" "SELECT COUNT(*) FROM account;")"
  account_online="$(exec_mysql "$db_auth" "SELECT COUNT(*) FROM account WHERE online = 1;")"
  character_total="$(exec_mysql "$db_characters" "SELECT COUNT(*) FROM characters;")"
  last_week="$(exec_mysql "$db_auth" "SELECT COUNT(*) FROM account WHERE last_login >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY);")"

  [[ -z "$account_total" ]] && account_total="0"
  [[ -z "$account_online" ]] && account_online="0"
  [[ -z "$character_total" ]] && character_total="0"
  [[ -z "$last_week" ]] && last_week="0"

  printf "USERS: Accounts %b%s%b | Online %b%s%b | Characters %b%s%b | Active 7d %b%s%b\n" \
    "$GREEN" "$account_total" "$NC" \
    "$YELLOW" "$account_online" "$NC" \
    "$CYAN" "$character_total" "$NC" \
    "$BLUE" "$last_week" "$NC"
}

ports_summary(){
  local names=("Auth" "World" "SOAP" "MySQL" "phpMyAdmin" "Keira3")
  local ports=("$AUTH_PORT" "$WORLD_PORT" "$SOAP_PORT" "$MYSQL_PORT" "$PMA_PORT" "$KEIRA_PORT")
  printf "PORTS:\n"
  for i in "${!names[@]}"; do
    local svc="${names[$i]}"
    local port="${ports[$i]}"
    if [ -z "$port" ]; then
      printf "  %-10s %-6s %b○%b not set\n" "$svc" "--" "$YELLOW" "$NC"
      continue
    fi
    if timeout 1 bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1; then
      printf "  %-10s %-6s %b●%b reachable\n" "$svc" "$port" "$GREEN" "$NC"
    else
      printf "  %-10s %-6s %b○%b unreachable\n" "$svc" "$port" "$RED" "$NC"
    fi
  done
}

network_summary(){
  if [ -z "$NETWORK_NAME" ]; then
    echo "DOCKER NET: not set"
    return
  fi
  if docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
    echo "DOCKER NET: $NETWORK_NAME"
  else
    echo "DOCKER NET: missing ($NETWORK_NAME)"
  fi
}

show_realm_status_header(){
  echo -e "${BLUE}🏰 REALM STATUS DASHBOARD 🏰${NC}"
  echo -e "${BLUE}═══════════════════════════${NC}"
}

render_snapshot(){
  show_realm_status_header
  printf "\nTIME %s  PROJECT %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$PROJECT_NAME"
  printf "%-20s %-15s %-28s %s\n" "SERVICE" "CONTAINER" "STATE" "IMAGE"
  printf "%-20s %-15s %-28s %s\n" "--------------------" "---------------" "----------------------------" "------------------------------"
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
  user_stats
  echo ""
  echo "$(ports_summary)"
  echo "$(network_summary)"
}

display_snapshot(){
  local tmp
  tmp="$(mktemp)"
  render_snapshot >"$tmp"
  clear 2>/dev/null || printf '\033[2J\033[H'
  cat "$tmp"
  rm -f "$tmp"
}

if [ "$WATCH_MODE" = true ]; then
  while true; do
    display_snapshot
    sleep 3
  done
else
  display_snapshot
fi

#!/bin/bash
#
# High-level orchestrator for module-aware deployments.
# 1. Ensures AzerothCore source repo is present
# 2. Runs ac-modules to sync/clean module checkout and configs
# 3. Rebuilds source images when C++ modules demand it
# 4. Stages target compose profile and optionally tails worldserver logs

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_PATH="$ROOT_DIR/.env"
TARGET_PROFILE=""
WATCH_LOGS=1
KEEP_RUNNING=0
SKIP_REBUILD=0
WORLD_LOG_SINCE=""
ASSUME_YES=0

COMPILE_MODULE_VARS=(
  MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE
  MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS
  MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD
  MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER
  MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT MODULE_ARAC MODULE_ASSISTANT MODULE_REAGENT_BANK
  MODULE_CHALLENGE_MODES MODULE_OLLAMA_CHAT MODULE_PLAYER_BOT_LEVEL_BRACKETS MODULE_STATBOOSTER MODULE_DUNGEON_RESPAWN
  MODULE_SKELETON_MODULE MODULE_BG_SLAVERYVALLEY MODULE_AZEROTHSHARD MODULE_WORGOBLIN
)

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ printf '%b\n' "${BLUE}ℹ️  $*${NC}"; }
ok(){ printf '%b\n' "${GREEN}✅ $*${NC}"; }
warn(){ printf '%b\n' "${YELLOW}⚠️  $*${NC}"; }
err(){ printf '%b\n' "${RED}❌ $*${NC}"; }

show_deployment_header(){
  printf '\n%b\n' "${BLUE}⚔️  AZEROTHCORE REALM DEPLOYMENT  ⚔️${NC}"
  printf '%b\n' "${BLUE}════════════════════════════════════════${NC}"
  printf '%b\n\n' "${BLUE}🏰 Bringing Your Realm Online 🏰${NC}"
}

show_step(){
  local step="$1" total="$2" message="$3"
  printf '%b\n' "${YELLOW}🔧 Step ${step}/${total}: ${message}...${NC}"
}

show_realm_ready(){
  printf '\n%b\n' "${GREEN}⚔️ The realm has been forged! ⚔️${NC}"
  printf '%b\n' "${GREEN}🏰 Adventurers may now enter your world${NC}"
  printf '%b\n\n' "${GREEN}🗡️ May your server bring epic adventures!${NC}"
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile {standard|playerbots|modules}  Force target profile (default: auto-detect)
  --no-watch                               Do not tail worldserver logs after staging
  --keep-running                           Do not pre-stop runtime stack before rebuild
  --skip-rebuild                           Skip source rebuild even if modules require it
  --yes, -y                                Auto-confirm deployment and rebuild prompts
  --watch-logs                             Tail worldserver logs even if --no-watch was set earlier
  --log-tail LINES                         Override WORLD_LOG_TAIL (number of log lines to show)
  --once                                   Run status checks once (alias for --no-watch)
  -h, --help                               Show this help

This command automates the module workflow: sync modules, rebuild source if needed,
stage the correct compose profile, and optionally watch worldserver logs.

Rebuild Detection:
The script automatically detects when a module rebuild is required by checking:
• Module changes (sentinel file .requires_rebuild)
• C++ modules enabled but modules-latest Docker images missing

Set AUTO_REBUILD_ON_DEPLOY=1 in .env to skip rebuild prompts and auto-rebuild.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) TARGET_PROFILE="$2"; shift 2;;
    --no-watch) WATCH_LOGS=0; shift;;
    --keep-running) KEEP_RUNNING=1; shift;;
    --skip-rebuild) SKIP_REBUILD=1; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

require_cmd(){
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

require_cmd docker

read_env(){
  local key="$1" default="${2:-}"
  local value=""
  if [ -f "$ENV_PATH" ]; then
    value="$(grep -E "^${key}=" "$ENV_PATH" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

resolve_project_name(){
  local raw_name="$(read_env COMPOSE_PROJECT_NAME "acore-compose")"
  local sanitized
  sanitized="$(echo "$raw_name" | tr '[:upper:]' '[:lower:]')"
  sanitized="${sanitized// /-}"
  sanitized="$(echo "$sanitized" | tr -cd 'a-z0-9_-')"
  if [[ -z "$sanitized" ]]; then
    sanitized="acore-compose"
  elif [[ ! "$sanitized" =~ ^[a-z0-9] ]]; then
    sanitized="ac${sanitized}"
  fi
  echo "$sanitized"
}

compose(){
  local project_name
  project_name="$(resolve_project_name)"
  docker compose --project-name "$project_name" -f "$COMPOSE_FILE" "$@"
}

ensure_source_repo(){
  local use_playerbot_source=0
  if requires_playerbot_source; then
    use_playerbot_source=1
  fi
  local local_root
  local_root="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  local_root="${local_root%/}"
  [ -z "$local_root" ] && local_root="."
  local default_source="${local_root}/source/azerothcore"
  if [ "$use_playerbot_source" = "1" ]; then
    default_source="${local_root}/source/azerothcore-playerbots"
  fi

  local src_path
  src_path="$(read_env MODULES_REBUILD_SOURCE_PATH "$default_source")"
  if [[ "$src_path" != /* ]]; then
    src_path="$ROOT_DIR/$src_path"
  fi
  if [ -d "$src_path/.git" ]; then
    echo "$src_path"
    return
  fi
  warn "AzerothCore source not found at $src_path; running setup-source.sh"
  (cd "$ROOT_DIR" && ./scripts/setup-source.sh)
  echo "$src_path"
}

stop_runtime_stack(){
  info "Stopping runtime stack to avoid container name conflicts"
  compose \
    --profile services-standard \
    --profile services-playerbots \
    --profile services-modules \
    --profile db \
    --profile client-data \
    --profile client-data-bots \
    --profile modules \
    down 2>/dev/null || true
}

sync_modules(){
  info "Synchronising modules (ac-modules)"
  compose --profile db --profile modules up ac-modules
  compose --profile db --profile modules down >/dev/null 2>&1 || true
}

modules_need_rebuild(){
  local storage_path
  storage_path="$(read_env STORAGE_PATH "./storage")"
  if [[ "$storage_path" != /* ]]; then
    storage_path="$ROOT_DIR/$storage_path"
  fi
  local sentinel="$storage_path/modules/.requires_rebuild"
  [[ -f "$sentinel" ]]
}

check_auto_rebuild_setting(){
  local auto_rebuild
  auto_rebuild="$(read_env AUTO_REBUILD_ON_DEPLOY "0")"
  [[ "$auto_rebuild" = "1" ]]
}

detect_rebuild_reasons(){
  local reasons=()

  # Check sentinel file
  if modules_need_rebuild; then
    reasons+=("Module changes detected (sentinel file present)")
  fi

  # Check if any C++ modules are enabled but modules-latest images don't exist
  local any_cxx_modules=0
  local var
  for var in "${COMPILE_MODULE_VARS[@]}"; do
    if [ "$(read_env "$var" "0")" = "1" ]; then
      any_cxx_modules=1
      break
    fi
  done

  if [ "$any_cxx_modules" = "1" ]; then
    local authserver_modules_image
    local worldserver_modules_image
    authserver_modules_image="$(read_env AC_AUTHSERVER_IMAGE_MODULES "uprightbass360/azerothcore-wotlk-playerbots:authserver-modules-latest")"
    worldserver_modules_image="$(read_env AC_WORLDSERVER_IMAGE_MODULES "uprightbass360/azerothcore-wotlk-playerbots:worldserver-modules-latest")"

    if ! docker image inspect "$authserver_modules_image" >/dev/null 2>&1; then
      reasons+=("C++ modules enabled but authserver modules image $authserver_modules_image is missing")
    fi
    if ! docker image inspect "$worldserver_modules_image" >/dev/null 2>&1; then
      reasons+=("C++ modules enabled but worldserver modules image $worldserver_modules_image is missing")
    fi
  fi

  printf '%s\n' "${reasons[@]}"
}

requires_playerbot_source(){
  if [ "$(read_env MODULE_PLAYERBOTS "0")" = "1" ]; then
    return 0
  fi
  local var
  for var in "${COMPILE_MODULE_VARS[@]}"; do
    if [ "$(read_env "$var" "0")" = "1" ]; then
      return 0
    fi
  done
  return 1
}

confirm_rebuild(){
  local reasons=("$@")

  if [ ${#reasons[@]} -eq 0 ]; then
    return 1  # No rebuild needed
  fi

  echo
  warn "Module rebuild appears to be required:"
  local reason
  for reason in "${reasons[@]}"; do
    warn "  • $reason"
  done
  echo

  # Check auto-rebuild setting
  if check_auto_rebuild_setting; then
    info "AUTO_REBUILD_ON_DEPLOY is enabled; proceeding with automatic rebuild."
    return 0
  fi

  # Skip prompt if --yes flag is provided
  if [ "$ASSUME_YES" -eq 1 ]; then
    info "Auto-confirming rebuild (--yes supplied)."
    return 0
  fi

  # Interactive prompt
  info "This will rebuild AzerothCore from source with your enabled modules."
  warn "⏱️  This process typically takes 15-45 minutes depending on your system."
  echo
  if [ -t 0 ]; then
    local reply
    read -r -p "Proceed with module rebuild? [y/N]: " reply
    reply="${reply:-n}"
    case "$reply" in
      [Yy]*)
        info "Rebuild confirmed."
        return 0
        ;;
      *)
        warn "Rebuild declined. You can:"
        warn "  • Run with --skip-rebuild to deploy without rebuilding"
        warn "  • Set AUTO_REBUILD_ON_DEPLOY=1 in .env for automatic rebuilds"
        warn "  • Run './scripts/rebuild-with-modules.sh' manually later"
        return 1
        ;;
    esac
  else
    warn "Standard input is not interactive; use --yes to auto-confirm or --skip-rebuild to skip."
    return 1
  fi
}

determine_profile(){
  if [ -n "$TARGET_PROFILE" ]; then
    echo "$TARGET_PROFILE"
    return
  fi

  local module_playerbots
  local playerbot_enabled
  module_playerbots="$(read_env MODULE_PLAYERBOTS "0")"
  playerbot_enabled="$(read_env PLAYERBOT_ENABLED "0")"
  if [ "$module_playerbots" = "1" ] || [ "$playerbot_enabled" = "1" ]; then
    echo "playerbots"
    return
  fi

  local var
  for var in "${COMPILE_MODULE_VARS[@]}"; do
    if [ "$(read_env "$var" "0")" = "1" ]; then
      echo "modules"
      return
    fi
  done

  echo "standard"
}

rebuild_source(){
  local src_dir="$1"
  local compose_file="$src_dir/docker-compose.yml"
  if [ ! -f "$compose_file" ]; then
    warn "Source docker-compose.yml missing at $compose_file; running setup-source.sh"
    (cd "$ROOT_DIR" && ./scripts/setup-source.sh)
  fi
  if [ ! -f "$compose_file" ]; then
    err "Source docker-compose.yml missing at $compose_file"
    return 1
  fi
  info "Rebuilding AzerothCore source with modules (this may take a while)"
  docker compose -f "$compose_file" down --remove-orphans >/dev/null 2>&1 || true
  if (cd "$ROOT_DIR" && ./scripts/rebuild-with-modules.sh --yes); then
    ok "Source rebuild completed"
  else
    err "Source rebuild failed"
    return 1
  fi
  docker compose -f "$compose_file" down --remove-orphans >/dev/null 2>&1 || true
}

tag_module_images(){
  local source_auth
  local source_world
  local target_auth
  local target_world

  source_auth="$(read_env AC_AUTHSERVER_IMAGE_PLAYERBOTS "uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot")"
  source_world="$(read_env AC_WORLDSERVER_IMAGE_PLAYERBOTS "uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot")"
  target_auth="$(read_env AC_AUTHSERVER_IMAGE_MODULES "uprightbass360/azerothcore-wotlk-playerbots:authserver-modules-latest")"
  target_world="$(read_env AC_WORLDSERVER_IMAGE_MODULES "uprightbass360/azerothcore-wotlk-playerbots:worldserver-modules-latest")"

  if docker image inspect "$source_auth" >/dev/null 2>&1; then
    docker tag "$source_auth" "$target_auth"
    ok "Tagged $target_auth from $source_auth"
  else
    warn "Source authserver image $source_auth not found; skipping modules tag"
  fi

  if docker image inspect "$source_world" >/dev/null 2>&1; then
    docker tag "$source_world" "$target_world"
    ok "Tagged $target_world from $source_world"
  else
    warn "Source worldserver image $source_world not found; skipping modules tag"
  fi
}

stage_runtime(){
  local args=(--yes)
  if [ -n "$TARGET_PROFILE" ]; then
    args+=("$TARGET_PROFILE")
  fi
  info "Staging runtime environment via stage-modules.sh ${args[*]}"
  (cd "$ROOT_DIR" && ./scripts/stage-modules.sh "${args[@]}")
}

tail_world_logs(){
  info "Tailing worldserver logs (Ctrl+C to stop)"
  local args=(--follow)
  if [ -n "$WORLD_LOG_SINCE" ]; then
    args+=(--since "$WORLD_LOG_SINCE")
  fi
  local tail_opt="${WORLD_LOG_TAIL:-0}"
  args+=(--tail "$tail_opt")
  if ! docker logs "${args[@]}" ac-worldserver; then
    warn "Worldserver logs unavailable; container may not be running."
  fi
}

wait_for_worldserver_ready(){
  local timeout="${WORLD_READY_TIMEOUT:-180}" start
  start="$(date +%s)"
  info "Waiting for worldserver to become healthy (timeout: ${timeout}s)"
  while true; do
    if ! docker ps --format '{{.Names}}' | grep -qx "ac-worldserver"; then
      info "Worldserver container is not running yet; retrying..."
    else
      local health
      health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' ac-worldserver 2>/dev/null || echo none)"
      case "$health" in
        healthy)
          WORLD_LOG_SINCE="$(docker inspect --format='{{.State.StartedAt}}' ac-worldserver 2>/dev/null)"
          ok "Worldserver reported healthy"
          return 0
          ;;
        none)
          if docker inspect --format='{{.State.Status}}' ac-worldserver 2>/dev/null | grep -q '^running$'; then
            WORLD_LOG_SINCE="$(docker inspect --format='{{.State.StartedAt}}' ac-worldserver 2>/dev/null)"
            ok "Worldserver running (no healthcheck configured)"
            return 0
          fi
          ;;
        unhealthy)
          warn "Worldserver healthcheck reports unhealthy; logs recommended"
          return 1
          ;;
      esac
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      warn "Timed out waiting for worldserver health"
      return 1
    fi
    sleep 3
  done
}

main(){
  if [ "$ASSUME_YES" -ne 1 ]; then
    if [ -t 0 ]; then
      read -r -p "Proceed with AzerothCore deployment? [y/N]: " reply
      reply="${reply:-n}"
    else
      warn "No --yes flag provided and standard input is not interactive; aborting deployment."
      exit 1
    fi
    case "$reply" in
      [Yy]*) info "Deployment confirmed."; ;;
      *) err "Deployment cancelled."; exit 1 ;;
    esac
  else
    info "Auto-confirming deployment (--yes supplied)."
  fi

  show_deployment_header

  local src_dir
  local resolved_profile
  show_step 1 5 "Setting up source repository"
  src_dir="$(ensure_source_repo)"

  resolved_profile="$(determine_profile)"

  if [ "$KEEP_RUNNING" -ne 1 ]; then
    show_step 2 5 "Stopping runtime stack"
    stop_runtime_stack
  fi

  show_step 3 5 "Syncing modules"
  sync_modules

  local did_rebuild=0
  local rebuild_reasons
  readarray -t rebuild_reasons < <(detect_rebuild_reasons)

  if [ ${#rebuild_reasons[@]} -gt 0 ]; then
    if [ "$SKIP_REBUILD" -eq 1 ]; then
      warn "Modules require rebuild, but --skip-rebuild was provided:"
      local reason
      for reason in "${rebuild_reasons[@]}"; do
        warn "  • $reason"
      done
      warn "Proceeding without rebuild; deployment may fail if modules-latest images are missing."
    else
      if confirm_rebuild "${rebuild_reasons[@]}"; then
        show_step 4 5 "Building realm with modules (this may take 15-45 minutes)"
        rebuild_source "$src_dir"
        did_rebuild=1
      else
        err "Rebuild required but declined. Use --skip-rebuild to force deployment without rebuild."
        exit 1
      fi
    fi
  else
    info "No module rebuild required."
  fi

  if [ "$did_rebuild" -eq 1 ]; then
    tag_module_images
  elif [ "$resolved_profile" = "modules" ]; then
    tag_module_images
  fi

  show_step 5 5 "Bringing your realm online"
  info "Pulling images and waiting for containers to become healthy; this may take a few minutes on first deploy."
  stage_runtime

  show_realm_ready

  if [ "$WATCH_LOGS" -eq 1 ]; then
    if wait_for_worldserver_ready; then
      info "Watching your realm come to life (Ctrl+C to stop watching)"
      tail_world_logs
    else
      warn "Skipping log tail; worldserver not healthy. Use './status.sh --once' or 'docker logs ac-worldserver'."
    fi
  else
    ok "Realm deployment completed. Use './status.sh' to monitor your realm."
  fi
}

main

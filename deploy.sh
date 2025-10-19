#!/bin/bash
#
# High-level orchestrator for module-aware deployments.
# 1. Ensures AzerothCore source repo is present
# 2. Runs ac-modules to sync/clean module checkout and configs
# 3. Rebuilds source images when C++ modules demand it
# 4. Stages target compose profile and optionally tails worldserver logs

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose.yml"
ENV_PATH="$ROOT_DIR/.env"
TARGET_PROFILE=""
WATCH_LOGS=1
KEEP_RUNNING=0
SKIP_REBUILD=0

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ️  $*${NC}"; }
ok(){ echo -e "${GREEN}✅ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${NC}"; }
err(){ echo -e "${RED}❌ $*${NC}"; }

show_deployment_header(){
  echo -e "\n${BLUE}    ⚔️  AZEROTHCORE REALM DEPLOYMENT  ⚔️${NC}"
  echo -e "${BLUE}    ════════════════════════════════════${NC}"
  echo -e "${BLUE}         🏰 Bringing Your Realm Online 🏰${NC}\n"
}

show_step(){
  local step="$1" total="$2" message="$3"
  echo -e "${YELLOW}🔧 Step ${step}/${total}: ${message}...${NC}"
}

show_realm_ready(){
  echo -e "\n${GREEN}⚔️ The realm has been forged! ⚔️${NC}"
  echo -e "${GREEN}🏰 Adventurers may now enter your world${NC}"
  echo -e "${GREEN}🗡️ May your server bring epic adventures!${NC}\n"
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile {standard|playerbots|modules}  Force target profile (default: auto-detect)
  --no-watch                               Do not tail worldserver logs after staging
  --keep-running                           Do not pre-stop runtime stack before rebuild
  --skip-rebuild                           Skip source rebuild even if modules require it
  -h, --help                               Show this help

This command automates the module workflow (sync modules, rebuild source if needed,
stage the correct compose profile, and optionally watch worldserver logs).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) TARGET_PROFILE="$2"; shift 2;;
    --no-watch) WATCH_LOGS=0; shift;;
    --keep-running) KEEP_RUNNING=1; shift;;
    --skip-rebuild) SKIP_REBUILD=1; shift;;
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
  local src_path
  src_path="$(read_env MODULES_REBUILD_SOURCE_PATH "./source/azerothcore")"
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
  local source_world="acore/ac-wotlk-worldserver:master"
  local source_auth="acore/ac-wotlk-authserver:master"
  local target_world
  local target_auth
  target_world="$(read_env AC_WORLDSERVER_IMAGE_MODULES "acore/ac-wotlk-worldserver:modules-latest")"
  target_auth="$(read_env AC_AUTHSERVER_IMAGE_MODULES "acore/ac-wotlk-authserver:modules-latest")"

  if docker image inspect "$source_world" >/dev/null 2>&1; then
    docker tag "$source_world" "$target_world"
    ok "Tagged $target_world from $source_world"
  else
    warn "Source image $source_world not found; skipping tag"
  fi

  if docker image inspect "$source_auth" >/dev/null 2>&1; then
    docker tag "$source_auth" "$target_auth"
    ok "Tagged $target_auth from $source_auth"
  else
    warn "Source image $source_auth not found; skipping tag"
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
  compose logs -f ac-worldserver
}

main(){
  show_deployment_header

  local src_dir
  show_step 1 5 "Setting up source repository"
  src_dir="$(ensure_source_repo)"

  if [ "$KEEP_RUNNING" -ne 1 ]; then
    show_step 2 5 "Stopping runtime stack"
    stop_runtime_stack
  fi

  show_step 3 5 "Syncing modules"
  sync_modules

  if modules_need_rebuild; then
    if [ "$SKIP_REBUILD" -eq 1 ]; then
      warn "Modules require rebuild, but --skip-rebuild was provided."
    else
      show_step 4 5 "Building realm with modules (this may take 15-45 minutes)"
      rebuild_source "$src_dir"
      tag_module_images
    fi
  else
    info "No module rebuild required."
    tag_module_images
  fi

  show_step 5 5 "Bringing your realm online"
  stage_runtime

  show_realm_ready

  if [ "$WATCH_LOGS" -eq 1 ]; then
    info "Watching your realm come to life (Ctrl+C to stop watching)"
    tail_world_logs
  else
    ok "Realm deployment completed. Use './status.sh' to monitor your realm."
  fi
}

main

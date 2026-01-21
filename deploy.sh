#!/bin/bash
#
# High-level orchestrator for module-aware deployments.
# 1. Ensures AzerothCore source repo is present
# 2. Runs ac-modules to sync/clean module checkout and configs
# 3. Rebuilds source images when C++ modules demand it
# 4. Stages target compose profile and optionally tails worldserver logs

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_PATH="$ROOT_DIR/.env"
DEFAULT_ENV_PATH="$ENV_PATH"
TEMPLATE_PATH="$ROOT_DIR/.env.template"
source "$ROOT_DIR/scripts/bash/project_name.sh"
source "$ROOT_DIR/scripts/bash/lib/common.sh"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_PATH" "$TEMPLATE_PATH")"
source "$ROOT_DIR/scripts/bash/compose_overrides.sh"
TARGET_PROFILE=""
WATCH_LOGS=1
KEEP_RUNNING=0
WORLD_LOG_SINCE=""
ASSUME_YES=0
SKIP_CONFIG=0

REMOTE_MODE=0
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PORT="22"
REMOTE_IDENTITY=""
REMOTE_PROJECT_DIR=""
REMOTE_SKIP_STORAGE=0
REMOTE_COPY_SOURCE=0
REMOTE_ARGS_PROVIDED=0
REMOTE_AUTO_DEPLOY=0
REMOTE_CLEAN_CONTAINERS=0
REMOTE_STORAGE_OVERRIDE=""
REMOTE_CONTAINER_USER_OVERRIDE=""
REMOTE_ENV_FILE=""
REMOTE_SKIP_ENV=0
REMOTE_PRESERVE_CONTAINERS=0

MODULE_HELPER="$ROOT_DIR/scripts/python/modules.py"
MODULE_STATE_INITIALIZED=0
declare -a MODULES_COMPILE_LIST=()
declare -a COMPOSE_FILE_ARGS=()

show_deployment_header(){
  printf '\n%b\n' "${BLUE}⚔️  AZEROTHCORE REALM DEPLOYMENT ⚔️${NC}"
  printf '%b\n' "${BLUE}═══════════════════════════════════════${NC}"
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

show_remote_plan(){
  local plan_host="${REMOTE_HOST:-<host>}"
  local plan_user="${REMOTE_USER:-<user>}"
  local plan_dir="${REMOTE_PROJECT_DIR:-$(get_default_remote_dir)}"

  printf '\n%b\n' "${BLUE}🧭 Remote Deployment Plan${NC}"
  printf '%b\n' "${YELLOW}├─ Validate build status locally${NC}"
  printf '%b\n' "${YELLOW}└─ Package & sync to ${plan_user}@${plan_host}:${plan_dir}${NC}"
}

maybe_select_deploy_target(){
  if [ "$REMOTE_MODE" -eq 1 ]; then
    return
  fi
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    return
  fi
  echo
  echo "Select deployment target:"
  echo "  1) Local host (current machine)"
  echo "  2) Remote host (package for SSH deployment)"
  local choice
  read -rp "Choice [1]: " choice
  case "${choice:-1}" in
    2)
      REMOTE_MODE=1
      REMOTE_ARGS_PROVIDED=0
      ;;
    *)
      ;;
  esac
}

collect_remote_details(){
  if [ "$REMOTE_MODE" -ne 1 ]; then
    return
  fi

  local interactive=0
  if [ -t 0 ] && [ "$ASSUME_YES" -ne 1 ]; then
    interactive=1
  fi

  if [ -z "$REMOTE_HOST" ] && [ "$interactive" -eq 1 ]; then
    while true; do
      read -rp "Remote host (hostname or IP): " REMOTE_HOST
      [ -n "$REMOTE_HOST" ] && break
      echo "  Please enter a hostname or IP."
    done
  fi

  if [ -z "$REMOTE_USER" ] && [ "$interactive" -eq 1 ]; then
    local default_user="$USER"
    read -rp "SSH username [${default_user}]: " REMOTE_USER
    REMOTE_USER="${REMOTE_USER:-$default_user}"
  fi
  if [ -z "$REMOTE_USER" ] && [ -n "$USER" ]; then
    REMOTE_USER="$USER"
  fi

  if [ -z "$REMOTE_PORT" ]; then
    REMOTE_PORT="22"
  fi
  if [ "$interactive" -eq 1 ]; then
    local port_input
    read -rp "SSH port [${REMOTE_PORT}]: " port_input
    REMOTE_PORT="${port_input:-$REMOTE_PORT}"
  fi

  if [ "$interactive" -eq 1 ]; then
    local identity_input
    local identity_prompt="SSH identity file (leave blank for default)"
    if [ -n "$REMOTE_IDENTITY" ]; then
      identity_prompt="${identity_prompt} [${REMOTE_IDENTITY}]"
    fi
    read -rp "${identity_prompt}: " identity_input
    [ -n "$identity_input" ] && REMOTE_IDENTITY="$identity_input"
  fi
  if [ -n "$REMOTE_IDENTITY" ]; then
    REMOTE_IDENTITY="${REMOTE_IDENTITY/#\~/$HOME}"
  fi

  if [ -z "$REMOTE_PROJECT_DIR" ]; then
    REMOTE_PROJECT_DIR="$(get_default_remote_dir)"
  fi
  if [ "$interactive" -eq 1 ]; then
    local dir_input
    read -rp "Remote project directory [${REMOTE_PROJECT_DIR}]: " dir_input
    REMOTE_PROJECT_DIR="${dir_input:-$REMOTE_PROJECT_DIR}"
  fi

  if [ "$interactive" -eq 1 ] && [ "$REMOTE_ARGS_PROVIDED" -eq 0 ]; then
    local sync_answer
    read -rp "Sync storage directory to remote host? [Y/n]: " sync_answer
    sync_answer="${sync_answer:-Y}"
    case "${sync_answer,,}" in
      n|no) REMOTE_SKIP_STORAGE=1 ;;
      *) REMOTE_SKIP_STORAGE=0 ;;
    esac
  fi

  if [ "$interactive" -eq 1 ] && [ "$REMOTE_ARGS_PROVIDED" -eq 0 ]; then
    local cleanup_answer
    read -rp "Stop/remove remote containers & project images during migration? [y/N]: " cleanup_answer
    cleanup_answer="${cleanup_answer:-n}"
    case "${cleanup_answer,,}" in
      y|yes) REMOTE_CLEAN_CONTAINERS=1 ;;
      *)
        REMOTE_CLEAN_CONTAINERS=0
        # Offer explicit preservation when declining cleanup
        local preserve_answer
        read -rp "Preserve remote containers/images (skip cleanup)? [Y/n]: " preserve_answer
        preserve_answer="${preserve_answer:-Y}"
        case "${preserve_answer,,}" in
          n|no) REMOTE_PRESERVE_CONTAINERS=0 ;;
          *) REMOTE_PRESERVE_CONTAINERS=1 ;;
        esac
        ;;
    esac
  fi

  # Optional remote env overrides (default to current values)
  local storage_default container_user_default
  storage_default="$(read_env STORAGE_PATH "./storage")"
  container_user_default="$(read_env CONTAINER_USER "$(id -u):$(id -g)")"

  if [ -z "$REMOTE_STORAGE_OVERRIDE" ] && [ "$interactive" -eq 1 ]; then
    local storage_input
    read -rp "Remote storage path (STORAGE_PATH) [${storage_default}]: " storage_input
    REMOTE_STORAGE_OVERRIDE="${storage_input:-$storage_default}"
  fi

  if [ -z "$REMOTE_CONTAINER_USER_OVERRIDE" ] && [ "$interactive" -eq 1 ]; then
    local cu_input
    read -rp "Remote container user (CONTAINER_USER) [${container_user_default}]: " cu_input
    REMOTE_CONTAINER_USER_OVERRIDE="${cu_input:-$container_user_default}"
  fi
}

validate_remote_configuration(){
  if [ "$REMOTE_MODE" -ne 1 ]; then
    return
  fi
  if [ -z "$REMOTE_HOST" ]; then
    err "Remote deployment requires a hostname or IP."
    exit 1
  fi
  if [ -z "$REMOTE_USER" ]; then
    err "Remote deployment requires an SSH username."
    exit 1
  fi
  REMOTE_PORT="${REMOTE_PORT:-22}"
  if ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
    err "Invalid SSH port: $REMOTE_PORT"
    exit 1
  fi
  if [ -n "$REMOTE_IDENTITY" ]; then
    REMOTE_IDENTITY="${REMOTE_IDENTITY/#\~/$HOME}"
    if [ ! -f "$REMOTE_IDENTITY" ]; then
      err "Remote identity file not found: $REMOTE_IDENTITY"
      exit 1
    fi
  fi
  if [ -z "$REMOTE_PROJECT_DIR" ]; then
    REMOTE_PROJECT_DIR="$(get_default_remote_dir)"
  fi
  if [ ! -f "$ROOT_DIR/scripts/bash/migrate-stack.sh" ]; then
    err "Migration script not found: $ROOT_DIR/scripts/bash/migrate-stack.sh"
    exit 1
  fi
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile {standard|playerbots|modules}  Force target profile (default: auto-detect)
  --no-watch                               Do not tail worldserver logs after staging
  --keep-running                           Do not pre-stop runtime stack
  --yes, -y                                Auto-confirm deployment prompts
  --watch-logs                             Tail worldserver logs even if --no-watch was set earlier
  --log-tail LINES                         Override WORLD_LOG_TAIL (number of log lines to show)
  --once                                   Run status checks once (alias for --no-watch)
  --remote                                 Package deployment artifacts for a remote host
  --remote-host HOST                       Remote hostname or IP for migration
  --remote-user USER                       SSH username for remote migration
  --remote-port PORT                       SSH port for remote migration (default: 22)
  --remote-identity PATH                   SSH private key for remote migration
  --remote-project-dir DIR                 Remote project directory (default: ~/<project-name>)
  --remote-skip-storage                    Skip syncing the storage directory during migration
  --remote-copy-source                     Copy the local project directory to remote instead of relying on git
  --remote-auto-deploy                     Run './deploy.sh --yes --no-watch' on the remote host after migration
  --remote-clean-containers                Stop/remove remote containers & project images during migration
  --remote-storage-path PATH               Override STORAGE_PATH/STORAGE_PATH_LOCAL in the remote .env
  --remote-container-user USER[:GROUP]     Override CONTAINER_USER in the remote .env
  --remote-skip-env                        Do not upload .env to the remote host
  --remote-preserve-containers             Skip stopping/removing remote containers during migration
  --skip-config                            Skip applying server configuration preset
  -h, --help                               Show this help

This command automates deployment: sync modules, stage the correct compose profile,
and optionally watch worldserver logs.

Image Requirements:
This script assumes Docker images are already built. If you have custom modules:
• Run './build.sh' first to build custom images
• Standard AzerothCore images will be pulled automatically
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) TARGET_PROFILE="$2"; shift 2;;
    --no-watch) WATCH_LOGS=0; shift;;
    --keep-running) KEEP_RUNNING=1; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    --remote) REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-host) REMOTE_HOST="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-user) REMOTE_USER="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-port) REMOTE_PORT="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-identity) REMOTE_IDENTITY="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-project-dir) REMOTE_PROJECT_DIR="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-skip-storage) REMOTE_SKIP_STORAGE=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-copy-source) REMOTE_COPY_SOURCE=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-auto-deploy) REMOTE_AUTO_DEPLOY=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-clean-containers) REMOTE_CLEAN_CONTAINERS=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-storage-path) REMOTE_STORAGE_OVERRIDE="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-container-user) REMOTE_CONTAINER_USER_OVERRIDE="$2"; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift 2;;
    --remote-skip-env) REMOTE_SKIP_ENV=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --remote-preserve-containers) REMOTE_PRESERVE_CONTAINERS=1; REMOTE_MODE=1; REMOTE_ARGS_PROVIDED=1; shift;;
    --skip-config) SKIP_CONFIG=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

if [ "$REMOTE_CLEAN_CONTAINERS" -eq 1 ] && [ "$REMOTE_PRESERVE_CONTAINERS" -eq 1 ]; then
  err "Cannot combine --remote-clean-containers with --remote-preserve-containers."
  exit 1
fi

require_cmd docker
require_cmd python3

if [ "$REMOTE_MODE" -eq 1 ]; then
  if [ -z "$REMOTE_HOST" ]; then
    err "Remote deployment requires --remote-host to be specified"
    exit 1
  fi
  if [ -z "$REMOTE_USER" ]; then
    err "Remote deployment requires --remote-user to be specified"
    exit 1
  fi
  if [ -n "$REMOTE_IDENTITY" ]; then
    REMOTE_IDENTITY="${REMOTE_IDENTITY/#\~/$HOME}"
    if [ ! -f "$REMOTE_IDENTITY" ]; then
      err "Remote identity file not found: $REMOTE_IDENTITY"
      exit 1
    fi
  fi
  if [ ! -f "$ROOT_DIR/scripts/bash/migrate-stack.sh" ]; then
    err "Migration script not found: $ROOT_DIR/scripts/bash/migrate-stack.sh"
    exit 1
  fi
fi

init_compose_files(){
  compose_overrides::build_compose_args "$ROOT_DIR" "$ENV_PATH" "$DEFAULT_COMPOSE_FILE" COMPOSE_FILE_ARGS
}

init_compose_files

resolve_local_storage_path(){
  local path
  path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$path" != /* ]]; then
    path="${path#./}"
    path="$ROOT_DIR/$path"
  fi
  echo "${path%/}"
}

ensure_modules_dir_writable(){
  local base_path="$1"
  local modules_dir="${base_path%/}/modules"
  if [ -d "$modules_dir" ] || mkdir -p "$modules_dir" 2>/dev/null; then
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    if ! chown -R "$uid":"$gid" "$modules_dir" 2>/dev/null; then
      if command -v docker >/dev/null 2>&1; then
        local helper_image
        helper_image="$(read_env ALPINE_IMAGE "alpine:latest")"
        docker run --rm \
          -u 0:0 \
          -v "$modules_dir":/modules \
          "$helper_image" \
          sh -c "chown -R ${uid}:${gid} /modules && chmod -R ug+rwX /modules" >/dev/null 2>&1 || true
      fi
    fi
    chmod -R u+rwX "$modules_dir" 2>/dev/null || true
  fi
}

ensure_module_state(){
  if [ "$MODULE_STATE_INITIALIZED" -eq 1 ]; then
    return
  fi

  local storage_root
  storage_root="$(resolve_local_storage_path)"
  local output_dir="${storage_root}/modules"
  ensure_modules_dir_writable "$storage_root"

  if ! python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$ROOT_DIR/config/module-manifest.json" generate --output-dir "$output_dir"; then
    err "Module manifest validation failed. See errors above."
  fi

  if [ ! -f "$output_dir/modules.env" ]; then
    err "modules.env not produced at $output_dir/modules.env"
  fi

  # shellcheck disable=SC1090
  source "$output_dir/modules.env"
  MODULE_STATE_INITIALIZED=1
  MODULES_COMPILE_LIST=()
  IFS=' ' read -r -a MODULES_COMPILE_LIST <<< "${MODULES_COMPILE:-}"
  if [ "${#MODULES_COMPILE_LIST[@]}" -eq 1 ] && [ -z "${MODULES_COMPILE_LIST[0]}" ]; then
    MODULES_COMPILE_LIST=()
  fi
}

resolve_project_name(){
  local raw_name="$(read_env COMPOSE_PROJECT_NAME "$DEFAULT_PROJECT_NAME")"
  project_name::sanitize "$raw_name"
}

get_default_remote_dir(){
  local repo_name
  repo_name="$(basename "$ROOT_DIR")"
  echo "~/${repo_name}"
}

resolve_project_image(){
  local tag="$1"
  local project_name
  project_name="$(resolve_project_name)"
  echo "${project_name}:${tag}"
}

is_project_local_image(){
  local image="$1"
  local project_name
  project_name="$(resolve_project_name)"
  [[ "$image" == "${project_name}:"* ]]
}

filter_empty_lines(){
  awk '
    /^[[:space:]]*$/ {
      empty_count++
      if (empty_count <= 1) print
    }
    /[^[:space:]]/ {
      empty_count = 0
      print
    }
  '
}

compose(){
  local project_name
  project_name="$(resolve_project_name)"
  # Add --quiet for less verbose output, filter excessive empty lines
  docker compose --project-name "$project_name" "${COMPOSE_FILE_ARGS[@]}" "$@" | filter_empty_lines
}

# Build detection logic
detect_build_needed(){
  local reasons=()

  # Check sentinel file
  if modules_need_rebuild; then
    reasons+=("Module changes detected (sentinel file present)")
  fi

  # Check if any C++ modules are enabled but modules-latest images don't exist
  ensure_module_state

  local any_cxx_modules=0
  if [ "${#MODULES_COMPILE_LIST[@]}" -gt 0 ]; then
    any_cxx_modules=1
  fi

  if [ "$any_cxx_modules" = "1" ]; then
    local authserver_modules_image
    local worldserver_modules_image
    authserver_modules_image="$(read_env AC_AUTHSERVER_IMAGE_MODULES "$(resolve_project_image "authserver-modules-latest")")"
    worldserver_modules_image="$(read_env AC_WORLDSERVER_IMAGE_MODULES "$(resolve_project_image "worldserver-modules-latest")")"

    if ! docker image inspect "$authserver_modules_image" >/dev/null 2>&1; then
      if is_project_local_image "$authserver_modules_image"; then
        reasons+=("C++ modules enabled but authserver modules image $authserver_modules_image is missing")
      else
        info "Authserver modules image $authserver_modules_image missing locally but not tagged with project prefix; assuming compose will pull from registry."
      fi
    fi
    if ! docker image inspect "$worldserver_modules_image" >/dev/null 2>&1; then
      if is_project_local_image "$worldserver_modules_image"; then
        reasons+=("C++ modules enabled but worldserver modules image $worldserver_modules_image is missing")
      else
        info "Worldserver modules image $worldserver_modules_image missing locally but not tagged with project prefix; assuming compose will pull from registry."
      fi
    fi
  fi

  if [ ${#reasons[@]} -gt 0 ]; then
    printf '%s\n' "${reasons[@]}"
  fi
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

# Deployment sentinel management
mark_deployment_complete(){
  local storage_path
  storage_path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$storage_path" != /* ]]; then
    # Remove leading ./ if present
    storage_path="${storage_path#./}"
    storage_path="$ROOT_DIR/$storage_path"
  fi
  local sentinel="$storage_path/modules/.last_deployed"
  if ! mkdir -p "$(dirname "$sentinel")" 2>/dev/null; then
    warn "Cannot create local-storage directory. Deployment tracking may not work properly."
    return 0
  fi
  if ! date > "$sentinel" 2>/dev/null; then
    local sentinel_dir
    sentinel_dir="$(dirname "$sentinel")"
    if command -v docker >/dev/null 2>&1; then
      local helper_image
      helper_image="$(read_env ALPINE_IMAGE "alpine:latest")"
      local container_user
      container_user="$(read_env CONTAINER_USER "$(id -u):$(id -g)")"
      docker run --rm \
        --user "$container_user" \
        -v "$sentinel_dir":/sentinel \
        "$helper_image" \
        sh -c 'date > /sentinel/.last_deployed' >/dev/null 2>&1 || true
    fi
    if [ ! -f "$sentinel" ]; then
      warn "Unable to update deployment marker at $sentinel (permission denied)."
      return 0
    fi
  fi
}

modules_need_rebuild(){
  local storage_path
  storage_path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$storage_path" != /* ]]; then
    # Remove leading ./ if present
    storage_path="${storage_path#./}"
    storage_path="$ROOT_DIR/$storage_path"
  fi
  local sentinel="$storage_path/modules/.requires_rebuild"
  [[ -f "$sentinel" ]]
}

# Build prompting logic
prompt_build_if_needed(){
  local build_reasons_output
  build_reasons_output=$(detect_build_needed)

  if [ -z "$build_reasons_output" ]; then
    # Belt-and-suspenders: if C++ modules are enabled but module images missing, warn
    ensure_module_state
    if [ "${#MODULES_COMPILE_LIST[@]}" -gt 0 ]; then
      local authserver_modules_image
      local worldserver_modules_image
      authserver_modules_image="$(read_env AC_AUTHSERVER_IMAGE_MODULES "$(resolve_project_image "authserver-modules-latest")")"
      worldserver_modules_image="$(read_env AC_WORLDSERVER_IMAGE_MODULES "$(resolve_project_image "worldserver-modules-latest")")"
      local missing_images=()
      if ! docker image inspect "$authserver_modules_image" >/dev/null 2>&1; then
        missing_images+=("$authserver_modules_image")
      fi
      if ! docker image inspect "$worldserver_modules_image" >/dev/null 2>&1; then
        missing_images+=("$worldserver_modules_image")
      fi
      if [ ${#missing_images[@]} -gt 0 ]; then
        build_reasons_output=$(printf "C++ modules enabled but module images missing: %s\n" "${missing_images[*]}")
      fi
    fi
  fi

  if [ -z "$build_reasons_output" ]; then
    return 0  # No build needed
  fi

  local build_reasons
  readarray -t build_reasons <<< "$build_reasons_output"

  # Check if auto-rebuild is enabled
  local auto_rebuild
  auto_rebuild="$(read_env AUTO_REBUILD_ON_DEPLOY "0")"
  if [ "$auto_rebuild" = "1" ]; then
    warn "Auto-rebuild enabled, running build process..."
    if (cd "$ROOT_DIR" && ./build.sh --yes); then
      ok "Build completed successfully"
      return 0
    else
      err "Build failed"
      return 1
    fi
  fi

  if [ "$ASSUME_YES" -eq 1 ]; then
    warn "Build required; auto-confirming (--yes)"
    if (cd "$ROOT_DIR" && ./build.sh --yes); then
      ok "Build completed successfully"
      return 0
    else
      err "Build failed"
      return 1
    fi
  fi

  # Interactive prompt
  echo
  warn "Build appears to be required:"
  local reason
  for reason in "${build_reasons[@]}"; do
    warn "  • $reason"
  done
  echo

  if [ -t 0 ]; then
    local reply
    read -r -p "Run build now? [y/N]: " reply
    reply="${reply:-n}"
    case "$reply" in
      [Yy]*)
        if (cd "$ROOT_DIR" && ./build.sh --yes); then
          ok "Build completed successfully"
          return 0
        else
          err "Build failed"
          return 1
        fi
        ;;
      *)
        err "Build required but declined. Run './build.sh' manually before deploying or re-run this script."
        return 1
        ;;
    esac
  else
    err "Build required but running non-interactively. Run './build.sh'  manually before deploying or re-run this script."
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

  ensure_module_state
  if [ "${#MODULES_COMPILE_LIST[@]}" -gt 0 ]; then
    echo "modules"
    return
  fi

  echo "standard"
}

run_remote_migration(){
  if [ -z "$REMOTE_ENV_FILE" ] && { [ -n "$REMOTE_STORAGE_OVERRIDE" ] || [ -n "$REMOTE_CONTAINER_USER_OVERRIDE" ]; }; then
    local base_env=""
    if [ -f "$ENV_PATH" ]; then
      base_env="$ENV_PATH"
    elif [ -f "$TEMPLATE_PATH" ]; then
      base_env="$TEMPLATE_PATH"
    fi
    REMOTE_ENV_FILE="$(mktemp)"
    if [ -n "$base_env" ]; then
      cp "$base_env" "$REMOTE_ENV_FILE"
    else
      : > "$REMOTE_ENV_FILE"
    fi
    if [ -n "$REMOTE_STORAGE_OVERRIDE" ]; then
      {
        echo
        echo "STORAGE_PATH=$REMOTE_STORAGE_OVERRIDE"
      } >>"$REMOTE_ENV_FILE"
    fi
    if [ -n "$REMOTE_CONTAINER_USER_OVERRIDE" ]; then
      {
        echo
        echo "CONTAINER_USER=$REMOTE_CONTAINER_USER_OVERRIDE"
      } >>"$REMOTE_ENV_FILE"
    fi
  fi

  local args=(--host "$REMOTE_HOST" --user "$REMOTE_USER")

  if [ -n "$REMOTE_PORT" ] && [ "$REMOTE_PORT" != "22" ]; then
    args+=(--port "$REMOTE_PORT")
  fi

  if [ -n "$REMOTE_IDENTITY" ]; then
    args+=(--identity "$REMOTE_IDENTITY")
  fi

  if [ -n "$REMOTE_PROJECT_DIR" ]; then
    args+=(--project-dir "$REMOTE_PROJECT_DIR")
  fi

  if [ "$REMOTE_SKIP_STORAGE" -eq 1 ]; then
    args+=(--skip-storage)
  fi

  if [ "$REMOTE_COPY_SOURCE" -eq 1 ]; then
    args+=(--copy-source)
  fi

  if [ "$REMOTE_CLEAN_CONTAINERS" -eq 1 ]; then
    args+=(--clean-containers)
  fi

  if [ "$ASSUME_YES" -eq 1 ]; then
    args+=(--yes)
  fi

  if [ "$REMOTE_SKIP_ENV" -eq 1 ]; then
    args+=(--skip-env)
  fi

  if [ "$REMOTE_PRESERVE_CONTAINERS" -eq 1 ]; then
    args+=(--preserve-containers)
  fi

  if [ -n "$REMOTE_ENV_FILE" ]; then
    args+=(--env-file "$REMOTE_ENV_FILE")
  fi

  (cd "$ROOT_DIR" && ./scripts/bash/migrate-stack.sh "${args[@]}")
}

remote_exec(){
  local remote_cmd="$1"
  local ssh_cmd=(ssh -p "${REMOTE_PORT:-22}")
  if [ -n "$REMOTE_IDENTITY" ]; then
    ssh_cmd+=(-i "$REMOTE_IDENTITY")
  fi
  ssh_cmd+=("${REMOTE_USER}@${REMOTE_HOST}" "$remote_cmd")
  "${ssh_cmd[@]}"
}

run_remote_auto_deploy(){
  local remote_dir="${1:-${REMOTE_PROJECT_DIR:-$(get_default_remote_dir)}}"
  local deploy_cmd="cd ${remote_dir} && ./deploy.sh --yes --no-watch"
  local quoted_cmd
  quoted_cmd=$(printf '%q' "$deploy_cmd")
  info "Triggering remote deployment on ${REMOTE_HOST}..."
  remote_exec "bash -lc ${quoted_cmd}"
}


stage_runtime(){
  local args=(--yes)
  if [ -n "$TARGET_PROFILE" ]; then
    args+=("$TARGET_PROFILE")
  fi
  info "Staging runtime environment via stage-modules.sh ${args[*]}"
  (cd "$ROOT_DIR" && ./scripts/bash/stage-modules.sh "${args[@]}")
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
  info "Waiting for worldserver to become ready (timeout: ${timeout}s)"
  info "First deployment may take 10-15 minutes while client-data is extracted"
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
          info "Worldserver starting up - waiting for client-data to complete..."
          info "This may take several minutes on first deployment while data files are extracted"
          ;;
      esac
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      info "Worldserver is still starting up after ${timeout}s. This is normal for first deployments."
      info "Client-data extraction can take 10-15 minutes. Check progress with './status.sh' or container logs."
      return 1
    fi
    sleep 3
  done
}

apply_server_config(){
  if [ "$SKIP_CONFIG" -eq 1 ]; then
    info "Skipping server configuration application (--skip-config flag set)"
    return 0
  fi

  # Read the SERVER_CONFIG_PRESET from .env
  local server_config_preset
  server_config_preset="$(read_env SERVER_CONFIG_PRESET "none")"

  if [ "$server_config_preset" = "none" ] || [ -z "$server_config_preset" ]; then
    info "No server configuration preset selected - using defaults"
    return 0
  fi

  info "Applying server configuration preset: $server_config_preset"

  local config_script="$ROOT_DIR/scripts/python/apply-config.py"
  if [ ! -x "$config_script" ]; then
    warn "Configuration script not found or not executable: $config_script"
    warn "Server will use default settings"
    return 0
  fi

  local storage_path
  storage_path="$(read_env STORAGE_PATH "./storage")"

  # Check if preset file exists
  local preset_file="$ROOT_DIR/config/presets/${server_config_preset}.conf"
  if [ ! -f "$preset_file" ]; then
    warn "Server configuration preset not found: $preset_file"
    warn "Server will use default settings"
    return 0
  fi

  # Apply the configuration
  if python3 "$config_script" --storage-path "$storage_path" --preset "$server_config_preset"; then
    ok "Server configuration preset '$server_config_preset' applied successfully"
    info "Restart worldserver to apply configuration changes"

    # Restart worldserver if it's running to apply config changes
    if docker ps --format '{{.Names}}' | grep -q '^ac-worldserver$'; then
      info "Restarting worldserver to apply configuration changes..."
      docker restart ac-worldserver
      info "Waiting for worldserver to become healthy after configuration..."
      sleep 5  # Brief pause before health check
    fi
  else
    warn "Failed to apply server configuration preset '$server_config_preset'"
    warn "Server will continue with existing settings"
  fi
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

  maybe_select_deploy_target
  collect_remote_details
  validate_remote_configuration

  if [ "$REMOTE_MODE" -eq 1 ]; then
    local remote_steps=2
    show_remote_plan
    show_step 1 "$remote_steps" "Checking build requirements"
    if ! prompt_build_if_needed; then
      err "Build required but not completed. Remote deployment cancelled."
      exit 1
    fi

    show_step 2 "$remote_steps" "Migrating deployment to $REMOTE_HOST"
    if run_remote_migration; then
      ok "Remote deployment package prepared for $REMOTE_USER@$REMOTE_HOST."
      local remote_dir="${REMOTE_PROJECT_DIR:-$(get_default_remote_dir)}"
      if [ "$REMOTE_AUTO_DEPLOY" -eq 1 ]; then
        if run_remote_auto_deploy "$remote_dir"; then
          ok "Remote host deployment completed."
        else
          warn "Automatic remote deployment failed."
          info "Run the following on the remote host to complete deployment:"
          printf '  %bcd %s && ./deploy.sh --yes --no-watch%b\n' "$YELLOW" "$remote_dir" "$NC"
          exit 1
        fi
      else
        info "Run the following on the remote host to complete deployment:"
        printf '  %bcd %s && ./deploy.sh --yes --no-watch%b\n' "$YELLOW" "$remote_dir" "$NC"
      fi
      exit 0
    else
      err "Remote migration failed."
      exit 1
    fi
  fi

  show_step 1 4 "Checking build requirements"
  if ! prompt_build_if_needed; then
    err "Build required but not completed. Deployment cancelled."
    exit 1
  fi

  if [ "$KEEP_RUNNING" -ne 1 ]; then
    show_step 2 4 "Stopping runtime stack"
    stop_runtime_stack
  fi

  show_step 3 5 "Importing user database files"
  info "Checking for database files in ./import/db/ and ./database-import/"
  bash "$ROOT_DIR/scripts/bash/import-database-files.sh"

  show_step 4 6 "Bringing your realm online"
  info "Pulling images and waiting for containers to become healthy; this may take a few minutes on first deploy."
  stage_runtime

  show_step 5 6 "Applying server configuration"
  apply_server_config

  show_step 6 6 "Finalizing deployment"
  mark_deployment_complete

  show_realm_ready

  if [ "$WATCH_LOGS" -eq 1 ]; then
    if wait_for_worldserver_ready; then
      info "Watching your realm come to life (Ctrl+C to stop watching)"
      tail_world_logs
    else
      info "Worldserver still initializing. Client-data extraction may still be in progress."
      info "Use './status.sh' to monitor progress or 'docker logs ac-worldserver' to view startup logs."
    fi
  else
    ok "Realm deployment completed. Use './status.sh' to monitor your realm."
  fi
}

main

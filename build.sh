#!/bin/bash
#
# AzerothCore Build Script
# Handles all module compilation and image building for custom configurations
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$ROOT_DIR/.env"
ASSUME_YES=0
FORCE_REBUILD=0
SKIP_SOURCE_SETUP=0
CUSTOM_SOURCE_PATH=""
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ printf '%b\n' "${BLUE}ℹ️  $*${NC}"; }
ok(){ printf '%b\n' "${GREEN}✅ $*${NC}"; }
warn(){ printf '%b\n' "${YELLOW}⚠️  $*${NC}"; }
err(){ printf '%b\n' "${RED}❌ $*${NC}"; }

show_build_header(){
  printf '\n%b\n' "${BLUE}🔨 AZEROTHCORE BUILD SYSTEM 🔨${NC}"
  printf '%b\n' "${BLUE}═══════════════════════════════════${NC}"
  printf '%b\n\n' "${BLUE}⚒️  Forging Your Custom Realm ⚒️${NC}"
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Build AzerothCore with custom modules and create deployment-ready images.

Options:
  --yes, -y                    Auto-confirm all prompts
  --force                      Force rebuild even if no changes detected
  --source-path PATH           Custom source repository path
  --skip-source-setup          Skip automatic source repository setup
  -h, --help                   Show this help

This script handles:
• Source repository preparation and updates
• Module staging and configuration
• AzerothCore compilation with enabled modules
• Docker image building and tagging
• Build state management

Examples:
  ./build.sh                   Interactive build
  ./build.sh --yes             Auto-confirm build
  ./build.sh --force           Force rebuild regardless of state
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift;;
    --force) FORCE_REBUILD=1; shift;;
    --source-path) CUSTOM_SOURCE_PATH="$2"; shift 2;;
    --skip-source-setup) SKIP_SOURCE_SETUP=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

require_cmd(){
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

require_cmd docker
require_cmd python3

read_env(){
  local key="$1" default="${2:-}"
  local value=""
  if [ -f "$ENV_PATH" ]; then
    value="$(grep -E "^${key}=" "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r' | sed 's/[[:space:]]*#.*//' | sed 's/[[:space:]]*$//')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

update_env_value(){
  local key="$1" value="$2" env_file="$ENV_PATH"
  [ -n "$env_file" ] || return 0
  if [ ! -f "$env_file" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
    return 0
  fi
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

MODULE_HELPER="$ROOT_DIR/scripts/modules.py"
MODULE_STATE_INITIALIZED=0
declare -a MODULES_COMPILE_LIST=()

resolve_local_storage_path(){
  local local_root
  local_root="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$local_root" != /* ]]; then
    local_root="${local_root#./}"
    local_root="$ROOT_DIR/$local_root"
  fi
  echo "${local_root%/}"
}

generate_module_state(){
  local storage_root
  storage_root="$(resolve_local_storage_path)"
  local output_dir="${storage_root}/modules"
  ensure_modules_dir_writable "$storage_root"
  if ! python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$ROOT_DIR/config/modules.json" generate --output-dir "$output_dir"; then
    err "Module manifest validation failed. See errors above."
    exit 1
  fi
  if [ ! -f "${output_dir}/modules.env" ]; then
    err "modules.env not produced by helper at ${output_dir}/modules.env"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${output_dir}/modules.env"
  MODULE_STATE_INITIALIZED=1
  MODULES_COMPILE_LIST=()
  IFS=' ' read -r -a MODULES_COMPILE_LIST <<< "${MODULES_COMPILE:-}"
  if [ "${#MODULES_COMPILE_LIST[@]}" -eq 1 ] && [ -z "${MODULES_COMPILE_LIST[0]}" ]; then
    MODULES_COMPILE_LIST=()
  fi
}

requires_playerbot_source(){
  if [ "$MODULE_STATE_INITIALIZED" -ne 1 ]; then
    generate_module_state
  fi
  [ "${MODULES_REQUIRES_PLAYERBOT_SOURCE:-0}" = "1" ]
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
  if [ -n "$CUSTOM_SOURCE_PATH" ]; then
    src_path="$CUSTOM_SOURCE_PATH"
  else
    src_path="$(read_env MODULES_REBUILD_SOURCE_PATH "$default_source")"
  fi

  if [[ "$src_path" != /* ]]; then
    src_path="$ROOT_DIR/$src_path"
  fi

  # Normalize path (extracted from deploy.sh)
  if command -v readlink >/dev/null 2>&1 && [[ -e "$src_path" || -e "$(dirname "$src_path")" ]]; then
    src_path="$(readlink -f "$src_path" 2>/dev/null || echo "$src_path")"
  else
    src_path="$(cd "$ROOT_DIR" && realpath -m "$src_path" 2>/dev/null || echo "$src_path")"
  fi
  src_path="${src_path//\/.\//\/}"

  if [ -d "$src_path/.git" ]; then
    echo "$src_path"
    return
  fi

  if [ "$SKIP_SOURCE_SETUP" = "1" ]; then
    err "Source repository not found at $src_path and --skip-source-setup specified"
    exit 1
  fi

  warn "AzerothCore source not found at $src_path; running setup-source.sh" >&2
  if ! (cd "$ROOT_DIR" && ./scripts/setup-source.sh) >&2; then
    err "Failed to setup source repository" >&2
    exit 1
  fi

  # Verify the source was actually created
  if [ ! -d "$src_path/.git" ]; then
    err "Source repository setup failed - no git directory at $src_path" >&2
    exit 1
  fi

  echo "$src_path"
}

# Build state detection (extracted from setup.sh and deploy.sh)
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

detect_rebuild_reasons(){
  local reasons=()

  # Check sentinel file
  if modules_need_rebuild; then
    reasons+=("Module changes detected (sentinel file present)")
  fi

  # Check if source repository is freshly cloned (no previous build state)
  local storage_path
  storage_path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$storage_path" != /* ]]; then
    storage_path="$ROOT_DIR/$storage_path"
  fi
  local last_deployed="$storage_path/modules/.last_deployed"
  if [ ! -f "$last_deployed" ]; then
    reasons+=("Fresh source repository setup - initial build required")
  fi

  # Check if any C++ modules are enabled but modules-latest images don't exist
  if [ "$MODULE_STATE_INITIALIZED" -ne 1 ]; then
    generate_module_state
  fi

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
      reasons+=("C++ modules enabled but authserver modules image $authserver_modules_image is missing")
    fi
    if ! docker image inspect "$worldserver_modules_image" >/dev/null 2>&1; then
      reasons+=("C++ modules enabled but worldserver modules image $worldserver_modules_image is missing")
    fi
  fi

  if [ ${#reasons[@]} -gt 0 ]; then
    printf '%s\n' "${reasons[@]}"
  fi
}

confirm_build(){
  local reasons=("$@")

  if [ ${#reasons[@]} -eq 0 ] && [ "$FORCE_REBUILD" = "0" ]; then
    info "No build required - all images are up to date"
    if [ "$ASSUME_YES" -ne 1 ] && [ -t 0 ]; then
      local reply
      read -r -p "Build anyway? [y/N]: " reply
      reply="${reply:-n}"
      case "$reply" in
        [Yy]*) return 0 ;;  # Proceed with build
        *) return 1 ;;      # Skip build
      esac
    else
      return 1  # No build needed (non-interactive or --yes flag)
    fi
  fi

  # Skip duplicate output if called from deploy.sh (reasons already shown)
  local show_reasons=1
  if [ "$ASSUME_YES" -eq 1 ] && [ ${#reasons[@]} -gt 0 ]; then
    show_reasons=0  # deploy.sh already showed the reasons
  fi

  if [ "$show_reasons" -eq 1 ]; then
    echo
    if [ "$FORCE_REBUILD" = "1" ]; then
      warn "Force rebuild requested (--force flag)"
    elif [ ${#reasons[@]} -gt 0 ]; then
      warn "Build appears to be required:"
      local reason
      for reason in "${reasons[@]}"; do
        warn "  • $reason"
      done
    fi
    echo
  fi

  # Skip prompt if --yes flag is provided
  if [ "$ASSUME_YES" -eq 1 ]; then
    info "Auto-confirming build (--yes supplied)."
    return 0
  fi

  # Interactive prompt
  info "This will rebuild AzerothCore from source with your enabled modules."
  warn "⏱️  This process typically takes 15-45 minutes depending on your system."
  echo
  if [ -t 0 ]; then
    local reply
    read -r -p "Proceed with build? [y/N]: " reply
    reply="${reply:-n}"
    case "$reply" in
      [Yy]*)
        info "Build confirmed."
        return 0
        ;;
      *)
        info "Build cancelled."
        return 1
        ;;
    esac
  else
    warn "Standard input is not interactive; use --yes to auto-confirm."
    return 1
  fi
}

# Module staging logic (extracted from setup.sh)
sync_modules(){
  local storage_path
  storage_path="$(resolve_local_storage_path)"

  mkdir -p "$storage_path/modules"
  info "Using local module staging at $storage_path/modules"
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

ensure_modules_dir_writable(){
  local base_path="$1"
  local modules_dir="${base_path%/}/modules"
  ensure_host_writable "$modules_dir"
}

ensure_host_writable(){
  local target="$1"
  [ -n "$target" ] || return 0
  if [ -d "$target" ] || mkdir -p "$target" 2>/dev/null; then
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    if ! chown -R "$uid":"$gid" "$target" 2>/dev/null; then
      if command -v docker >/dev/null 2>&1; then
        local helper_image
        helper_image="$(read_env ALPINE_IMAGE "alpine:latest")"
        docker run --rm \
          -u 0:0 \
          -v "$target":/workspace \
          "$helper_image" \
          sh -c "chown -R ${uid}:${gid} /workspace" >/dev/null 2>&1 || true
      fi
    fi
    chmod -R u+rwX "$target" 2>/dev/null || true
  fi
}

resolve_project_image(){
  local tag="$1"
  local project_name
  project_name="$(resolve_project_name)"
  echo "${project_name}:${tag}"
}

stage_modules(){
  local src_path="$1"
  local storage_path
  storage_path="$(resolve_local_storage_path)"

  if [ -z "${MODULES_ENABLED:-}" ]; then
    generate_module_state
  fi

  info "Staging modules to source directory: $src_path/modules"

  # Verify source path exists
  if [ ! -d "$src_path" ]; then
    err "Source path does not exist: $src_path"
    return 1
  fi

  local local_modules_dir="${src_path}/modules"
  mkdir -p "$local_modules_dir"
  ensure_host_writable "$local_modules_dir"

  local staging_modules_dir="${storage_path}/modules"
  export MODULES_HOST_DIR="$staging_modules_dir"
  ensure_host_writable "$staging_modules_dir"

  local env_target_dir="$src_path/env/dist/etc"
  mkdir -p "$env_target_dir"
  export MODULES_ENV_TARGET_DIR="$env_target_dir"
  ensure_host_writable "$env_target_dir"

  local lua_target_dir="$src_path/lua_scripts"
  mkdir -p "$lua_target_dir"
  export MODULES_LUA_TARGET_DIR="$lua_target_dir"
  ensure_host_writable "$lua_target_dir"

  # Set up local storage path for build sentinel tracking
  local local_storage_path
  local_storage_path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$local_storage_path" != /* ]]; then
    # Remove leading ./ if present
    local_storage_path="${local_storage_path#./}"
    local_storage_path="$ROOT_DIR/$local_storage_path"
  fi
  export LOCAL_STORAGE_SENTINEL_PATH="$local_storage_path/modules/.requires_rebuild"

  # Prepare isolated git config for the module script
  local prev_git_config_global="${GIT_CONFIG_GLOBAL:-}"
  local git_temp_config=""
  if command -v mktemp >/dev/null 2>&1; then
    if ! git_temp_config="$(mktemp)"; then
      git_temp_config=""
    fi
  fi
  if [ -z "$git_temp_config" ]; then
    git_temp_config="$local_modules_dir/.gitconfig.tmp"
    : > "$git_temp_config"
  fi
  export GIT_CONFIG_GLOBAL="$git_temp_config"

  # Run module staging script in local modules directory
  export MODULES_LOCAL_RUN=1
  export MODULES_SKIP_SQL=1
  if [ -n "$staging_modules_dir" ]; then
    mkdir -p "$staging_modules_dir"
    rm -f "$staging_modules_dir/.modules_state" "$staging_modules_dir/.requires_rebuild" 2>/dev/null || true
  fi

  if ! (cd "$local_modules_dir" && bash "$ROOT_DIR/scripts/manage-modules.sh"); then
    err "Module staging failed; aborting build"
    return 1
  fi

  ok "Module repositories staged to $local_modules_dir"
  if [ -n "$staging_modules_dir" ]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude '.modules_state' \
        --exclude '.requires_rebuild' \
        --exclude 'modules.env' \
        --exclude 'modules-state.json' \
        --exclude 'modules-compile.txt' \
        --exclude 'modules-enabled.txt' \
        "$local_modules_dir"/ "$staging_modules_dir"/
    else
      find "$staging_modules_dir" -mindepth 1 -maxdepth 1 \
        ! -name '.modules_state' \
        ! -name '.requires_rebuild' \
        ! -name 'modules.env' \
        ! -name 'modules-state.json' \
        ! -name 'modules-compile.txt' \
        ! -name 'modules-enabled.txt' \
        -exec rm -rf {} + 2>/dev/null || true
      (cd "$local_modules_dir" && tar cf - --exclude='.modules_state' --exclude='.requires_rebuild' .) | (cd "$staging_modules_dir" && tar xf -)
    fi
    if [ -f "$local_modules_dir/.modules_state" ]; then
      cp "$local_modules_dir/.modules_state" "$staging_modules_dir/.modules_state" 2>/dev/null || true
    fi
  fi

  # Cleanup
  export GIT_CONFIG_GLOBAL="$prev_git_config_global"
  unset MODULES_LOCAL_RUN
  unset MODULES_SKIP_SQL
  unset MODULES_HOST_DIR
  [ -n "$git_temp_config" ] && [ -f "$git_temp_config" ] && rm -f "$git_temp_config"
}

# Build execution (extracted from setup.sh)
execute_build(){
  local src_path="$1"

  # Verify source path exists
  if [ ! -d "$src_path" ]; then
    err "Source path does not exist: $src_path"
    return 1
  fi

  local compose_file="$src_path/docker-compose.yml"
  if [ ! -f "$compose_file" ]; then
    err "Source docker-compose.yml missing at $compose_file"
    return 1
  fi

  info "Building AzerothCore with modules (this may take a while)"
  docker compose -f "$compose_file" down --remove-orphans >/dev/null 2>&1 || true

  if (cd "$ROOT_DIR" && ./scripts/rebuild-with-modules.sh --yes --source "$src_path"); then
    ok "Source build completed"
  else
    err "Source build failed"
    return 1
  fi

  docker compose -f "$compose_file" down --remove-orphans >/dev/null 2>&1 || true
}

# Image tagging (extracted from setup.sh and deploy.sh)
tag_module_images(){
  local source_auth
  local source_world
  local target_auth
  local target_world

  source_auth="$(read_env AC_AUTHSERVER_IMAGE_PLAYERBOTS "$(resolve_project_image "authserver-playerbots")")"
  source_world="$(read_env AC_WORLDSERVER_IMAGE_PLAYERBOTS "$(resolve_project_image "worldserver-playerbots")")"
  target_auth="$(read_env AC_AUTHSERVER_IMAGE_MODULES "$(resolve_project_image "authserver-modules-latest")")"
  target_world="$(read_env AC_WORLDSERVER_IMAGE_MODULES "$(resolve_project_image "worldserver-modules-latest")")"

  if docker image inspect "$source_auth" >/dev/null 2>&1; then
    if docker tag "$source_auth" "$target_auth"; then
      ok "Tagged $target_auth from $source_auth"
      update_env_value "AC_AUTHSERVER_IMAGE_PLAYERBOTS" "$source_auth"
      update_env_value "AC_AUTHSERVER_IMAGE_MODULES" "$target_auth"
    else
      warn "Failed to tag $target_auth from $source_auth"
    fi
  else
    warn "Source authserver image $source_auth not found; skipping modules tag"
  fi

  if docker image inspect "$source_world" >/dev/null 2>&1; then
    if docker tag "$source_world" "$target_world"; then
      ok "Tagged $target_world from $source_world"
      update_env_value "AC_WORLDSERVER_IMAGE_PLAYERBOTS" "$source_world"
      update_env_value "AC_WORLDSERVER_IMAGE_MODULES" "$target_world"
    else
      warn "Failed to tag $target_world from $source_world"
    fi
  else
    warn "Source worldserver image $source_world not found; skipping modules tag"
  fi
}

show_build_complete(){
  printf '\n%b\n' "${GREEN}🔨 Build Complete! 🔨${NC}"
  printf '%b\n' "${GREEN}⚒️  Your custom AzerothCore images are ready${NC}"
  printf '%b\n\n' "${GREEN}🚀 Ready for deployment with ./deploy.sh${NC}"
}

main(){
  show_build_header

  local src_dir
  local rebuild_reasons

  info "Preparing module manifest metadata"
  generate_module_state

  info "Step 1/6: Setting up source repository"
  src_dir="$(ensure_source_repo)"

  info "Step 2/6: Detecting build requirements"
  readarray -t rebuild_reasons < <(detect_rebuild_reasons)

  if ! confirm_build "${rebuild_reasons[@]}"; then
    info "Build cancelled or not required."
    exit 0
  fi

  info "Step 3/6: Syncing modules to container storage"
  sync_modules

  info "Step 4/6: Staging modules to source directory"
  stage_modules "$src_dir"

  info "Step 5/6: Building AzerothCore with modules"
  execute_build "$src_dir"

  info "Step 6/6: Tagging images for deployment"
  tag_module_images

  # Clear build sentinel after successful build
  local storage_path
  storage_path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$storage_path" != /* ]]; then
    # Remove leading ./ if present
    storage_path="${storage_path#./}"
    storage_path="$ROOT_DIR/$storage_path"
  fi
  local sentinel="$storage_path/modules/.requires_rebuild"
  rm -f "$sentinel" 2>/dev/null || true

  show_build_complete
}

main "$@"

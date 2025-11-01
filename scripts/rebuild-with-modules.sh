#!/bin/bash

# ac-compose helper to rebuild AzerothCore from source with enabled modules.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_rebuild_step(){
  local step="$1" total="$2" message="$3"
  echo -e "${YELLOW}🔧 Step ${step}/${total}: ${message}...${NC}"
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --yes, -y            Skip interactive confirmation prompts
  --source PATH        Override MODULES_REBUILD_SOURCE_PATH from .env
  --skip-stop          Do not run 'docker compose down' in the source tree before rebuilding
  -h, --help           Show this help
EOF
}

read_env(){
  local key="$1" default="$2" env_path="$ENV_FILE" value
  if [ -f "$env_path" ]; then
    value="$(grep -E "^${key}=" "$env_path" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="${!key:-}"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

update_env_value(){
  local key="$1" value="$2" env_file="$ENV_FILE"
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

find_image_with_suffix(){
  local suffix="$1"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E ":${suffix}$" | head -n1
}

cleanup_legacy_tags(){
  local suffix="$1" keep_tag="$2"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E ":${suffix}$" | while read -r tag; do
    [ "$tag" = "$keep_tag" ] && continue
    docker rmi "$tag" >/dev/null 2>&1 || true
  done
}

ensure_project_image_tag(){
  local suffix="$1" target="$2"
  if [ -n "$target" ] && docker image inspect "$target" >/dev/null 2>&1; then
    cleanup_legacy_tags "$suffix" "$target"
    echo "$target"
    return 0
  fi
  local source
  source="$(find_image_with_suffix "$suffix")"
  if [ -z "$source" ]; then
    echo ""
    return 1
  fi
  if docker tag "$source" "$target" >/dev/null 2>&1; then
    if [ "$source" != "$target" ]; then
      docker rmi "$source" >/dev/null 2>&1 || true
    fi
    cleanup_legacy_tags "$suffix" "$target"
    echo "$target"
    return 0
  fi
  echo ""
  return 1
}

resolve_project_name(){
  local raw_name
  raw_name="$(read_env COMPOSE_PROJECT_NAME "acore-compose")"
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

resolve_project_image(){
  local tag="$1"
  local project_name
  project_name="$(resolve_project_name)"
  echo "${project_name}:${tag}"
}

default_source_path(){
  local require_playerbot
  require_playerbot="$(modules_require_playerbot_source)"
  local local_root
  local_root="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  local_root="${local_root%/}"
  if [[ -z "$local_root" ]]; then
    local_root="."
  fi
  if [ "$require_playerbot" = "1" ]; then
    echo "${local_root}/source/azerothcore-playerbots"
  else
    echo "${local_root}/source/azerothcore"
  fi
}

confirm(){
  local prompt="$1" default="$2" reply
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  while true; do
    if [ "$default" = "y" ]; then
      read -r -p "$prompt [Y/n]: " reply
      reply="${reply:-y}"
    else
      read -r -p "$prompt [y/N]: " reply
      reply="${reply:-n}"
    fi
    case "$reply" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
    esac
  done
}

ASSUME_YES=0
SOURCE_OVERRIDE=""
SKIP_STOP=0

MODULE_HELPER="$PROJECT_DIR/scripts/modules.py"
MODULE_STATE_DIR=""
declare -a MODULES_COMPILE_LIST=()

resolve_local_storage_path(){
  local path
  path="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
  if [[ "$path" != /* ]]; then
    path="${path#./}"
    path="$PROJECT_DIR/$path"
  fi
  echo "${path%/}"
}

ensure_module_state(){
  if [ -n "$MODULE_STATE_DIR" ]; then
    return 0
  fi
  local storage_root
  storage_root="$(resolve_local_storage_path)"
  MODULE_STATE_DIR="${storage_root}/modules"
  if ! python3 "$MODULE_HELPER" --env-path "$ENV_FILE" --manifest "$PROJECT_DIR/config/modules.json" generate --output-dir "$MODULE_STATE_DIR"; then
    echo "❌ Module manifest validation failed. See details above."
    exit 1
  fi
  if [ ! -f "$MODULE_STATE_DIR/modules.env" ]; then
    echo "❌ modules.env not produced at $MODULE_STATE_DIR/modules.env"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$MODULE_STATE_DIR/modules.env"
  IFS=' ' read -r -a MODULES_COMPILE_LIST <<< "${MODULES_COMPILE:-}"
  if [ "${#MODULES_COMPILE_LIST[@]}" -eq 1 ] && [ -z "${MODULES_COMPILE_LIST[0]}" ]; then
    MODULES_COMPILE_LIST=()
  fi
}

modules_require_playerbot_source(){
  ensure_module_state
  if [ "${MODULES_REQUIRES_PLAYERBOT_SOURCE:-0}" = "1" ]; then
    echo 1
  else
    echo 0
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift;;
    --source) SOURCE_OVERRIDE="$2"; shift 2;;
    --skip-stop) SKIP_STOP=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker CLI not found in PATH."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 not found in PATH."
  exit 1
fi

STORAGE_PATH="$(read_env STORAGE_PATH "./storage")"
if [[ "$STORAGE_PATH" != /* ]]; then
  STORAGE_PATH="$PROJECT_DIR/${STORAGE_PATH#./}"
fi
# Build sentinel is tracked in local storage
LOCAL_STORAGE_PATH="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
if [[ "$LOCAL_STORAGE_PATH" != /* ]]; then
  # Remove leading ./ if present
  LOCAL_STORAGE_PATH="${LOCAL_STORAGE_PATH#./}"
  LOCAL_STORAGE_PATH="$PROJECT_DIR/$LOCAL_STORAGE_PATH"
fi
MODULES_DIR="$STORAGE_PATH/modules"
SENTINEL_FILE="$LOCAL_STORAGE_PATH/modules/.requires_rebuild"

STORAGE_PATH_ABS="$STORAGE_PATH"

REBUILD_SOURCE_PATH="$SOURCE_OVERRIDE"
default_path="$(default_source_path)"
if [ -z "$REBUILD_SOURCE_PATH" ]; then
  REBUILD_SOURCE_PATH="$(read_env MODULES_REBUILD_SOURCE_PATH "$default_path")"
fi

if [ -z "$REBUILD_SOURCE_PATH" ]; then
  REBUILD_SOURCE_PATH="$default_path"
fi

if [[ "$REBUILD_SOURCE_PATH" != /* ]]; then
  REBUILD_SOURCE_PATH="$PROJECT_DIR/${REBUILD_SOURCE_PATH#./}"
fi

if [[ "$default_path" != /* ]]; then
  default_path_abs="$PROJECT_DIR/${default_path#./}"
else
  default_path_abs="$default_path"
fi
if [[ "$REBUILD_SOURCE_PATH" == "$STORAGE_PATH_ABS"* ]]; then
  echo "⚠️  Source path $REBUILD_SOURCE_PATH is inside shared storage ($STORAGE_PATH_ABS). Using local workspace $default_path_abs instead."
  REBUILD_SOURCE_PATH="$default_path_abs"
fi

REBUILD_SOURCE_PATH="$(realpath "$REBUILD_SOURCE_PATH" 2>/dev/null || echo "$REBUILD_SOURCE_PATH")"

# Check for modules in source directory first, then fall back to shared storage
LOCAL_MODULES_DIR="$REBUILD_SOURCE_PATH/modules"
LOCAL_STAGING_MODULES_DIR="$LOCAL_STORAGE_PATH/modules"

if [ -d "$LOCAL_STAGING_MODULES_DIR" ] && [ "$(ls -A "$LOCAL_STAGING_MODULES_DIR" 2>/dev/null)" ]; then
  echo "🔧 Using modules from local staging: $LOCAL_STAGING_MODULES_DIR"
  MODULES_DIR="$LOCAL_STAGING_MODULES_DIR"
elif [ -d "$LOCAL_MODULES_DIR" ]; then
  echo "🔧 Using modules from source directory: $LOCAL_MODULES_DIR"
  MODULES_DIR="$LOCAL_MODULES_DIR"
else
  echo "⚠️  No local module staging detected; falling back to source directory $LOCAL_MODULES_DIR"
  MODULES_DIR="$LOCAL_MODULES_DIR"
fi

SOURCE_COMPOSE="$REBUILD_SOURCE_PATH/docker-compose.yml"
if [ ! -f "$SOURCE_COMPOSE" ]; then
  if [ -f "$REBUILD_SOURCE_PATH/apps/docker/docker-compose.yml" ]; then
    SOURCE_COMPOSE="$REBUILD_SOURCE_PATH/apps/docker/docker-compose.yml"
  else
    echo "❌ Source docker-compose.yml not found at $REBUILD_SOURCE_PATH (checked $SOURCE_COMPOSE and apps/docker/docker-compose.yml)"
    exit 1
  fi
fi

ensure_module_state

if [ ${#MODULES_COMPILE_LIST[@]} -eq 0 ]; then
  echo "✅ No C++ modules enabled that require a source rebuild."
  rm -f "$SENTINEL_FILE" 2>/dev/null || true
  exit 0
fi

echo "🔧 Modules requiring compilation:"
for mod in "${MODULES_COMPILE_LIST[@]}"; do
  echo "   • $mod"
done

if [ ! -d "$MODULES_DIR" ]; then
  echo "⚠️  Modules directory not found at $MODULES_DIR"
fi

if ! confirm "Proceed with source rebuild in $REBUILD_SOURCE_PATH? (15-45 minutes)" n; then
  echo "❌ Rebuild cancelled"
  exit 1
fi

pushd "$REBUILD_SOURCE_PATH" >/dev/null

if [ "$SKIP_STOP" != "1" ]; then
  echo "🛑 Stopping existing source services (if any)..."
  docker compose down || true
fi

if [ -d "$MODULES_DIR" ]; then
  echo "🔄 Syncing enabled modules into source tree..."
  mkdir -p modules
  find modules -mindepth 1 -maxdepth 1 -type d -name 'mod-*' -exec rm -rf {} + 2>/dev/null || true
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$MODULES_DIR"/ modules/
  else
    cp -R "$MODULES_DIR"/. modules/
  fi
else
  echo "⚠️  No modules directory found at $MODULES_DIR; continuing without sync."
fi

echo "🚀 Building AzerothCore with modules..."
docker compose build --no-cache

echo "🔖 Tagging modules-latest images"

# Get image names and tags from .env.template
TEMPLATE_FILE="$PROJECT_DIR/.env.template"
get_template_value() {
  local key="$1"
  local fallback="$2"
  if [ -f "$TEMPLATE_FILE" ]; then
    local value
    value=$(grep "^${key}=" "$TEMPLATE_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/')
    if [[ "$value" =~ ^\$\{[^}]*:-([^}]*)\}$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    [ -n "$value" ] && echo "$value" || echo "$fallback"
  else
    echo "$fallback"
  fi
}

TARGET_AUTHSERVER_IMAGE="$(read_env AC_AUTHSERVER_IMAGE_MODULES "$(get_template_value "AC_AUTHSERVER_IMAGE_MODULES")")"
TARGET_WORLDSERVER_IMAGE="$(read_env AC_WORLDSERVER_IMAGE_MODULES "$(get_template_value "AC_WORLDSERVER_IMAGE_MODULES")")"
PLAYERBOTS_AUTHSERVER_IMAGE="$(read_env AC_AUTHSERVER_IMAGE_PLAYERBOTS "$(get_template_value "AC_AUTHSERVER_IMAGE_PLAYERBOTS")")"
PLAYERBOTS_WORLDSERVER_IMAGE="$(read_env AC_WORLDSERVER_IMAGE_PLAYERBOTS "$(get_template_value "AC_WORLDSERVER_IMAGE_PLAYERBOTS")")"

[ -z "$TARGET_AUTHSERVER_IMAGE" ] && TARGET_AUTHSERVER_IMAGE="$(resolve_project_image "authserver-modules-latest")"
[ -z "$TARGET_WORLDSERVER_IMAGE" ] && TARGET_WORLDSERVER_IMAGE="$(resolve_project_image "worldserver-modules-latest")"
[ -z "$PLAYERBOTS_AUTHSERVER_IMAGE" ] && PLAYERBOTS_AUTHSERVER_IMAGE="$(resolve_project_image "authserver-playerbots")"
[ -z "$PLAYERBOTS_WORLDSERVER_IMAGE" ] && PLAYERBOTS_WORLDSERVER_IMAGE="$(resolve_project_image "worldserver-playerbots")"

PLAYERBOTS_AUTHSERVER_IMAGE="$(ensure_project_image_tag "authserver-Playerbot" "$(resolve_project_image "authserver-playerbots")")"
if [ -z "$PLAYERBOTS_AUTHSERVER_IMAGE" ]; then
  echo "⚠️  Warning: unable to ensure project tag for authserver playerbots image"
else
  update_env_value "AC_AUTHSERVER_IMAGE_PLAYERBOTS" "$PLAYERBOTS_AUTHSERVER_IMAGE"
fi

PLAYERBOTS_WORLDSERVER_IMAGE="$(ensure_project_image_tag "worldserver-Playerbot" "$(resolve_project_image "worldserver-playerbots")")"
if [ -z "$PLAYERBOTS_WORLDSERVER_IMAGE" ]; then
  echo "⚠️  Warning: unable to ensure project tag for worldserver playerbots image"
else
  update_env_value "AC_WORLDSERVER_IMAGE_PLAYERBOTS" "$PLAYERBOTS_WORLDSERVER_IMAGE"
fi

echo "🔁 Tagging modules images from playerbot build artifacts"
if [ -n "$PLAYERBOTS_AUTHSERVER_IMAGE" ] && docker image inspect "$PLAYERBOTS_AUTHSERVER_IMAGE" >/dev/null 2>&1; then
  if docker tag "$PLAYERBOTS_AUTHSERVER_IMAGE" "$TARGET_AUTHSERVER_IMAGE"; then
    echo "✅ Tagged $TARGET_AUTHSERVER_IMAGE from $PLAYERBOTS_AUTHSERVER_IMAGE"
    update_env_value "AC_AUTHSERVER_IMAGE_PLAYERBOTS" "$PLAYERBOTS_AUTHSERVER_IMAGE"
    update_env_value "AC_AUTHSERVER_IMAGE_MODULES" "$TARGET_AUTHSERVER_IMAGE"
  else
    echo "⚠️  Failed to tag $TARGET_AUTHSERVER_IMAGE from $PLAYERBOTS_AUTHSERVER_IMAGE"
  fi
else
  echo "⚠️  Warning: unable to locate project-tagged authserver playerbots image"
fi

if [ -n "$PLAYERBOTS_WORLDSERVER_IMAGE" ] && docker image inspect "$PLAYERBOTS_WORLDSERVER_IMAGE" >/dev/null 2>&1; then
  if docker tag "$PLAYERBOTS_WORLDSERVER_IMAGE" "$TARGET_WORLDSERVER_IMAGE"; then
    echo "✅ Tagged $TARGET_WORLDSERVER_IMAGE from $PLAYERBOTS_WORLDSERVER_IMAGE"
    update_env_value "AC_WORLDSERVER_IMAGE_PLAYERBOTS" "$PLAYERBOTS_WORLDSERVER_IMAGE"
    update_env_value "AC_WORLDSERVER_IMAGE_MODULES" "$TARGET_WORLDSERVER_IMAGE"
  else
    echo "⚠️  Failed to tag $TARGET_WORLDSERVER_IMAGE from $PLAYERBOTS_WORLDSERVER_IMAGE"
  fi
else
  echo "⚠️  Warning: unable to locate project-tagged worldserver playerbots image"
fi

TARGET_DB_IMPORT_IMAGE="$(resolve_project_image "db-import-playerbots")"
DB_IMPORT_IMAGE="$(ensure_project_image_tag "db-import-Playerbot" "$TARGET_DB_IMPORT_IMAGE")"
if [ -n "$DB_IMPORT_IMAGE" ]; then
  update_env_value "AC_DB_IMPORT_IMAGE" "$DB_IMPORT_IMAGE"
else
  echo "⚠️  Warning: unable to ensure project tag for db-import image"
fi

TARGET_CLIENT_DATA_IMAGE="$(resolve_project_image "client-data-playerbots")"
CLIENT_DATA_IMAGE="$(ensure_project_image_tag "client-data-Playerbot" "$TARGET_CLIENT_DATA_IMAGE")"
if [ -n "$CLIENT_DATA_IMAGE" ]; then
  update_env_value "AC_CLIENT_DATA_IMAGE_PLAYERBOTS" "$CLIENT_DATA_IMAGE"
else
  echo "⚠️  Warning: unable to ensure project tag for client-data image"
fi

show_rebuild_step 5 5 "Cleaning up build containers"
echo "🧹 Cleaning up source build containers..."
docker compose down --remove-orphans >/dev/null 2>&1 || true

popd >/dev/null

remove_sentinel(){
  local sentinel_path="$1"
  [ -n "$sentinel_path" ] || return 0
  [ -f "$sentinel_path" ] || return 0
  if rm -f "$sentinel_path" 2>/dev/null; then
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    local db_image
    db_image="$(read_env AC_DB_IMPORT_IMAGE "acore/ac-wotlk-db-import:14.0.0-dev")"
    if docker image inspect "$db_image" >/dev/null 2>&1; then
      local mount_dir
      mount_dir="$(dirname "$sentinel_path")"
      docker run --rm \
        --entrypoint /bin/sh \
        --user 0:0 \
        -v "$mount_dir":/modules \
        "$db_image" \
        -c 'rm -f /modules/.requires_rebuild' >/dev/null 2>&1 || true
    fi
  fi
  if [ -f "$sentinel_path" ]; then
    echo "⚠️  Unable to remove rebuild sentinel at $sentinel_path. Remove manually if rebuild detection persists."
  fi
}

remove_sentinel "$SENTINEL_FILE"

echo ""
echo -e "${GREEN}⚔️ Module build forged successfully! ⚔️${NC}"
echo -e "${GREEN}🏰 Your custom AzerothCore images are ready${NC}"
echo -e "${GREEN}🗡️ Time to stage your enhanced realm!${NC}"

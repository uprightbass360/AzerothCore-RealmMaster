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

COMPILE_MODULE_KEYS=(
  MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE
  MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS
  MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD
  MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER
  MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT MODULE_ARAC MODULE_ASSISTANT MODULE_REAGENT_BANK
  MODULE_CHALLENGE_MODES MODULE_OLLAMA_CHAT MODULE_PLAYER_BOT_LEVEL_BRACKETS MODULE_STATBOOSTER MODULE_DUNGEON_RESPAWN
  MODULE_SKELETON_MODULE MODULE_BG_SLAVERYVALLEY MODULE_AZEROTHSHARD MODULE_WORGOBLIN
)

modules_require_playerbot_source(){
  if [ "$(read_env MODULE_PLAYERBOTS "0")" = "1" ]; then
    echo 1
    return
  fi
  local key
  for key in "${COMPILE_MODULE_KEYS[@]}"; do
    if [ "$(read_env "$key" "0")" = "1" ]; then
      echo 1
      return
    fi
  done
  echo 0
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

STORAGE_PATH="$(read_env STORAGE_PATH "./storage")"
if [[ "$STORAGE_PATH" != /* ]]; then
  STORAGE_PATH="$PROJECT_DIR/${STORAGE_PATH#./}"
fi
# Build sentinel is tracked in local storage
LOCAL_STORAGE_PATH="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
if [[ "$LOCAL_STORAGE_PATH" != /* ]]; then
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
SHARED_MODULES_DIR="$STORAGE_PATH/modules"

if [ -d "$LOCAL_MODULES_DIR" ]; then
  echo "🔧 Using modules from source directory: $LOCAL_MODULES_DIR"
  MODULES_DIR="$LOCAL_MODULES_DIR"
  # Build sentinel always stays in local storage for consistency
else
  echo "🔧 Using modules from shared storage: $SHARED_MODULES_DIR"
  MODULES_DIR="$SHARED_MODULES_DIR"
  # Build sentinel always stays in local storage for consistency
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

declare -A MODULE_REPO_MAP=(
  [MODULE_AOE_LOOT]=mod-aoe-loot
  [MODULE_LEARN_SPELLS]=mod-learn-spells
  [MODULE_FIREWORKS]=mod-fireworks-on-level
  [MODULE_INDIVIDUAL_PROGRESSION]=mod-individual-progression
  [MODULE_AHBOT]=mod-ahbot
  [MODULE_AUTOBALANCE]=mod-autobalance
  [MODULE_TRANSMOG]=mod-transmog
  [MODULE_NPC_BUFFER]=mod-npc-buffer
  [MODULE_DYNAMIC_XP]=mod-dynamic-xp
  [MODULE_SOLO_LFG]=mod-solo-lfg
  [MODULE_1V1_ARENA]=mod-1v1-arena
  [MODULE_PHASED_DUELS]=mod-phased-duels
  [MODULE_BREAKING_NEWS]=mod-breaking-news-override
  [MODULE_BOSS_ANNOUNCER]=mod-boss-announcer
  [MODULE_ACCOUNT_ACHIEVEMENTS]=mod-account-achievements
  [MODULE_AUTO_REVIVE]=mod-auto-revive
  [MODULE_GAIN_HONOR_GUARD]=mod-gain-honor-guard
  [MODULE_TIME_IS_TIME]=mod-TimeIsTime
  [MODULE_POCKET_PORTAL]=mod-pocket-portal
  [MODULE_RANDOM_ENCHANTS]=mod-random-enchants
  [MODULE_SOLOCRAFT]=mod-solocraft
  [MODULE_PVP_TITLES]=mod-pvp-titles
  [MODULE_NPC_BEASTMASTER]=mod-npc-beastmaster
  [MODULE_NPC_ENCHANTER]=mod-npc-enchanter
  [MODULE_INSTANCE_RESET]=mod-instance-reset
  [MODULE_LEVEL_GRANT]=mod-quest-count-level
  [MODULE_ARAC]=mod-arac
  [MODULE_ASSISTANT]=mod-assistant
  [MODULE_REAGENT_BANK]=mod-reagent-bank
  [MODULE_CHALLENGE_MODES]=mod-challenge-modes
  [MODULE_OLLAMA_CHAT]=mod-ollama-chat
  [MODULE_PLAYER_BOT_LEVEL_BRACKETS]=mod-player-bot-level-brackets
  [MODULE_STATBOOSTER]=StatBooster
  [MODULE_DUNGEON_RESPAWN]=DungeonRespawn
  [MODULE_SKELETON_MODULE]=skeleton-module
  [MODULE_BG_SLAVERYVALLEY]=mod-bg-slaveryvalley
  [MODULE_AZEROTHSHARD]=mod-azerothshard
  [MODULE_WORGOBLIN]=mod-worgoblin
)

compile_modules=()
for key in "${!MODULE_REPO_MAP[@]}"; do
  if [ "$(read_env "$key" "0")" = "1" ]; then
    compile_modules+=("${MODULE_REPO_MAP[$key]}")
  fi
done

if [ ${#compile_modules[@]} -eq 0 ]; then
  echo "✅ No C++ modules enabled that require a source rebuild."
  rm -f "$SENTINEL_FILE" 2>/dev/null || true
  exit 0
fi

echo "🔧 Modules requiring compilation:"
for mod in "${compile_modules[@]}"; do
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

echo "🔁 Tagging modules images from playerbot build artifacts"
if docker image inspect "$PLAYERBOTS_AUTHSERVER_IMAGE" >/dev/null 2>&1; then
  docker tag "$PLAYERBOTS_AUTHSERVER_IMAGE" "$TARGET_AUTHSERVER_IMAGE"
else
  echo "⚠️  Warning: $PLAYERBOTS_AUTHSERVER_IMAGE not found, skipping authserver tag"
fi

if docker image inspect "$PLAYERBOTS_WORLDSERVER_IMAGE" >/dev/null 2>&1; then
  docker tag "$PLAYERBOTS_WORLDSERVER_IMAGE" "$TARGET_WORLDSERVER_IMAGE"
else
  echo "⚠️  Warning: $PLAYERBOTS_WORLDSERVER_IMAGE not found, skipping worldserver tag"
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
if [ -n "$SHARED_MODULES_DIR" ]; then
  remove_sentinel "$SHARED_MODULES_DIR/.requires_rebuild"
fi

echo ""
echo -e "${GREEN}⚔️ Module build forged successfully! ⚔️${NC}"
echo -e "${GREEN}🏰 Your custom AzerothCore images are ready${NC}"
echo -e "${GREEN}🗡️ Time to stage your enhanced realm!${NC}"

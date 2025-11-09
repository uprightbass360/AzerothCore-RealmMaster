#!/bin/bash

# azerothcore-rm helper to automatically stage modules and trigger source builds when needed.

set -e

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

show_staging_header(){
  printf '\n%b\n' "${BLUE}⚔️  REALM STAGING SYSTEM  ⚔️${NC}"
  printf '%b\n' "${BLUE}══════════════════════════════${NC}"
  printf '%b\n\n' "${BLUE}🎯 Configuring Your Realm 🎯${NC}"
}

show_staging_step(){
  local step="$1" message="$2"
  printf '%b\n' "${YELLOW}🔧 ${step}: ${message}...${NC}"
}

sync_local_staging(){
  local src_root="$LOCAL_STORAGE_PATH"
  local dest_root="$STORAGE_PATH"

  if [ -z "$src_root" ] || [ -z "$dest_root" ]; then
    return
  fi

  if [ "$src_root" = "$dest_root" ]; then
    return
  fi

  local src_modules="${src_root}/modules"
  local dest_modules="${dest_root}/modules"

  if [ ! -d "$src_modules" ]; then
    echo "ℹ️  No local module staging found at $src_modules (skipping sync)."
    # Check if modules exist in destination storage
    if [ -d "$dest_modules" ] && [ -n "$(ls -A "$dest_modules" 2>/dev/null)" ]; then
      local module_count
      module_count=$(find "$dest_modules" -maxdepth 1 -type d | wc -l)
      module_count=$((module_count - 1))  # Subtract 1 for the parent directory
      if [ "$module_count" -gt 0 ]; then
        echo "✅ Found $module_count modules in shared storage at $dest_modules"
      fi
    fi
    return
  fi

  echo "📦 Syncing local module staging from $src_modules to $dest_modules"
  if ! mkdir -p "$dest_modules" 2>/dev/null; then
    echo "ℹ️  Destination storage path $dest_root not accessible (likely remote storage - skipping sync)."
    echo "ℹ️  Module sync will be handled by the remote deployment."
    return
  fi

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src_modules"/ "$dest_modules"/
  else
    find "$dest_modules" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    (cd "$src_modules" && tar cf - .) | (cd "$dest_modules" && tar xf -)
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
TEMPLATE_FILE="$PROJECT_DIR/.env.template"
source "$PROJECT_DIR/scripts/bash/project_name.sh"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"
DEFAULT_COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
source "$PROJECT_DIR/scripts/bash/compose_overrides.sh"

usage(){
  cat <<EOF
Usage: $(basename "$0") [options] [PROFILE]

Automatically detect and stage modules for AzerothCore.

Arguments:
  PROFILE              Target profile (standard, playerbots, or auto-detect)

Options:
  --force-rebuild      Force a source rebuild even if not needed
  --yes, -y            Skip interactive confirmation prompts
  -h, --help           Show this help

Examples:
  $(basename "$0")                    # Auto-detect profile based on enabled modules
  $(basename "$0") playerbots         # Force playerbots profile
  $(basename "$0") --force-rebuild    # Force rebuild and auto-detect
EOF
}

read_env(){
  local key="$1" default="$2" env_path="$ENV_FILE" value
  if [ -f "$env_path" ]; then
    value="$(grep -E "^${key}=" "$env_path" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

resolve_project_name(){
  local raw_name
  raw_name="$(read_env COMPOSE_PROJECT_NAME "$DEFAULT_PROJECT_NAME")"
  project_name::sanitize "$raw_name"
}

if [ -z "${COMPOSE_FILE:-}" ]; then
  compose_files=("$DEFAULT_COMPOSE_FILE")
  declare -a enabled_overrides=()
  compose_overrides::list_enabled_files "$PROJECT_DIR" "$ENV_FILE" enabled_overrides
  if [ "${#enabled_overrides[@]}" -gt 0 ]; then
    compose_files+=("${enabled_overrides[@]}")
  fi
  COMPOSE_FILE="$(IFS=:; echo "${compose_files[*]}")"
  export COMPOSE_FILE
fi

resolve_project_image(){
  local tag="$1"
  local project_name
  project_name="$(resolve_project_name)"
  echo "${project_name}:${tag}"
}

canonical_path(){
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$path"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import os, sys
print(os.path.normpath(sys.argv[1]))
PY
  else
    local normalized="$path"
    # Strip leading "./" portions so relative paths are clean
    while [[ "$normalized" == ./* ]]; do
      normalized="${normalized:2}"
    done
    # Collapse any embedded "/./" segments that appear in absolute paths
    while [[ "$normalized" == *"/./"* ]]; do
      normalized="${normalized//\/\.\//\/}"
    done
    # Replace duplicate slashes with a single slash for readability
    while [[ "$normalized" == *"//"* ]]; do
      normalized="${normalized//\/\//\/}"
    done
    # Preserve absolute path prefix if original started with '/'
    if [[ "$path" == /* && "$normalized" != /* ]]; then
      normalized="/${normalized}"
    fi
    echo "$normalized"
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

# Parse arguments
ASSUME_YES=0
FORCE_REBUILD=0
TARGET_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift;;
    --force-rebuild) FORCE_REBUILD=1; shift;;
    -h|--help) usage; exit 0;;
    standard|playerbots) TARGET_PROFILE="$1"; shift;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker CLI not found in PATH."
  exit 1
fi

STORAGE_PATH="$(read_env STORAGE_PATH "./storage")"
if [[ "$STORAGE_PATH" != /* ]]; then
  STORAGE_PATH="$PROJECT_DIR/$STORAGE_PATH"
fi
STORAGE_PATH="$(canonical_path "$STORAGE_PATH")"
MODULES_DIR="$STORAGE_PATH/modules"

# Build sentinel is in local storage, deployment modules are in shared storage
LOCAL_STORAGE_PATH="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
if [[ "$LOCAL_STORAGE_PATH" != /* ]]; then
  LOCAL_STORAGE_PATH="$PROJECT_DIR/$LOCAL_STORAGE_PATH"
fi
LOCAL_STORAGE_PATH="$(canonical_path "$LOCAL_STORAGE_PATH")"
SENTINEL_FILE="$LOCAL_STORAGE_PATH/modules/.requires_rebuild"

# Define module mappings (from rebuild-with-modules.sh)
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

show_staging_header

# Check for enabled C++ modules that require compilation
compile_modules=()
for key in "${!MODULE_REPO_MAP[@]}"; do
  if [ "$(read_env "$key" "0")" = "1" ]; then
    compile_modules+=("${MODULE_REPO_MAP[$key]}")
  fi
done

# Check for playerbots mode
PLAYERBOT_ENABLED="$(read_env PLAYERBOT_ENABLED "0")"
MODULE_PLAYERBOTS="$(read_env MODULE_PLAYERBOTS "0")"

# Determine target profile if not specified
if [ -z "$TARGET_PROFILE" ]; then
  show_staging_step "Profile Detection" "Analyzing enabled modules"
  if [ "$MODULE_PLAYERBOTS" = "1" ] || [ "$PLAYERBOT_ENABLED" = "1" ]; then
    TARGET_PROFILE="playerbots"
    echo "🤖 Playerbot profile enabled"
    if [ ${#compile_modules[@]} -gt 0 ]; then
      echo "   ⚠️  Detected ${#compile_modules[@]} C++ modules. Ensure your playerbot images include these features."
    fi
  elif [ ${#compile_modules[@]} -gt 0 ]; then
    echo "🔧 Detected ${#compile_modules[@]} C++ modules requiring compilation:"
    for mod in "${compile_modules[@]}"; do
      echo "   • $mod"
    done
    TARGET_PROFILE="modules"
    echo "🧩 Using modules profile for custom source build"
  else
    TARGET_PROFILE="standard"
    echo "✅ No special modules detected - using standard profile"
  fi
fi

echo "🎯 Target profile: services-$TARGET_PROFILE"

# Check if source rebuild is needed for modules profile
REBUILD_NEEDED=0
TARGET_WORLDSERVER_IMAGE_MODULES="$(read_env AC_WORLDSERVER_IMAGE_MODULES "$(resolve_project_image "worldserver-modules-latest")")"
if [ "$TARGET_PROFILE" = "modules" ]; then
  # Check if source image exists
  if ! docker image inspect "$TARGET_WORLDSERVER_IMAGE_MODULES" >/dev/null 2>&1; then
    echo "📦 Modules image $TARGET_WORLDSERVER_IMAGE_MODULES not found - rebuild needed"
    REBUILD_NEEDED=1
  elif [ -f "$SENTINEL_FILE" ]; then
    echo "🔄 Modules changed since last build - rebuild needed"
    REBUILD_NEEDED=1
  elif [ "$FORCE_REBUILD" = "1" ]; then
    echo "🔧 Force rebuild requested"
    REBUILD_NEEDED=1
  fi

  if [ "$REBUILD_NEEDED" = "1" ]; then
    show_staging_step "Source Rebuild" "Preparing custom build with modules"
    echo "🚀 Triggering source rebuild with modules..."
    if confirm "Proceed with source rebuild? (15-45 minutes)" n; then
      "$SCRIPT_DIR/rebuild-with-modules.sh" ${ASSUME_YES:+--yes}
    else
      echo "❌ Rebuild cancelled"
      exit 1
    fi
  else
    echo "✅ Custom worldserver image up to date"
  fi
fi

# Stage the services
show_staging_step "Service Orchestration" "Preparing realm services"
sync_local_staging
echo "🎬 Staging services with profile: services-$TARGET_PROFILE"
echo "⏳ Pulling images and starting containers; this can take several minutes on first run."

# Stop any currently running services
echo "🛑 Stopping current services..."
docker compose \
  --profile services-standard \
  --profile services-playerbots \
  --profile services-modules \
  --profile tools \
  --profile client-data \
  --profile client-data-bots \
  down 2>/dev/null || true

# Build list of profiles to start
PROFILE_ARGS=(--profile "services-$TARGET_PROFILE" --profile db --profile modules --profile tools)
case "$TARGET_PROFILE" in
  standard) PROFILE_ARGS+=(--profile client-data) ;;
  playerbots) PROFILE_ARGS+=(--profile client-data-bots) ;;
  modules) PROFILE_ARGS+=(--profile client-data) ;;
esac

# Start the target profile
show_staging_step "Realm Activation" "Bringing services online"
echo "🟢 Starting services-$TARGET_PROFILE profile..."
docker compose "${PROFILE_ARGS[@]}" up -d

printf '\n%b\n' "${GREEN}⚔️ Realm staging completed successfully! ⚔️${NC}"
printf '%b\n' "${GREEN}🏰 Profile: services-$TARGET_PROFILE${NC}"
printf '%b\n' "${GREEN}🗡️ Your realm is ready for adventure!${NC}"

# Show status
printf '\n'
echo "📊 Service Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | grep -E "(ac-worldserver|ac-authserver|ac-phpmyadmin|ac-keira3|NAME)" || true

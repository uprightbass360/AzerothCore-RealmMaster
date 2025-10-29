#!/bin/bash

# ac-compose helper to automatically stage modules and trigger source builds when needed.

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
    return
  fi

  echo "📦 Syncing local module staging from $src_modules to $dest_modules"
  mkdir -p "$dest_modules"

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
MODULES_DIR="$STORAGE_PATH/modules"

# Build sentinel is in local storage, deployment modules are in shared storage
LOCAL_STORAGE_PATH="$(read_env STORAGE_PATH_LOCAL "./local-storage")"
if [[ "$LOCAL_STORAGE_PATH" != /* ]]; then
  # Remove leading ./ if present
  LOCAL_STORAGE_PATH="${LOCAL_STORAGE_PATH#./}"
  LOCAL_STORAGE_PATH="$PROJECT_DIR/$LOCAL_STORAGE_PATH"
fi
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
TARGET_WORLDSERVER_IMAGE_MODULES="$(read_env AC_WORLDSERVER_IMAGE_MODULES "uprightbass360/azerothcore-wotlk-playerbots:worldserver-modules-latest")"
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

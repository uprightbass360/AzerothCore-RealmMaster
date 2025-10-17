#!/bin/bash

# ac-compose helper to rebuild AzerothCore from source with enabled modules.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

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

ASSUME_YES=0
SOURCE_OVERRIDE=""
SKIP_STOP=0

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
  STORAGE_PATH="$PROJECT_DIR/$STORAGE_PATH"
fi
MODULES_DIR="$STORAGE_PATH/modules"
SENTINEL_FILE="$MODULES_DIR/.requires_rebuild"

REBUILD_SOURCE_PATH="$SOURCE_OVERRIDE"
if [ -z "$REBUILD_SOURCE_PATH" ]; then
  REBUILD_SOURCE_PATH="$(read_env MODULES_REBUILD_SOURCE_PATH "")"
fi

if [ -z "$REBUILD_SOURCE_PATH" ]; then
  cat <<EOF
❌ MODULES_REBUILD_SOURCE_PATH is not configured.

Set MODULES_REBUILD_SOURCE_PATH in .env to the AzerothCore source repository
that contains the Docker Compose file used for source builds, then rerun:

  scripts/rebuild-with-modules.sh --yes
EOF
  exit 1
fi

if [[ "$REBUILD_SOURCE_PATH" != /* ]]; then
  REBUILD_SOURCE_PATH="$(realpath "$REBUILD_SOURCE_PATH" 2>/dev/null || echo "$REBUILD_SOURCE_PATH")"
fi

SOURCE_COMPOSE="$REBUILD_SOURCE_PATH/docker-compose.yml"
if [ ! -f "$SOURCE_COMPOSE" ]; then
  echo "❌ Source docker-compose.yml not found at $SOURCE_COMPOSE"
  exit 1
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
  [MODULE_ELUNA]=mod-eluna
  [MODULE_TIME_IS_TIME]=mod-TimeIsTime
  [MODULE_POCKET_PORTAL]=mod-pocket-portal
  [MODULE_RANDOM_ENCHANTS]=mod-random-enchants
  [MODULE_SOLOCRAFT]=mod-solocraft
  [MODULE_PVP_TITLES]=mod-pvp-titles
  [MODULE_NPC_BEASTMASTER]=mod-npc-beastmaster
  [MODULE_NPC_ENCHANTER]=mod-npc-enchanter
  [MODULE_INSTANCE_RESET]=mod-instance-reset
  [MODULE_LEVEL_GRANT]=mod-quest-count-level
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
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$MODULES_DIR"/ modules/
  else
    rm -rf modules/*
    cp -R "$MODULES_DIR"/. modules/
  fi
else
  echo "⚠️  No modules directory found at $MODULES_DIR; continuing without sync."
fi

echo "🚀 Building AzerothCore with modules..."
docker compose build --no-cache

echo "🟢 Starting source services..."
docker compose up -d

popd >/dev/null

rm -f "$SENTINEL_FILE" 2>/dev/null || true

echo ""
echo "🎉 SUCCESS! AzerothCore source build completed with modules."

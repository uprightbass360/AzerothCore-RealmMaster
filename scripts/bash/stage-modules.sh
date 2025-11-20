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

seed_sql_ledger_if_needed(){
  : # No-op; ledger removed
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

  # Ensure both source and destination trees are writable by the host user.
  ensure_host_writable "$src_modules"
  ensure_host_writable "$dest_modules"

  if command -v rsync >/dev/null 2>&1; then
    # rsync may return exit code 23 (permission warnings) in WSL2 - these are harmless
    rsync -a --delete "$src_modules"/ "$dest_modules"/ || {
      local rsync_exit=$?
      if [ $rsync_exit -eq 23 ]; then
        echo "ℹ️  rsync completed with permission warnings (normal in WSL2)"
      else
        echo "⚠️  rsync failed with exit code $rsync_exit"
        return $rsync_exit
      fi
    }
  else
    find "$dest_modules" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    (cd "$src_modules" && tar cf - .) | (cd "$dest_modules" && tar xf -)
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

is_project_local_image(){
  local image="$1"
  local project_name
  project_name="$(resolve_project_name)"
  [[ "$image" == "${project_name}:"* ]]
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
STORAGE_PATH_LOCAL="$LOCAL_STORAGE_PATH"
SENTINEL_FILE="$LOCAL_STORAGE_PATH/modules/.requires_rebuild"
MODULES_META_DIR="$STORAGE_PATH/modules/.modules-meta"
RESTORE_PRESTAGED_FLAG="$MODULES_META_DIR/.restore-prestaged"
MODULES_ENABLED_FILE="$MODULES_META_DIR/modules-enabled.txt"
MODULE_SQL_STAGE_PATH="$(read_env MODULE_SQL_STAGE_PATH "$STORAGE_PATH/module-sql-updates")"
MODULE_SQL_STAGE_PATH="$(eval "echo \"$MODULE_SQL_STAGE_PATH\"")"
if [[ "$MODULE_SQL_STAGE_PATH" != /* ]]; then
  MODULE_SQL_STAGE_PATH="$PROJECT_DIR/$MODULE_SQL_STAGE_PATH"
fi
MODULE_SQL_STAGE_PATH="$(canonical_path "$MODULE_SQL_STAGE_PATH")"
mkdir -p "$MODULE_SQL_STAGE_PATH"
ensure_host_writable "$MODULE_SQL_STAGE_PATH"
HOST_STAGE_HELPER_IMAGE="$(read_env ALPINE_IMAGE "alpine:latest")"

declare -A ENABLED_MODULES=()

load_enabled_modules(){
  ENABLED_MODULES=()
  if [ -f "$MODULES_ENABLED_FILE" ]; then
    while IFS= read -r enabled_module; do
      enabled_module="$(echo "$enabled_module" | tr -d '\r')"
      [ -n "$enabled_module" ] || continue
      ENABLED_MODULES["$enabled_module"]=1
    done < "$MODULES_ENABLED_FILE"
  fi
}

module_is_enabled(){
  local module_dir="$1"
  if [ ${#ENABLED_MODULES[@]} -eq 0 ]; then
    return 0
  fi
  if [ -n "${ENABLED_MODULES[$module_dir]:-}" ]; then
    return 0
  fi
  return 1
}

# Load the enabled module list (if present) so staging respects disabled modules.
load_enabled_modules

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
    if is_project_local_image "$TARGET_WORLDSERVER_IMAGE_MODULES"; then
      echo "📦 Modules image $TARGET_WORLDSERVER_IMAGE_MODULES not found - rebuild needed"
      REBUILD_NEEDED=1
    else
      echo "ℹ️  Modules image $TARGET_WORLDSERVER_IMAGE_MODULES missing locally but not tagged with the project prefix; assuming compose will pull from your registry."
    fi
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
      "$PROJECT_DIR/scripts/bash/rebuild-with-modules.sh" ${ASSUME_YES:+--yes}
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

# Stage module SQL to core updates directory (after containers start)
host_stage_clear(){
  docker run --rm \
    -v "$MODULE_SQL_STAGE_PATH":/host-stage \
    "$HOST_STAGE_HELPER_IMAGE" \
    sh -c 'find /host-stage -type f -name "MODULE_*.sql" -delete' >/dev/null 2>&1 || true
}

host_stage_reset_dir(){
  local dir="$1"
  docker run --rm \
    -v "$MODULE_SQL_STAGE_PATH":/host-stage \
    "$HOST_STAGE_HELPER_IMAGE" \
    sh -c "mkdir -p /host-stage/$dir && rm -f /host-stage/$dir/MODULE_*.sql" >/dev/null 2>&1 || true
}

copy_to_host_stage(){
  local file_path="$1"
  local core_dir="$2"
  local target_name="$3"
  local src_dir
  src_dir="$(dirname "$file_path")"
  local base_name
  base_name="$(basename "$file_path")"
  docker run --rm \
    -v "$MODULE_SQL_STAGE_PATH":/host-stage \
    -v "$src_dir":/src \
    "$HOST_STAGE_HELPER_IMAGE" \
    sh -c "mkdir -p /host-stage/$core_dir && cp \"/src/$base_name\" \"/host-stage/$core_dir/$target_name\"" >/dev/null 2>&1
}

stage_module_sql_to_core() {
  show_staging_step "Module SQL Staging" "Preparing module database updates"

  # Start containers first to get access to worldserver container
  show_staging_step "Realm Activation" "Bringing services online"
  echo "🟢 Starting services-$TARGET_PROFILE profile..."
  docker compose "${PROFILE_ARGS[@]}" up -d

  # Wait for worldserver container to be running
  echo "⏳ Waiting for worldserver container..."
  local max_wait=60
  local waited=0
  while ! docker ps --format '{{.Names}}' | grep -q "ac-worldserver" && [ $waited -lt $max_wait ]; do
    sleep 2
    waited=$((waited + 2))
  done

  if ! docker ps --format '{{.Names}}' | grep -q "ac-worldserver"; then
    echo "⚠️  Worldserver container not found, skipping module SQL staging"
    return 0
  fi

  if [ -f "$RESTORE_PRESTAGED_FLAG" ]; then
    echo "↻ Restore pipeline detected (flag: $RESTORE_PRESTAGED_FLAG); re-staging module SQL so worldserver can apply updates."
    rm -f "$RESTORE_PRESTAGED_FLAG" 2>/dev/null || true
  fi

  echo "📦 Staging module SQL files to core updates directory..."
  host_stage_clear

  # Create core updates directories inside container
  docker exec ac-worldserver bash -c "
    mkdir -p /azerothcore/data/sql/updates/db_world \
             /azerothcore/data/sql/updates/db_characters \
             /azerothcore/data/sql/updates/db_auth
  " 2>/dev/null || true

  # Stage SQL from all modules
  local staged_count=0
  local total_skipped=0
  local total_failed=0
  docker exec ac-worldserver bash -c "find /azerothcore/data/sql/updates -name '*_MODULE_*.sql' -delete" >/dev/null 2>&1 || true

  shopt -s nullglob
  for db_type in db-world db-characters db-auth db-playerbots; do
    local core_dir=""
    local legacy_name=""
    case "$db_type" in
      db-world)
        core_dir="db_world"
        legacy_name="world"  # Some modules use 'world' instead of 'db-world'
        ;;
      db-characters)
        core_dir="db_characters"
        legacy_name="characters"
        ;;
      db-auth)
        core_dir="db_auth"
        legacy_name="auth"
        ;;
      db-playerbots)
        core_dir="db_playerbots"
        legacy_name="playerbots"
        ;;
    esac

    docker exec ac-worldserver bash -c "mkdir -p /azerothcore/data/sql/updates/$core_dir" >/dev/null 2>&1 || true
    host_stage_reset_dir "$core_dir"

    local counter=0
    local skipped=0
    local failed=0

    local search_paths=(
      "$MODULES_DIR"/*/data/sql/"$db_type"
      "$MODULES_DIR"/*/data/sql/"$db_type"/base
      "$MODULES_DIR"/*/data/sql/"$db_type"/updates
      "$MODULES_DIR"/*/data/sql/"$legacy_name"
      "$MODULES_DIR"/*/data/sql/"$legacy_name"/base
    )

    for module_dir in "${search_paths[@]}"; do
      for sql_file in "$module_dir"/*.sql; do
        [ -e "$sql_file" ] || continue

        if [ ! -f "$sql_file" ] || [ ! -s "$sql_file" ]; then
          echo "  ⚠️  Skipped empty or invalid: $(basename "$sql_file")"
          skipped=$((skipped + 1))
          continue
        fi

        if grep -qE '^[[:space:]]*(system|exec|shell|!)' "$sql_file" 2>/dev/null; then
          echo "  ❌ Security: Rejected $(basename "$(dirname "$module_dir")")/$(basename "$sql_file") (contains shell commands)"
          failed=$((failed + 1))
          continue
        fi

        local module_name
        module_name="$(echo "$sql_file" | sed 's|.*/modules/||' | cut -d'/' -f1)"
        local base_name
        base_name="$(basename "$sql_file" .sql)"
        local update_identifier="MODULE_${module_name}_${base_name}"

        if ! module_is_enabled "$module_name"; then
          echo "  ⏭️  Skipped $module_name/$db_type/$(basename "$sql_file") (module disabled)"
          skipped=$((skipped + 1))
          continue
        fi

        local target_name="MODULE_${module_name}_${base_name}.sql"
        if ! copy_to_host_stage "$sql_file" "$core_dir" "$target_name"; then
          echo "  ❌ Failed to copy to host staging: $module_name/$db_type/$(basename "$sql_file")"
          failed=$((failed + 1))
          continue
        fi
        if docker cp "$sql_file" "ac-worldserver:/azerothcore/data/sql/updates/$core_dir/$target_name" >/dev/null; then
          echo "  ✓ Staged $module_name/$db_type/$(basename "$sql_file")"
          counter=$((counter + 1))
        else
          echo "  ❌ Failed to copy: $module_name/$(basename "$sql_file")"
          failed=$((failed + 1))
        fi
      done
    done

    staged_count=$((staged_count + counter))
    total_skipped=$((total_skipped + skipped))
    total_failed=$((total_failed + failed))

  done
  shopt -u nullglob

  echo ""
  if [ "$staged_count" -gt 0 ]; then
    echo "✅ Staged $staged_count module SQL files to core updates directory"
    [ "$total_skipped" -gt 0 ] && echo "⚠️  Skipped $total_skipped empty/invalid file(s)"
    [ "$total_failed" -gt 0 ] && echo "❌ Failed to stage $total_failed file(s)"
    echo "🔄 Restart worldserver to apply: docker restart ac-worldserver"
  else
    echo "ℹ️  No module SQL files found to stage"
  fi
}

get_module_dbc_path(){
  local module_name="$1"
  local manifest_file="$PROJECT_DIR/config/module-manifest.json"

  if [ ! -f "$manifest_file" ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local dbc_path
    dbc_path=$(jq -r ".modules[] | select(.name == \"$module_name\") | .server_dbc_path // empty" "$manifest_file" 2>/dev/null)
    if [ -n "$dbc_path" ]; then
      echo "$dbc_path"
      return 0
    fi
  fi

  return 1
}

stage_module_dbc_files(){
  show_staging_step "Module DBC Staging" "Deploying binary DBC files to server"

  if ! docker ps --format '{{.Names}}' | grep -q "ac-worldserver"; then
    echo "⚠️  Worldserver container not found, skipping module DBC staging"
    return 0
  fi

  echo "📦 Staging module DBC files to server data directory..."
  echo "   (Using manifest 'server_dbc_path' field to locate server-side DBC files)"

  local staged_count=0
  local skipped=0
  local failed=0

  shopt -s nullglob
  for module_path in "$MODULES_DIR"/*; do
    [ -d "$module_path" ] || continue
    local module_name="$(basename "$module_path")"

    # Skip disabled modules
    if ! module_is_enabled "$module_name"; then
      continue
    fi

    # Get DBC path from manifest
    local dbc_path
    if ! dbc_path=$(get_module_dbc_path "$module_name"); then
      # No server_dbc_path defined in manifest - skip this module
      continue
    fi

    local dbc_dir="$module_path/$dbc_path"
    if [ ! -d "$dbc_dir" ]; then
      echo "  ⚠️  $module_name: DBC directory not found at $dbc_path"
      skipped=$((skipped + 1))
      continue
    fi

    for dbc_file in "$dbc_dir"/*.dbc; do
      [ -e "$dbc_file" ] || continue

      if [ ! -f "$dbc_file" ] || [ ! -s "$dbc_file" ]; then
        echo "  ⚠️  Skipped empty or invalid: $module_name/$(basename "$dbc_file")"
        skipped=$((skipped + 1))
        continue
      fi

      local dbc_filename="$(basename "$dbc_file")"

      # Copy to worldserver DBC directory
      if docker cp "$dbc_file" "ac-worldserver:/azerothcore/data/dbc/$dbc_filename" >/dev/null 2>&1; then
        echo "  ✓ Staged $module_name → $dbc_filename"
        staged_count=$((staged_count + 1))
      else
        echo "  ❌ Failed to copy: $module_name/$dbc_filename"
        failed=$((failed + 1))
      fi
    done
  done
  shopt -u nullglob

  echo ""
  if [ "$staged_count" -gt 0 ]; then
    echo "✅ Staged $staged_count module DBC files to server data directory"
    [ "$skipped" -gt 0 ] && echo "⚠️  Skipped $skipped file(s) (no server_dbc_path in manifest)"
    [ "$failed" -gt 0 ] && echo "❌ Failed to stage $failed file(s)"
    echo "🔄 Restart worldserver to load new DBC data: docker restart ac-worldserver"
  else
    echo "ℹ️  No module DBC files found to stage (use 'server_dbc_path' in manifest to enable)"
  fi
}

# Stage module SQL (this will also start the containers)
stage_module_sql_to_core

# Stage module DBC files
stage_module_dbc_files

printf '\n%b\n' "${GREEN}⚔️ Realm staging completed successfully! ⚔️${NC}"
printf '%b\n' "${GREEN}🏰 Profile: services-$TARGET_PROFILE${NC}"
printf '%b\n' "${GREEN}🗡️ Your realm is ready for adventure!${NC}"

# Show status
printf '\n'
echo "📊 Service Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | grep -E "(ac-worldserver|ac-authserver|ac-phpmyadmin|ac-keira3|NAME)" || true

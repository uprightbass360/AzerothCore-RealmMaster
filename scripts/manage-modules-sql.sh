#!/bin/bash
# ac-compose
set -e
trap 'echo "    ❌ SQL helper error (line ${LINENO}): ${BASH_COMMAND}" >&2' ERR

CUSTOM_SQL_ROOT="/tmp/scripts/sql/custom"
ALT_CUSTOM_SQL_ROOT="/scripts/sql/custom"

run_custom_sql_group(){
  local subdir="$1" target_db="$2" label="$3"
  local dir="${CUSTOM_SQL_ROOT}/${subdir}"
  if [ ! -d "$dir" ] && [ -d "${ALT_CUSTOM_SQL_ROOT}/${subdir}" ]; then
    dir="${ALT_CUSTOM_SQL_ROOT}/${subdir}"
  fi
  [ -d "$dir" ] || return 0
  LC_ALL=C find "$dir" -type f -name "*.sql" | sort | while read -r sql_file; do
    local base_name
    base_name="$(basename "$sql_file")"
    echo "  Executing ${label}: ${base_name}"
    if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${target_db}" < "$sql_file" >/dev/null 2>&1; then
      echo "    ✅ Successfully executed ${base_name}"
    else
      echo "    ❌ Failed to execute $sql_file"
    fi
  done || true
}

# Function to execute SQL files for a module
execute_module_sql() {
  local module_dir="$1"
  local module_name="$2"
  local playerbots_db="${DB_PLAYERBOTS_NAME:-acore_playerbots}"
  local character_set="${MYSQL_CHARACTER_SET:-utf8mb4}"
  local collation="${MYSQL_COLLATION:-utf8mb4_unicode_ci}"
  local run_sorted_sql

  run_sorted_sql() {
    local dir="$1"
    local target_db="$2"
    local label="$3"
    local skip_regex="${4:-}"
    [ -d "$dir" ] || return
    LC_ALL=C find "$dir" -type f -name "*.sql" | sort | while read -r sql_file; do
      local base_name
      base_name="$(basename "$sql_file")"
      if [ -n "$skip_regex" ] && [[ "$base_name" =~ $skip_regex ]]; then
        echo "  Skipping ${label}: ${base_name}"
        continue
      fi
      echo "  Executing ${label}: ${base_name}"
      if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${target_db}" < "$sql_file" >/dev/null 2>&1; then
        echo "    ✅ Successfully executed ${base_name}"
      else
        echo "    ❌ Failed to execute $sql_file"
      fi
    done || true
  }

  echo "Processing SQL scripts for $module_name..."

  if [ "$module_name" = "Playerbots" ]; then
    echo "  Ensuring database ${playerbots_db} exists..."
    if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${playerbots_db}\` CHARACTER SET ${character_set} COLLATE ${collation};" >/dev/null 2>&1; then
      echo "    ✅ Playerbots database ready"
    else
      echo "    ❌ Failed to ensure playerbots database"
    fi
  fi

  # Find and execute SQL files in the module
  if [ -d "$module_dir/data/sql" ]; then
    # Execute world database scripts
    if [ -d "$module_dir/data/sql/world" ]; then
      find "$module_dir/data/sql/world" -name "*.sql" -type f | while read sql_file; do
        echo "  Executing world SQL: $(basename "$sql_file")"
        if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_WORLD_NAME}" < "$sql_file" >/dev/null 2>&1; then
          echo "    ✅ Successfully executed $(basename "$sql_file")"
        else
          echo "    ❌ Failed to execute $sql_file"
        fi
      done
    fi
    run_sorted_sql "$module_dir/data/sql/db-world" "${DB_WORLD_NAME}" "world SQL"

    # Execute auth database scripts
    if [ -d "$module_dir/data/sql/auth" ]; then
      find "$module_dir/data/sql/auth" -name "*.sql" -type f | while read sql_file; do
        echo "  Executing auth SQL: $(basename "$sql_file")"
        if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" < "$sql_file" >/dev/null 2>&1; then
          echo "    ✅ Successfully executed $(basename "$sql_file")"
        else
          echo "    ❌ Failed to execute $sql_file"
        fi
      done
    fi
    run_sorted_sql "$module_dir/data/sql/db-auth" "${DB_AUTH_NAME}" "auth SQL"

    # Execute character database scripts
    if [ -d "$module_dir/data/sql/characters" ]; then
      find "$module_dir/data/sql/characters" -name "*.sql" -type f | while read sql_file; do
        echo "  Executing characters SQL: $(basename "$sql_file")"
        if mariadb --ssl=false -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_CHARACTERS_NAME}" < "$sql_file" >/dev/null 2>&1; then
          echo "    ✅ Successfully executed $(basename "$sql_file")"
        else
          echo "    ❌ Failed to execute $sql_file"
        fi
      done
    fi
    run_sorted_sql "$module_dir/data/sql/db-characters" "${DB_CHARACTERS_NAME}" "characters SQL"

    # Execute playerbots database scripts
    if [ "$module_name" = "Playerbots" ] && [ -d "$module_dir/data/sql/playerbots" ]; then
      local pb_root="$module_dir/data/sql/playerbots"
      run_sorted_sql "$pb_root/base" "$playerbots_db" "playerbots SQL"
      run_sorted_sql "$pb_root/custom" "$playerbots_db" "playerbots SQL"
      run_sorted_sql "$pb_root/updates" "$playerbots_db" "playerbots SQL"
      run_sorted_sql "$pb_root/archive" "$playerbots_db" "playerbots SQL"
      echo "  Skipping playerbots create scripts (handled by automation)"
    fi

    # Execute base SQL files (common pattern)
    find "$module_dir/data/sql" -maxdepth 1 -name "*.sql" -type f | while read sql_file; do
      echo "  Executing base SQL: $(basename "$sql_file")"
      mysql -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_WORLD_NAME}" < "$sql_file" 2>/dev/null || echo "    Warning: Failed to execute $sql_file"
    done
  fi

  # Look for SQL files in other common locations
  if [ -d "$module_dir/sql" ]; then
    find "$module_dir/sql" -name "*.sql" -type f | while read sql_file; do
      echo "  Executing SQL: $(basename "$sql_file")"
      mysql -h "${CONTAINER_MYSQL}" -P 3306 -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_WORLD_NAME}" < "$sql_file" 2>/dev/null || echo "    Warning: Failed to execute $sql_file"
    done
  fi

  return 0
}

# Main function to execute SQL for all enabled modules
execute_module_sql_scripts() {
  # Install MariaDB client if not available
  which mariadb >/dev/null 2>&1 || {
    echo "Installing MariaDB client..."
    apk add --no-cache mariadb-client >/dev/null 2>&1 || echo "Warning: Could not install MariaDB client"
  }

  # Iterate modules from staging directory to catch new modules automatically
  for module_dir in */; do
    [[ -d "$module_dir" ]] || continue
    [[ "$module_dir" == "." || "$module_dir" == ".." ]] && continue
    module_dir="${module_dir%/}"
    # Only process directories that follow mod-* convention or known module names
    if [[ "$module_dir" != mod-* && "$module_dir" != StatBooster && "$module_dir" != DungeonRespawn && "$module_dir" != eluna-ts ]]; then
      continue
    fi

    local enabled=0
    case "$module_dir" in
      mod-playerbots) enabled="$MODULE_PLAYERBOTS" ;;
      mod-aoe-loot) enabled="$MODULE_AOE_LOOT" ;;
      mod-learn-spells) enabled="$MODULE_LEARN_SPELLS" ;;
      mod-fireworks-on-level) enabled="$MODULE_FIREWORKS" ;;
      mod-individual-progression) enabled="$MODULE_INDIVIDUAL_PROGRESSION" ;;
      mod-ahbot) enabled="$MODULE_AHBOT" ;;
      mod-autobalance) enabled="$MODULE_AUTOBALANCE" ;;
      mod-transmog) enabled="$MODULE_TRANSMOG" ;;
      mod-npc-buffer) enabled="$MODULE_NPC_BUFFER" ;;
      mod-dynamic-xp) enabled="$MODULE_DYNAMIC_XP" ;;
      mod-solo-lfg) enabled="$MODULE_SOLO_LFG" ;;
      mod-1v1-arena) enabled="$MODULE_1V1_ARENA" ;;
      mod-phased-duels) enabled="$MODULE_PHASED_DUELS" ;;
      mod-breaking-news-override) enabled="$MODULE_BREAKING_NEWS" ;;
      mod-boss-announcer) enabled="$MODULE_BOSS_ANNOUNCER" ;;
      mod-account-achievements) enabled="$MODULE_ACCOUNT_ACHIEVEMENTS" ;;
      mod-auto-revive) enabled="$MODULE_AUTO_REVIVE" ;;
      mod-gain-honor-guard) enabled="$MODULE_GAIN_HONOR_GUARD" ;;
      mod-ale) enabled="$MODULE_ELUNA" ;;
      mod-TimeIsTime) enabled="$MODULE_TIME_IS_TIME" ;;
      mod-pocket-portal) enabled="$MODULE_POCKET_PORTAL" ;;
      mod-random-enchants) enabled="$MODULE_RANDOM_ENCHANTS" ;;
      mod-solocraft) enabled="$MODULE_SOLOCRAFT" ;;
      mod-pvp-titles) enabled="$MODULE_PVP_TITLES" ;;
      mod-npc-beastmaster) enabled="$MODULE_NPC_BEASTMASTER" ;;
      mod-npc-enchanter) enabled="$MODULE_NPC_ENCHANTER" ;;
      mod-instance-reset) enabled="$MODULE_INSTANCE_RESET" ;;
      mod-quest-count-level) enabled="$MODULE_LEVEL_GRANT" ;;
      mod-arac) enabled="$MODULE_ARAC" ;;
      mod-assistant) enabled="$MODULE_ASSISTANT" ;;
      mod-reagent-bank) enabled="$MODULE_REAGENT_BANK" ;;
      mod-black-market) enabled="$MODULE_BLACK_MARKET_AUCTION_HOUSE" ;;
      mod-challenge-modes) enabled="$MODULE_CHALLENGE_MODES" ;;
      mod-ollama-chat) enabled="$MODULE_OLLAMA_CHAT" ;;
      mod-player-bot-level-brackets) enabled="$MODULE_PLAYER_BOT_LEVEL_BRACKETS" ;;
      StatBooster) enabled="$MODULE_STATBOOSTER" ;;
      DungeonRespawn) enabled="$MODULE_DUNGEON_RESPAWN" ;;
      skeleton-module) enabled="$MODULE_SKELETON_MODULE" ;;
      mod-bg-slaveryvalley) enabled="$MODULE_BG_SLAVERYVALLEY" ;;
      mod-azerothshard) enabled="$MODULE_AZEROTHSHARD" ;;
      mod-worgoblin) enabled="$MODULE_WORGOBLIN" ;;
      eluna-ts) enabled="$MODULE_ELUNA_TS" ;;
      *) enabled=1 ;;  # Default to enabled for unknown module directories
    esac

    if [ "${enabled:-0}" = "1" ]; then
      # Skip modules explicitly disabled for SQL
      if [ "$module_dir" = "mod-pocket-portal" ]; then
        echo '⚠️  Skipping mod-pocket-portal SQL: module disabled until C++20 patch is applied.'
        continue
      fi
      execute_module_sql "$module_dir" "$module_dir"
    fi
  done

  run_custom_sql_group world "${DB_WORLD_NAME}" "custom world SQL"
  run_custom_sql_group auth "${DB_AUTH_NAME}" "custom auth SQL"
  run_custom_sql_group characters "${DB_CHARACTERS_NAME}" "custom characters SQL"

  return 0
}

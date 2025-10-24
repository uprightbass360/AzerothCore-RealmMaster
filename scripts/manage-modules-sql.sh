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

  # Execute SQL for enabled modules only
  if [ "$MODULE_PLAYERBOTS" = "1" ] && [ -d "mod-playerbots" ]; then
    execute_module_sql "mod-playerbots" "Playerbots"
  fi

  if [ "$MODULE_AOE_LOOT" = "1" ] && [ -d "mod-aoe-loot" ]; then
    execute_module_sql "mod-aoe-loot" "AoE Loot"
  fi

  if [ "$MODULE_LEARN_SPELLS" = "1" ] && [ -d "mod-learn-spells" ]; then
    execute_module_sql "mod-learn-spells" "Learn Spells"
  fi

  if [ "$MODULE_FIREWORKS" = "1" ] && [ -d "mod-fireworks-on-level" ]; then
    execute_module_sql "mod-fireworks-on-level" "Fireworks"
  fi

  if [ "$MODULE_INDIVIDUAL_PROGRESSION" = "1" ] && [ -d "mod-individual-progression" ]; then
    execute_module_sql "mod-individual-progression" "Individual Progression"
  fi

  if [ "$MODULE_AHBOT" = "1" ] && [ -d "mod-ahbot" ]; then
    execute_module_sql "mod-ahbot" "AHBot"
  fi

  if [ "$MODULE_AUTOBALANCE" = "1" ] && [ -d "mod-autobalance" ]; then
    execute_module_sql "mod-autobalance" "AutoBalance"
  fi

  if [ "$MODULE_TRANSMOG" = "1" ] && [ -d "mod-transmog" ]; then
    execute_module_sql "mod-transmog" "Transmog"
  fi

  if [ "$MODULE_NPC_BUFFER" = "1" ] && [ -d "mod-npc-buffer" ]; then
    execute_module_sql "mod-npc-buffer" "NPC Buffer"
  fi

  if [ "$MODULE_DYNAMIC_XP" = "1" ] && [ -d "mod-dynamic-xp" ]; then
    execute_module_sql "mod-dynamic-xp" "Dynamic XP"
  fi

  if [ "$MODULE_SOLO_LFG" = "1" ] && [ -d "mod-solo-lfg" ]; then
    execute_module_sql "mod-solo-lfg" "Solo LFG"
  fi

  if [ "$MODULE_1V1_ARENA" = "1" ] && [ -d "mod-1v1-arena" ]; then
    execute_module_sql "mod-1v1-arena" "1v1 Arena"
  fi

  if [ "$MODULE_PHASED_DUELS" = "1" ] && [ -d "mod-phased-duels" ]; then
    execute_module_sql "mod-phased-duels" "Phased Duels"
  fi

  if [ "$MODULE_BREAKING_NEWS" = "1" ] && [ -d "mod-breaking-news-override" ]; then
    execute_module_sql "mod-breaking-news-override" "Breaking News"
  fi

  if [ "$MODULE_BOSS_ANNOUNCER" = "1" ] && [ -d "mod-boss-announcer" ]; then
    execute_module_sql "mod-boss-announcer" "Boss Announcer"
  fi

  if [ "$MODULE_ACCOUNT_ACHIEVEMENTS" = "1" ] && [ -d "mod-account-achievements" ]; then
    execute_module_sql "mod-account-achievements" "Account Achievements"
  fi

  if [ "$MODULE_AUTO_REVIVE" = "1" ] && [ -d "mod-auto-revive" ]; then
    execute_module_sql "mod-auto-revive" "Auto Revive"
  fi

  if [ "$MODULE_GAIN_HONOR_GUARD" = "1" ] && [ -d "mod-gain-honor-guard" ]; then
    execute_module_sql "mod-gain-honor-guard" "Gain Honor Guard"
  fi

  if [ "$MODULE_ELUNA" = "1" ] && [ -d "mod-eluna" ]; then
    execute_module_sql "mod-eluna" "Eluna"
  fi
  if [ "$MODULE_ARAC" = "1" ] && [ -d "mod-arac" ]; then
    execute_module_sql "mod-arac" "All Races All Classes"
  fi

  if [ "$MODULE_TIME_IS_TIME" = "1" ] && [ -d "mod-TimeIsTime" ]; then
    execute_module_sql "mod-TimeIsTime" "Time Is Time"
  fi

  if [ "$MODULE_POCKET_PORTAL" = "1" ]; then
    echo '⚠️  Skipping mod-pocket-portal SQL: module disabled until C++20 patch is applied.'
    MODULE_POCKET_PORTAL=0
  fi

  if [ "$MODULE_RANDOM_ENCHANTS" = "1" ] && [ -d "mod-random-enchants" ]; then
    execute_module_sql "mod-random-enchants" "Random Enchants"
  fi

  if [ "$MODULE_SOLOCRAFT" = "1" ] && [ -d "mod-solocraft" ]; then
    execute_module_sql "mod-solocraft" "Solocraft"
  fi

  if [ "$MODULE_PVP_TITLES" = "1" ] && [ -d "mod-pvp-titles" ]; then
    execute_module_sql "mod-pvp-titles" "PvP Titles"
  fi

  if [ "$MODULE_NPC_BEASTMASTER" = "1" ] && [ -d "mod-npc-beastmaster" ]; then
    execute_module_sql "mod-npc-beastmaster" "NPC Beastmaster"
  fi

  if [ "$MODULE_NPC_ENCHANTER" = "1" ] && [ -d "mod-npc-enchanter" ]; then
    execute_module_sql "mod-npc-enchanter" "NPC Enchanter"
  fi

  if [ "$MODULE_INSTANCE_RESET" = "1" ] && [ -d "mod-instance-reset" ]; then
    execute_module_sql "mod-instance-reset" "Instance Reset"
  fi

  if [ "$MODULE_LEVEL_GRANT" = "1" ] && [ -d "mod-quest-count-level" ]; then
    execute_module_sql "mod-quest-count-level" "Level Grant"
  fi
  if [ "$MODULE_ASSISTANT" = "1" ] && [ -d "mod-assistant" ]; then
    execute_module_sql "mod-assistant" "Assistant"
  fi
  if [ "$MODULE_REAGENT_BANK" = "1" ] && [ -d "mod-reagent-bank" ]; then
    execute_module_sql "mod-reagent-bank" "Reagent Bank"
  fi
  if [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" = "1" ] && [ -d "mod-black-market" ]; then
    execute_module_sql "mod-black-market" "Black Market"
  fi

  run_custom_sql_group world "${DB_WORLD_NAME}" "custom world SQL"
  run_custom_sql_group auth "${DB_AUTH_NAME}" "custom auth SQL"
  run_custom_sql_group characters "${DB_CHARACTERS_NAME}" "custom characters SQL"

  return 0
}

#!/bin/bash
# Ensure dbimport.conf exists with usable connection values.
set -euo pipefail 2>/dev/null || set -eu

# Usage: seed_dbimport_conf [conf_dir]
# - conf_dir: target directory (defaults to DBIMPORT_CONF_DIR or /azerothcore/env/dist/etc)
seed_dbimport_conf() {
  local conf_dir="${1:-${DBIMPORT_CONF_DIR:-/azerothcore/env/dist/etc}}"
  local conf="${conf_dir}/dbimport.conf"
  local dist="${conf}.dist"
  local source_root="${DBIMPORT_SOURCE_ROOT:-${AC_SOURCE_DIR:-/local-storage-root/source/azerothcore-playerbots}}"
  if [ ! -d "$source_root" ]; then
    local fallback="/local-storage-root/source/azerothcore-wotlk"
    if [ -d "$fallback" ]; then
      source_root="$fallback"
    fi
  fi
  local source_dist="${DBIMPORT_DIST_PATH:-${source_root}/src/tools/dbimport/dbimport.conf.dist}"
  # Put temp dir inside the writable config mount so non-root can create files.
  local temp_dir="${DBIMPORT_TEMP_DIR:-/azerothcore/env/dist/etc/temp}"

  mkdir -p "$conf_dir" "$temp_dir"

  # Prefer a real .dist from the source tree if it exists.
  if [ -f "$source_dist" ]; then
    cp -n "$source_dist" "$dist" 2>/dev/null || true
  fi

  if [ ! -f "$conf" ]; then
    if [ -f "$dist" ]; then
      cp "$dist" "$conf"
    else
      echo "⚠️  dbimport.conf.dist not found; generating minimal dbimport.conf" >&2
      cat > "$conf" <<EOF
LoginDatabaseInfo = "localhost;3306;root;root;acore_auth"
WorldDatabaseInfo = "localhost;3306;root;root;acore_world"
CharacterDatabaseInfo = "localhost;3306;root;root;acore_characters"
PlayerbotsDatabaseInfo = "localhost;3306;root;root;acore_playerbots"
EnableDatabases = 15
Updates.AutoSetup = 1
MySQLExecutable = "/usr/bin/mysql"
TempDir = "/azerothcore/env/dist/temp"
EOF
    fi
  fi

  set_conf() {
    local key="$1" value="$2" file="$3" quoted="${4:-true}"
    local formatted="$value"
    if [ "$quoted" = "true" ]; then
      formatted="\"${value}\""
    fi
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
      sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${formatted}|" "$file"
    else
      printf '%s = %s\n' "$key" "$formatted" >> "$file"
    fi
  }

  local host="${CONTAINER_MYSQL:-${MYSQL_HOST:-localhost}}"
  local port="${MYSQL_PORT:-3306}"
  local user="${MYSQL_USER:-root}"
  local pass="${MYSQL_ROOT_PASSWORD:-root}"
  local db_auth="${DB_AUTH_NAME:-acore_auth}"
  local db_world="${DB_WORLD_NAME:-acore_world}"
  local db_chars="${DB_CHARACTERS_NAME:-acore_characters}"
  local db_bots="${DB_PLAYERBOTS_NAME:-acore_playerbots}"

  set_conf "LoginDatabaseInfo" "${host};${port};${user};${pass};${db_auth}" "$conf"
  set_conf "WorldDatabaseInfo" "${host};${port};${user};${pass};${db_world}" "$conf"
  set_conf "CharacterDatabaseInfo" "${host};${port};${user};${pass};${db_chars}" "$conf"
  set_conf "PlayerbotsDatabaseInfo" "${host};${port};${user};${pass};${db_bots}" "$conf"
  set_conf "EnableDatabases" "${AC_UPDATES_ENABLE_DATABASES:-15}" "$conf" false
  set_conf "Updates.AutoSetup" "${AC_UPDATES_AUTO_SETUP:-1}" "$conf" false
  set_conf "Updates.ExceptionShutdownDelay" "${AC_UPDATES_EXCEPTION_SHUTDOWN_DELAY:-10000}" "$conf" false
  set_conf "Updates.AllowedModules" "${DB_UPDATES_ALLOWED_MODULES:-all}" "$conf"
  set_conf "Updates.Redundancy" "${DB_UPDATES_REDUNDANCY:-1}" "$conf" false
  set_conf "Database.Reconnect.Seconds" "${DB_RECONNECT_SECONDS:-5}" "$conf" false
  set_conf "Database.Reconnect.Attempts" "${DB_RECONNECT_ATTEMPTS:-5}" "$conf" false
  set_conf "LoginDatabase.WorkerThreads" "${DB_LOGIN_WORKER_THREADS:-1}" "$conf" false
  set_conf "WorldDatabase.WorkerThreads" "${DB_WORLD_WORKER_THREADS:-1}" "$conf" false
  set_conf "CharacterDatabase.WorkerThreads" "${DB_CHARACTER_WORKER_THREADS:-1}" "$conf" false
  set_conf "LoginDatabase.SynchThreads" "${DB_LOGIN_SYNCH_THREADS:-1}" "$conf" false
  set_conf "WorldDatabase.SynchThreads" "${DB_WORLD_SYNCH_THREADS:-1}" "$conf" false
  set_conf "CharacterDatabase.SynchThreads" "${DB_CHARACTER_SYNCH_THREADS:-1}" "$conf" false
  set_conf "MySQLExecutable" "/usr/bin/mysql" "$conf"
  set_conf "TempDir" "$temp_dir" "$conf"
}

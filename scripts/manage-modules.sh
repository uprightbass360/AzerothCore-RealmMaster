#!/bin/bash

# Manifest-driven module management. Stages repositories, applies module
# metadata hooks, manages configuration files, and flags rebuild requirements.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MODULE_HELPER="$SCRIPT_DIR/modules.py"
DEFAULT_ENV_PATH="$PROJECT_ROOT/.env"
ENV_PATH="${MODULES_ENV_PATH:-$DEFAULT_ENV_PATH}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
PLAYERBOTS_DB_UPDATE_LOGGED=0
info(){ printf '%b\n' "${BLUE}ℹ️  $*${NC}"; }
ok(){ printf '%b\n' "${GREEN}✅ $*${NC}"; }
warn(){ printf '%b\n' "${YELLOW}⚠️  $*${NC}"; }
err(){ printf '%b\n' "${RED}❌ $*${NC}"; exit 1; }

ensure_python(){
  if ! command -v python3 >/dev/null 2>&1; then
    err "python3 is required but not installed in PATH"
  fi
}

resolve_manifest_path(){
  if [ -n "${MODULES_MANIFEST_PATH:-}" ] && [ -f "${MODULES_MANIFEST_PATH}" ]; then
    echo "${MODULES_MANIFEST_PATH}"
    return
  fi
  local candidate
  candidate="$PROJECT_ROOT/config/modules.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  candidate="$SCRIPT_DIR/../config/modules.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  candidate="/tmp/config/modules.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  err "Unable to locate module manifest (set MODULES_MANIFEST_PATH or ensure config/modules.json exists)"
}

setup_git_config(){
  info "Configuring git identity"
  git config --global user.name "${GIT_USERNAME:-ac-compose}" >/dev/null 2>&1 || true
  git config --global user.email "${GIT_EMAIL:-noreply@azerothcore.org}" >/dev/null 2>&1 || true
}

generate_module_state(){
  mkdir -p "$STATE_DIR"
  if ! python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$MANIFEST_PATH" generate --output-dir "$STATE_DIR"; then
    err "Module manifest validation failed"
  fi
  local env_file="$STATE_DIR/modules.env"
  if [ ! -f "$env_file" ]; then
    err "modules.env not produced at $env_file"
  fi
  # shellcheck disable=SC1090
  source "$env_file"
  if ! MODULE_SHELL_STATE="$(python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$MANIFEST_PATH" dump --format shell)"; then
    err "Unable to load manifest metadata"
  fi
  local eval_script
  eval_script="$(echo "$MODULE_SHELL_STATE" | sed 's/^declare -A /declare -gA /')"
  eval "$eval_script"
  IFS=' ' read -r -a MODULES_COMPILE_LIST <<< "${MODULES_COMPILE:-}"
  if [ "${#MODULES_COMPILE_LIST[@]}" -eq 1 ] && [ -z "${MODULES_COMPILE_LIST[0]}" ]; then
    MODULES_COMPILE_LIST=()
  fi
}

remove_disabled_modules(){
  for key in "${MODULE_KEYS[@]}"; do
    local dir
    dir="${MODULE_NAME[$key]:-}"
    [ -n "$dir" ] || continue
    if [ "${MODULE_ENABLED[$key]:-0}" != "1" ] && [ -d "$dir" ]; then
      info "Removing ${dir} (disabled)"
      rm -rf "$dir"
    fi
  done
}

run_post_install_hooks(){
  local key="$1"
  local dir="$2"
  local hooks_csv="${MODULE_POST_INSTALL[$key]:-}"
  IFS=',' read -r -a hooks <<< "$hooks_csv"
  for hook in "${hooks[@]}"; do
    [ -n "$hook" ] || continue
    case "$hook" in
      mod_ale_move_path_patch)
        apply_mod_ale_patch "$dir"
        ;;
      black_market_copy_lua)
        copy_black_market_lua "$dir"
        ;;
      *)
        warn "Unknown post-install hook '$hook' for ${MODULE_NAME[$key]:-}"
        ;;
    esac
  done
}

install_enabled_modules(){
  for key in "${MODULE_KEYS[@]}"; do
    if [ "${MODULE_ENABLED[$key]:-0}" != "1" ]; then
      continue
    fi
    local dir repo ref
    dir="${MODULE_NAME[$key]:-}"
    repo="${MODULE_REPO[$key]:-}"
    ref="${MODULE_REF[$key]:-}"
    if [ -z "$dir" ] || [ -z "$repo" ]; then
      warn "Missing repository metadata for $key"
      continue
    fi
    if [ -d "$dir/.git" ]; then
      info "$dir already present; skipping clone"
    elif [ -d "$dir" ]; then
      warn "$dir exists but is not a git repository; leaving in place"
    else
      info "Cloning ${dir} from ${repo}"
      if ! git clone "$repo" "$dir"; then
        err "Failed to clone $repo"
      fi
      if [ -n "$ref" ]; then
        (cd "$dir" && git checkout "$ref") || warn "Unable to checkout ref $ref for $dir"
      fi
    fi
    run_post_install_hooks "$key" "$dir"
  done
}

apply_mod_ale_patch(){
  local module_dir="$1"
  local target_file="$module_dir/src/LuaEngine/methods/CreatureMethods.h"
  if [ ! -f "$target_file" ]; then
    warn "mod-ale file missing for MovePath patch ($target_file)"
    return
  fi
  if grep -q 'MoveWaypoint(creature->GetWaypointPath(), true);' "$target_file"; then
    if sed -i 's/MoveWaypoint(creature->GetWaypointPath(), true);/MovePath(creature->GetWaypointPath(), FORCED_MOVEMENT_RUN);/' "$target_file"; then
      ok "Applied mod-ale MovePath compatibility fix"
    else
      warn "Failed to adjust mod-ale MovePath call"
    fi
  else
    info "mod-ale MovePath compatibility fix already present"
  fi
}

copy_black_market_lua(){
  local module_dir="$1"
  local source_dir="$module_dir/Server Files/lua_scripts"
  if [ ! -d "$source_dir" ]; then
    warn "Black Market Lua scripts not found at '$source_dir'"
    return
  fi
  local target="${MODULES_LUA_TARGET_DIR:-}"
  if [ -z "$target" ]; then
    if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
      target="${MODULES_ROOT}/lua_scripts"
    else
      target="/azerothcore/lua_scripts"
    fi
  fi
  if mkdir -p "$target" 2>/dev/null && cp -r "$source_dir/." "$target/" 2>/dev/null; then
    ok "Black Market Lua scripts copied to $target"
    return
  fi
  if [ -n "${MODULES_HOST_DIR:-}" ]; then
    target="${MODULES_HOST_DIR%/}/lua_scripts"
    if mkdir -p "$target" 2>/dev/null && cp -r "$source_dir/." "$target/" 2>/dev/null; then
      ok "Black Market Lua scripts staged to $target"
      return
    fi
  fi
  warn "Unable to copy Black Market Lua scripts to a writable location"
}

update_playerbots_db_info(){
  local target="$1"
  if [ ! -f "$target" ]; then
    return 0
  fi

  local host="${CONTAINER_MYSQL:-${MYSQL_HOST:-127.0.0.1}}"
  local port="${MYSQL_PORT:-3306}"
  local user="${MYSQL_USER:-root}"
  local pass="${MYSQL_ROOT_PASSWORD:-acore}"
  local db="${DB_PLAYERBOTS_NAME:-acore_playerbots}"
  local value="${host};${port};${user};${pass};${db}"

  if grep -qE '^[[:space:]]*PlayerbotsDatabaseInfo[[:space:]]*=' "$target"; then
    sed -i "s|^[[:space:]]*PlayerbotsDatabaseInfo[[:space:]]*=.*|PlayerbotsDatabaseInfo = \"${value}\"|" "$target" || return
  else
    printf '\nPlayerbotsDatabaseInfo = "%s"\n' "$value" >> "$target" || return
  fi

  if [ "$PLAYERBOTS_DB_UPDATE_LOGGED" = "0" ]; then
    info "Updated PlayerbotsDatabaseInfo to use host ${host}:${port}"
    PLAYERBOTS_DB_UPDATE_LOGGED=1
  fi

  return 0
}

manage_configuration_files(){
  echo 'Managing configuration files...'

  local env_target="${MODULES_ENV_TARGET_DIR:-}"
  if [ -z "$env_target" ]; then
    if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
      env_target="${MODULES_ROOT}/env/dist/etc"
    else
      env_target="/azerothcore/env/dist/etc"
    fi
  fi

  mkdir -p "$env_target"

  local key patterns_csv enabled pattern
  for key in "${MODULE_KEYS[@]}"; do
    enabled="${MODULE_ENABLED[$key]:-0}"
    patterns_csv="${MODULE_CONFIG_CLEANUP[$key]:-}"
    IFS=',' read -r -a patterns <<< "$patterns_csv"
    if [ "${#patterns[@]}" -eq 1 ] && [ -z "${patterns[0]}" ]; then
      unset patterns
      continue
    fi
    for pattern in "${patterns[@]}"; do
      [ -n "$pattern" ] || continue
      if [ "$enabled" != "1" ]; then
        rm -f "$env_target"/$pattern 2>/dev/null || true
      fi
    done
    unset patterns
  done

  local module_dir
  for key in "${MODULE_KEYS[@]}"; do
    module_dir="${MODULE_NAME[$key]:-}"
    [ -n "$module_dir" ] || continue
    [ -d "$module_dir" ] || continue
    find "$module_dir" -name "*.conf.dist" -exec cp {} "$env_target"/ \; 2>/dev/null || true
  done

  local modules_conf_dir="${env_target%/}/modules"
  mkdir -p "$modules_conf_dir"
  rm -f "$modules_conf_dir"/*.conf "$modules_conf_dir"/*.conf.dist 2>/dev/null || true
  for key in "${MODULE_KEYS[@]}"; do
    module_dir="${MODULE_NAME[$key]:-}"
    [ -n "$module_dir" ] || continue
    [ -d "$module_dir" ] || continue
    while IFS= read -r conf_file; do
      [ -n "$conf_file" ] || continue
      base_name="$(basename "$conf_file")"
      dest_name="${base_name%.dist}"
      cp "$conf_file" "$modules_conf_dir/$dest_name"
    done < <(find "$module_dir" -path "*/conf/*" -type f \( -name "*.conf" -o -name "*.conf.dist" \) 2>/dev/null)
  done

  local playerbots_enabled="${MODULE_PLAYERBOTS:-0}"
  if [ "${MODULE_ENABLED[MODULE_PLAYERBOTS]:-0}" = "1" ]; then
    playerbots_enabled=1
  fi

  if [ "$playerbots_enabled" = "1" ]; then
    update_playerbots_db_info "$env_target/playerbots.conf"
    update_playerbots_db_info "$env_target/playerbots.conf.dist"
    update_playerbots_db_info "$modules_conf_dir/playerbots.conf"
    update_playerbots_db_info "$modules_conf_dir/playerbots.conf.dist"
  fi

  if [ "${MODULE_AUTOBALANCE:-0}" = "1" ] && [ -f "$env_target/AutoBalance.conf.dist" ]; then
    sed -i 's/^AutoBalance\.LevelScaling\.EndGameBoost.*/AutoBalance.LevelScaling.EndGameBoost = false    # disabled pending proper implementation/' \
      "$env_target/AutoBalance.conf.dist" || true
  fi
}

load_sql_helper(){
  local helper_paths=(
    "/scripts/manage-modules-sql.sh"
    "/tmp/scripts/manage-modules-sql.sh"
  )

  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    helper_paths+=("$SCRIPT_DIR/manage-modules-sql.sh")
  fi

  local helper_path=""
  for helper_path in "${helper_paths[@]}"; do
    if [ -f "$helper_path" ]; then
      # shellcheck disable=SC1090
      . "$helper_path"
      SQL_HELPER_PATH="$helper_path"
      return 0
    fi
  done

  err "SQL helper not found; expected manage-modules-sql.sh to be available"
}

execute_module_sql(){
  SQL_EXECUTION_FAILED=0
  if declare -f execute_module_sql_scripts >/dev/null 2>&1; then
    echo 'Executing module SQL scripts...'
    if execute_module_sql_scripts; then
      echo 'SQL execution complete.'
    else
      echo '⚠️  Module SQL scripts reported errors'
      SQL_EXECUTION_FAILED=1
    fi
  else
    info "SQL helper did not expose execute_module_sql_scripts; skipping module SQL execution"
  fi
}

track_module_state(){
  echo 'Checking for module changes that require rebuild...'

  local modules_state_file
  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    modules_state_file="./.modules_state"
  else
    modules_state_file="/modules/.modules_state"
  fi

  local current_state=""
  for key in "${MODULE_KEYS[@]}"; do
    current_state+="${key}=${MODULE_ENABLED[$key]:-0}|"
  done

  local previous_state=""
  if [ -f "$modules_state_file" ]; then
    previous_state="$(cat "$modules_state_file")"
  fi

  local rebuild_required=0
  if [ "$current_state" != "$previous_state" ]; then
    if [ -n "$previous_state" ]; then
      echo "🔄 Module configuration has changed - rebuild required"
    else
      echo "📝 First run - establishing module state baseline"
    fi
    rebuild_required=1
  else
    echo "✅ No module changes detected"
  fi

  echo "$current_state" > "$modules_state_file"

  if [ "${#MODULES_COMPILE_LIST[@]}" -gt 0 ]; then
    echo "🔧 Detected ${#MODULES_COMPILE_LIST[@]} enabled C++ modules requiring compilation:"
    for mod in "${MODULES_COMPILE_LIST[@]}"; do
      echo "   • $mod"
    done
  else
    echo "✅ No C++ modules enabled - pre-built containers can be used"
  fi

  local rebuild_sentinel
  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    if [ -n "${LOCAL_STORAGE_SENTINEL_PATH:-}" ]; then
      rebuild_sentinel="${LOCAL_STORAGE_SENTINEL_PATH}"
    else
      rebuild_sentinel="./.requires_rebuild"
    fi
  else
    rebuild_sentinel="/modules/.requires_rebuild"
  fi

  local host_rebuild_sentinel=""
  if [ -n "${MODULES_HOST_DIR:-}" ]; then
    host_rebuild_sentinel="${MODULES_HOST_DIR%/}/.requires_rebuild"
  fi

  if [ "$rebuild_required" = "1" ] && [ "${#MODULES_COMPILE_LIST[@]}" -gt 0 ]; then
    printf '%s\n' "${MODULES_COMPILE_LIST[@]}" > "$rebuild_sentinel"
    if [ -n "$host_rebuild_sentinel" ]; then
      printf '%s\n' "${MODULES_COMPILE_LIST[@]}" > "$host_rebuild_sentinel" 2>/dev/null || true
    fi
    echo "🚨 Module changes detected; run ./scripts/rebuild-with-modules.sh to rebuild source images."
  else
    rm -f "$rebuild_sentinel" 2>/dev/null || true
    if [ -n "$host_rebuild_sentinel" ]; then
      rm -f "$host_rebuild_sentinel" 2>/dev/null || true
    fi
  fi
}

main(){
  ensure_python

  if [ "${MODULES_LOCAL_RUN:-0}" != "1" ]; then
    cd /modules || err "Modules directory /modules not found"
  fi
  MODULES_ROOT="$(pwd)"

  MANIFEST_PATH="$(resolve_manifest_path)"
  STATE_DIR="${MODULES_HOST_DIR:-$MODULES_ROOT}"

  setup_git_config
  generate_module_state
  remove_disabled_modules
  install_enabled_modules
  manage_configuration_files
  info "SQL execution gate: MODULES_SKIP_SQL=${MODULES_SKIP_SQL:-0}"
  if [ "${MODULES_SKIP_SQL:-0}" = "1" ]; then
    info "Skipping module SQL execution (MODULES_SKIP_SQL=1)"
  else
    info "Initiating module SQL helper"
    load_sql_helper
    info "SQL helper loaded from ${SQL_HELPER_PATH:-unknown}"
    execute_module_sql
  fi
  track_module_state

  if [ "${SQL_EXECUTION_FAILED:-0}" = "1" ]; then
    warn "Module SQL execution reported issues; review logs above."
  fi

  echo 'Module management complete.'

  if [ "${MODULES_DEBUG_KEEPALIVE:-0}" = "1" ]; then
    tail -f /dev/null
  fi
}

main "$@"

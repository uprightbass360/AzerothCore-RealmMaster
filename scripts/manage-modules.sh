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

# Declare module metadata arrays globally at script level
declare -A MODULE_NAME MODULE_REPO MODULE_REF MODULE_TYPE MODULE_ENABLED MODULE_NEEDS_BUILD MODULE_BLOCKED MODULE_POST_INSTALL MODULE_REQUIRES MODULE_CONFIG_CLEANUP MODULE_NOTES MODULE_STATUS MODULE_BLOCK_REASON
declare -a MODULE_KEYS

read_env_value(){
  local key="$1" default="${2:-}" value="${!key:-}"
  if [ -n "$value" ]; then
    echo "$value"
    return
  fi
  if [ -f "$ENV_PATH" ]; then
    value="$(grep -E "^${key}=" "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
    value="$(echo "$value" | sed 's/[[:space:]]*#.*//' | sed 's/[[:space:]]*$//')"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:-1}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:-1}"
    fi
  fi
  if [ -z "${value:-}" ]; then
    value="$default"
  fi
  printf '%s\n' "${value}"
}

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
  candidate="$PROJECT_ROOT/config/module-manifest.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  candidate="$SCRIPT_DIR/../config/module-manifest.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  candidate="/tmp/config/module-manifest.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  err "Unable to locate module manifest (set MODULES_MANIFEST_PATH or ensure config/module-manifest.json exists)"
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

  # Module arrays are already declared at script level
  if ! MODULE_SHELL_STATE="$(python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$MANIFEST_PATH" dump --format shell)"; then
    err "Unable to load manifest metadata"
  fi
  local eval_script
  # Remove the declare line since we already declared the arrays
  eval_script="$(echo "$MODULE_SHELL_STATE" | sed '/^declare -A /d')"
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

  # Skip if no hooks defined
  [ -n "$hooks_csv" ] || return 0

  IFS=',' read -r -a hooks <<< "$hooks_csv"
  local -a hook_search_paths=(
    "$SCRIPT_DIR/hooks"
    "/tmp/scripts/hooks"
    "/scripts/hooks"
  )

  for hook in "${hooks[@]}"; do
    [ -n "$hook" ] || continue

    # Trim whitespace
    hook="$(echo "$hook" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    local hook_script=""
    local candidate
    for candidate in "${hook_search_paths[@]}"; do
      if [ -x "$candidate/$hook" ]; then
        hook_script="$candidate/$hook"
        break
      fi
    done

    if [ -n "$hook_script" ]; then
      info "Running post-install hook: $hook"

      # Set hook environment variables
      export MODULE_KEY="$key"
      export MODULE_DIR="$dir"
      export MODULE_NAME="${MODULE_NAME[$key]:-$(basename "$dir")}"
      export MODULES_ROOT="${MODULES_ROOT:-/modules}"
      export LUA_SCRIPTS_TARGET="/azerothcore/lua_scripts"

      # Execute the hook script
      if "$hook_script"; then
        ok "Hook '$hook' completed successfully"
      else
        local exit_code=$?
        case $exit_code in
          1) warn "Hook '$hook' completed with warnings" ;;
          *) err "Hook '$hook' failed with exit code $exit_code" ;;
        esac
      fi

      # Clean up hook-specific environment (preserve MODULE_NAME array and script-level MODULES_ROOT)
      unset MODULE_KEY MODULE_DIR LUA_SCRIPTS_TARGET
    else
      err "Hook script not found for ${hook} (searched: ${hook_search_paths[*]})"
    fi
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


update_playerbots_db_info(){
  local target="$1"
  if [ ! -f "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  local env_file="${ENV_PATH:-}"
  local resolved

  resolved="$(
    python3 - "$target" "${env_file}" <<'PY'
import os
import pathlib
import sys
import re

def load_env_file(path):
    data = {}
    if not path:
        return data
    candidate = pathlib.Path(path)
    if not candidate.is_file():
        return data
    for raw in candidate.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not raw or raw.lstrip().startswith("#"):
            continue
        if "=" not in raw:
            continue
        key, val = raw.split("=", 1)
        key = key.strip()
        val = val.strip()
        if not key:
            continue
        if val and val[0] == val[-1] and val[0] in {"'", '"'}:
            val = val[1:-1]
        if "#" in val:
            # Strip inline comments
            val = val.split("#", 1)[0].rstrip()
        data[key] = val
    return data

def resolve_key(env_map, key, default=""):
    value = os.environ.get(key)
    if value:
        return value
    return env_map.get(key, default)

def parse_bool(value):
    if value is None:
        return None
    value = value.strip().lower()
    if value == "":
        return None
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    return None

def parse_int(value):
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if re.fullmatch(r"[+-]?\d+", value):
        return str(int(value))
    return None

def update_config(path_in, settings):
    if not (os.path.exists(path_in) or os.path.islink(path_in)):
        return False
    path = os.path.realpath(path_in)
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        lines = []

    changed = False
    pending = dict(settings)

    for idx, raw in enumerate(lines):
        stripped = raw.strip()
        for key, value in list(pending.items()):
            if re.match(rf"^\s*{re.escape(key)}\s*=", stripped):
                desired = f"{key} = {value}"
                if stripped != desired:
                    leading = raw[: len(raw) - len(raw.lstrip())]
                    trailing = ""
                    if "#" in raw:
                        before, comment = raw.split("#", 1)
                        if before.strip():
                            trailing = f"  # {comment.strip()}"
                    lines[idx] = f"{leading}{desired}{trailing}"
                    changed = True
                pending.pop(key, None)
                break

    if pending:
        if lines and lines[-1] and not lines[-1].endswith("\n"):
            lines[-1] = lines[-1] + "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        for key, value in pending.items():
            lines.append(f"{key} = {value}\n")
        changed = True

    if changed:
        output = "\n".join(lines)
        if output and not output.endswith("\n"):
            output += "\n"
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(output)

    return True

target_path, env_path = sys.argv[1:3]
env_map = load_env_file(env_path)

host = resolve_key(env_map, "CONTAINER_MYSQL") or resolve_key(env_map, "MYSQL_HOST", "ac-mysql") or "ac-mysql"
port = resolve_key(env_map, "MYSQL_PORT", "3306") or "3306"
user = resolve_key(env_map, "MYSQL_USER", "root") or "root"
password = resolve_key(env_map, "MYSQL_ROOT_PASSWORD", "")
database = resolve_key(env_map, "DB_PLAYERBOTS_NAME", "acore_playerbots") or "acore_playerbots"

value = ";".join([host, port, user, password, database])
settings = {"PlayerbotsDatabaseInfo": f'"{value}"'}

enabled_setting = parse_bool(resolve_key(env_map, "PLAYERBOT_ENABLED"))
if enabled_setting is not None:
    settings["AiPlayerbot.Enabled"] = "1" if enabled_setting else "0"

max_bots = parse_int(resolve_key(env_map, "PLAYERBOT_MAX_BOTS"))
min_bots = parse_int(resolve_key(env_map, "PLAYERBOT_MIN_BOTS"))

if max_bots and not min_bots:
    min_bots = max_bots

if min_bots:
    settings["AiPlayerbot.MinRandomBots"] = min_bots
if max_bots:
    settings["AiPlayerbot.MaxRandomBots"] = max_bots

update_config(target_path, settings)

print(value)
PY
  )" || return 0

  local host port
  host="${resolved%%;*}"
  port="${resolved#*;}"
  port="${port%%;*}"

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

  local modules_conf_dir="${env_target%/}/modules"
  mkdir -p "$modules_conf_dir"
  rm -rf "${modules_conf_dir}.backup"
  rm -f "$modules_conf_dir"/*.conf "$modules_conf_dir"/*.conf.dist 2>/dev/null || true

  local module_dir
  for key in "${MODULE_KEYS[@]}"; do
    module_dir="${MODULE_NAME[$key]:-}"
    [ -n "$module_dir" ] || continue
    [ -d "$module_dir" ] || continue
    while IFS= read -r conf_file; do
      [ -n "$conf_file" ] || continue
      base_name="$(basename "$conf_file")"
      # Ensure previous copies in root config are removed to keep modules/ canonical
      main_conf_path="${env_target}/${base_name}"
      if [ -f "$main_conf_path" ]; then
        rm -f "$main_conf_path"
      fi
      if [[ "$base_name" == *.conf.dist ]]; then
        root_conf="${env_target}/${base_name%.dist}"
        if [ -f "$root_conf" ]; then
          rm -f "$root_conf"
        fi
      fi

      dest_path="${modules_conf_dir}/${base_name}"
      cp "$conf_file" "$dest_path"
      if [[ "$base_name" == *.conf.dist ]]; then
        dest_conf="${modules_conf_dir}/${base_name%.dist}"
        if [ ! -f "$dest_conf" ]; then
          cp "$conf_file" "$dest_conf"
        fi
      fi
    done < <(find "$module_dir" -path "*/conf/*" -type f \( -name "*.conf" -o -name "*.conf.dist" \) 2>/dev/null)
  done

  local playerbots_enabled="${MODULE_PLAYERBOTS:-0}"
  if [ "${MODULE_ENABLED[MODULE_PLAYERBOTS]:-0}" = "1" ]; then
    playerbots_enabled=1
  fi

  if [ "$playerbots_enabled" = "1" ]; then
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

  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    local target_dir="${MODULES_HOST_DIR:-$(pwd)}"
    local desired_user
    desired_user="$(id -u):$(id -g)"
    if [ -d "$target_dir" ]; then
      chown -R "$desired_user" "$target_dir" >/dev/null 2>&1 || true
      chmod -R ug+rwX "$target_dir" >/dev/null 2>&1 || true
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

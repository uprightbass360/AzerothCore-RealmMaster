#!/bin/bash

# Manifest-driven module management. Stages repositories, applies module
# metadata hooks, manages configuration files, and flags rebuild requirements.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common library for shared functions
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  source "$SCRIPT_DIR/lib/common.sh"
else
  echo "ERROR: Common library not found at $SCRIPT_DIR/lib/common.sh" >&2
  exit 1
fi

# Source project name helper
source "$PROJECT_ROOT/scripts/bash/project_name.sh"

# Module-specific configuration
MODULE_HELPER="$PROJECT_ROOT/scripts/python/modules.py"
DEFAULT_ENV_PATH="$PROJECT_ROOT/.env"
ENV_PATH="${MODULES_ENV_PATH:-$DEFAULT_ENV_PATH}"
TEMPLATE_FILE="$PROJECT_ROOT/.env.template"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_PATH" "$TEMPLATE_FILE")"

# Module-specific state
PLAYERBOTS_DB_UPDATE_LOGGED=0
MODULES_INSTALL_FAILED=0
declare -a HOOK_FAILURES=()

# Declare module metadata arrays globally at script level
declare -A MODULE_NAME MODULE_REPO MODULE_REF MODULE_TYPE MODULE_ENABLED MODULE_NEEDS_BUILD MODULE_BLOCKED MODULE_POST_INSTALL MODULE_REQUIRES MODULE_CONFIG_CLEANUP MODULE_NOTES MODULE_STATUS MODULE_BLOCK_REASON
declare -a MODULE_KEYS

# Ensure Python is available
require_cmd python3

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
  candidate="/tmp/config/module-manifest.json"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return
  fi
  fatal "Unable to locate module manifest (set MODULES_MANIFEST_PATH or ensure config/module-manifest.json exists)"
}

setup_git_config(){
  info "Configuring git identity"
  git config --global user.name "${GIT_USERNAME:-$DEFAULT_PROJECT_NAME}" >/dev/null 2>&1 || true
  git config --global user.email "${GIT_EMAIL:-noreply@azerothcore.org}" >/dev/null 2>&1 || true
}

generate_module_state(){
  mkdir -p "$STATE_DIR"
  # modules.py writes modules.env before reporting validation errors, so a
  # failure here must stop the run rather than continue on invalid state.
  if ! python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$MANIFEST_PATH" generate --output-dir "$STATE_DIR"; then
    fatal "Module manifest validation failed"
  fi
  local env_file="$STATE_DIR/modules.env"
  if [ ! -f "$env_file" ]; then
    fatal "modules.env not produced at $env_file"
  fi
  # shellcheck disable=SC1090
  source "$env_file"

  # Module arrays are already declared at script level
  if ! MODULE_SHELL_STATE="$(python3 "$MODULE_HELPER" --env-path "$ENV_PATH" --manifest "$MANIFEST_PATH" dump --format shell)"; then
    fatal "Unable to load manifest metadata"
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
  # Several manifest entries can share a clone directory (a module and its
  # forks, e.g. MODULE_PLAYERBOTS and MODULE_MOD_PLAYERBOTS -> mod-playerbots).
  # Never remove a directory an enabled entry still uses.
  local -A enabled_dirs=()
  local key
  for key in "${MODULE_KEYS[@]}"; do
    if [ "${MODULE_ENABLED[$key]:-0}" = "1" ] && [ -n "${MODULE_NAME[$key]:-}" ]; then
      enabled_dirs["${MODULE_NAME[$key]}"]=1
    fi
  done

  for key in "${MODULE_KEYS[@]}"; do
    local dir
    dir="${MODULE_NAME[$key]:-}"
    [ -n "$dir" ] || continue
    [ "${MODULE_ENABLED[$key]:-0}" != "1" ] || continue
    [ -z "${enabled_dirs[$dir]:-}" ] || continue
    if [ -d "$dir" ]; then
      info "Removing ${dir} (disabled)"
      rm -rf "$dir"
    fi
  done
}

# Lua hooks stage into $LUA_SCRIPTS_TARGET/<module name>/. Clear every module's
# folder before the hooks run so the result matches this run exactly: disabled
# modules and modules whose Lua hook was dropped from the manifest disappear,
# and enabled ones are re-staged by their hooks. Files and folders not named
# after a manifest module (e.g. hand-placed scripts) are left alone.
reset_staged_lua(){
  [ -n "${LUA_SCRIPTS_TARGET:-}" ] || return 0
  [ -d "$LUA_SCRIPTS_TARGET" ] || return 0
  local key dir removed=0
  for key in "${MODULE_KEYS[@]}"; do
    dir="${MODULE_NAME[$key]:-}"
    case "$dir" in ""|*/*|.|..) continue;; esac
    if [ -d "$LUA_SCRIPTS_TARGET/$dir" ]; then
      rm -rf "${LUA_SCRIPTS_TARGET:?}/$dir"
      removed=$((removed + 1))
    fi
  done
  if [ "$removed" -gt 0 ]; then
    info "Cleared ${removed} staged Lua folder(s); enabled modules are re-staged below"
  fi
}

run_post_install_hooks(){
  local key="$1"
  local dir="$2"
  local hooks_csv="${MODULE_POST_INSTALL[$key]:-}"

  # Skip if no hooks defined
  [ -n "$hooks_csv" ] || return 0

  IFS=',' read -r -a hooks <<< "$hooks_csv"
  local -a hook_search_paths=(
    "$PROJECT_ROOT/scripts/hooks"
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

      # Hook environment is passed via env(1): MODULE_NAME is an associative
      # array in this shell, so exporting it would never reach the hook.
      # LUA_SCRIPTS_TARGET is only set inside ac-modules (the storage/lua_scripts
      # mount); host-side runs leave it empty and Lua hooks skip staging.
      if env \
        MODULE_KEY="$key" \
        MODULE_DIR="$dir" \
        MODULE_NAME="${MODULE_NAME[$key]:-$(basename "$dir")}" \
        MODULES_ROOT="${MODULES_ROOT:-/modules}" \
        LUA_SCRIPTS_TARGET="${LUA_SCRIPTS_TARGET:-}" \
        STACK_SOURCE_VARIANT="${STACK_SOURCE_VARIANT:-}" \
        MODULES_REBUILD_SOURCE_PATH="${MODULES_REBUILD_SOURCE_PATH:-}" \
        "$hook_script"; then
        ok "Hook '$hook' completed successfully"
      else
        local exit_code=$?
        case $exit_code in
          1) warn "Hook '$hook' completed with warnings" ;;
          *)
            err "Hook '$hook' failed with exit code $exit_code"
            HOOK_FAILURES+=("${MODULE_NAME[$key]:-$key}: $hook (exit $exit_code)")
            ;;
        esac
      fi
    else
      err "Hook script not found for ${hook} (searched: ${hook_search_paths[*]})"
      HOOK_FAILURES+=("${MODULE_NAME[$key]:-$key}: $hook (hook not found)")
    fi
  done
}

# Checkout a pinned ref after a clone, warning on failure.
checkout_module_ref(){
  local dir="$1"
  local ref="$2"
  [ -n "$ref" ] || return 0
  (cd "$dir" && git checkout "$ref") || warn "Unable to checkout ref $ref for $dir"
}

# Replace an existing module directory with a fresh clone. The old directory is
# moved aside first and restored if the clone fails. Returns non-zero when the
# directory could not be replaced.
reclone_module_fresh(){
  local dir="$1"
  local repo="$2"
  local ref="$3"
  local stale_dir="${dir}.stale.$$"
  if ! mv "$dir" "$stale_dir" 2>/dev/null; then
    warn "Cannot replace $dir (parent directory not writable); leaving existing directory. Run scripts/bash/repair-storage-permissions.sh"
    return 1
  fi
  if git clone "$repo" "$dir"; then
    ok "$dir re-cloned fresh from remote"
    if ! rm -rf "$stale_dir" 2>/dev/null && command -v docker >/dev/null 2>&1; then
      docker run --rm -v "$(pwd)":/work -w /work "${ALPINE_IMAGE:-alpine:latest}" \
        rm -rf "$stale_dir" >/dev/null 2>&1 || true
    fi
    if [ -d "$stale_dir" ]; then
      warn "Could not remove old checkout at $stale_dir; remove it manually"
    fi
    checkout_module_ref "$dir" "$ref"
    return 0
  fi
  err "Failed to re-clone $repo; restoring previous checkout"
  mv "$stale_dir" "$dir" 2>/dev/null || err "Could not restore $dir from $stale_dir"
  return 1
}

# Compare repo URLs ignoring case, scheme, trailing slashes and ".git"
# (matches normalize_repo in scripts/python/local_modules.py).
normalize_repo_url(){
  local url="${1,,}"
  if [[ "$url" =~ ^[a-z]+:// ]]; then
    url="${url#*://}"
  fi
  while [[ "$url" == */ ]]; do url="${url%/}"; done
  url="${url%.git}"
  while [[ "$url" == */ ]]; do url="${url%/}"; done
  printf '%s' "$url"
}

install_enabled_modules(){
  local -a install_failures=()

  # A stack that never builds locally (prebuilt/registry images) has no
  # local-storage/modules dir, so stage-modules.sh's sync never runs and
  # .built-locally never arrives here - its module checkouts must keep
  # following their repos on every deploy, same as before the held-checkout
  # behaviour below existed. Only a local build's checkout is held in place.
  local container_holds_builds=0
  if [ "${MODULES_LOCAL_RUN:-0}" != "1" ] && [ -f "${MODULES_ROOT:-}/.built-locally" ]; then
    container_holds_builds=1
  fi

  for key in "${MODULE_KEYS[@]}"; do
    if [ "${MODULE_ENABLED[$key]:-0}" != "1" ]; then
      continue
    fi
    local dir repo ref current_origin
    dir="${MODULE_NAME[$key]:-}"
    repo="${MODULE_REPO[$key]:-}"
    ref="${MODULE_REF[$key]:-}"
    if [ -z "$dir" ] || [ -z "$repo" ]; then
      warn "Missing repository metadata for $key"
      continue
    fi
    if [ "${MODULES_FORCE_RECLONE:-0}" = "1" ] && [ -d "$dir" ]; then
      info "MODULES_FORCE_RECLONE=1: re-cloning $dir fresh"
      reclone_module_fresh "$dir" "$repo" "$ref" || install_failures+=("$dir")
    elif [ "$container_holds_builds" = "1" ] && [ "${MODULE_NEEDS_BUILD[$key]:-0}" = "1" ] && [ -d "$dir/.git" ]; then
      # build.sh stages the compiled checkouts into local-storage/modules and
      # stage-modules.sh syncs them to storage/modules before containers
      # start, so the container already has the built version; pulling it (or
      # re-cloning it on an origin change) here would stage SQL/config newer
      # than the compiled binary.
      info "$dir is compiled into the server; keeping the built checkout"
    elif [ -d "$dir/.git" ] && current_origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)" \
      && [ "$(normalize_repo_url "$current_origin")" != "$(normalize_repo_url "$repo")" ]; then
      # The module's repo changed (e.g. a fork override added or removed).
      info "$dir origin changed (${current_origin} -> ${repo}); re-cloning"
      reclone_module_fresh "$dir" "$repo" "$ref" || install_failures+=("$dir")
    elif [ -d "$dir/.git" ]; then
      info "$dir already present; checking for updates"
      (cd "$dir" && git fetch origin >/dev/null 2>&1) || warn "Failed to fetch updates for $dir"
      local head_before head_after
      head_before=$(cd "$dir" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      local update_failed=0
      if [ -n "$ref" ]; then
        # Pinned module: check out the ref directly, never pull a branch
        if (cd "$dir" && git checkout --quiet "$ref" >/dev/null 2>&1); then
          head_after=$(cd "$dir" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
          if [ "$head_after" = "$head_before" ]; then
            info "$dir is already at pinned ref ${head_after}"
          else
            ok "$dir moved to pinned ref (${head_before} -> ${head_after})"
          fi
        else
          update_failed=1
        fi
      else
        local current_branch
        current_branch=$(cd "$dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")
        if (cd "$dir" && git pull origin "$current_branch" >/dev/null 2>&1); then
          head_after=$(cd "$dir" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
          if [ "$head_after" = "$head_before" ]; then
            info "$dir is already up to date"
          else
            ok "$dir updated from remote (${head_before} -> ${head_after})"
          fi
        else
          update_failed=1
        fi
      fi
      if [ "$update_failed" -eq 1 ]; then
        warn "Failed to update $dir (checkout stuck at ${head_before}); re-cloning fresh"
        reclone_module_fresh "$dir" "$repo" "$ref" || true
      fi
    elif [ -d "$dir" ]; then
      # A directory without .git is a leftover from an interrupted clone or
      # partial sync; recover it instead of leaving the module missing.
      if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        info "$dir exists but is empty; cloning ${dir} from ${repo}"
        if git clone "$repo" "$dir"; then
          checkout_module_ref "$dir" "$ref"
        else
          err "Failed to clone $repo"
          install_failures+=("$dir")
        fi
      else
        warn "$dir exists but is not a git repository; re-cloning fresh"
        reclone_module_fresh "$dir" "$repo" "$ref" || install_failures+=("$dir")
      fi
    else
      info "Cloning ${dir} from ${repo}"
      if git clone "$repo" "$dir"; then
        checkout_module_ref "$dir" "$ref"
      else
        err "Failed to clone $repo"
        install_failures+=("$dir")
      fi
    fi
    # A failed first clone leaves no directory; its failure is already recorded.
    if [ -d "$dir" ]; then
      run_post_install_hooks "$key" "$dir"
    fi
  done

  if [ "${#install_failures[@]}" -gt 0 ]; then
    err "Failed to install ${#install_failures[@]} module(s): ${install_failures[*]}"
    err "Check network access to github.com and re-run to retry."
    MODULES_INSTALL_FAILED=1
  fi
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

}

load_sql_helper(){
  local helper_paths=(
    "/scripts/bash/manage-modules-sql.sh"
    "/tmp/scripts/bash/manage-modules-sql.sh"
  )

  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    helper_paths+=("$PROJECT_ROOT/scripts/bash/manage-modules-sql.sh")
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

# REMOVED: stage_module_sql_files() and execute_module_sql()
# These functions were part of build-time SQL staging that created files in
# /azerothcore/modules/*/data/sql/updates/ which are NEVER scanned by AzerothCore's DBUpdater.
# Module SQL is now staged at runtime by stage-modules.sh which copies files to
# /azerothcore/data/sql/updates/ (core directory) where they ARE scanned and processed.


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

  # Only the host-side run (build.sh) signals rebuilds: build.sh and deploy.sh
  # read the sentinel from local storage and compare the enabled C++ modules with
  # the last build's record (lib/module-build-record.sh). A sentinel written by
  # the ac-modules container landed in storage/modules, where nothing read it,
  # and would arrive after deploy.sh had already chosen its images anyway.
  if [ "${MODULES_LOCAL_RUN:-0}" != "1" ]; then
    return 0
  fi

  local rebuild_sentinel
  if [ -n "${LOCAL_STORAGE_SENTINEL_PATH:-}" ]; then
    rebuild_sentinel="${LOCAL_STORAGE_SENTINEL_PATH}"
  else
    rebuild_sentinel="./.requires_rebuild"
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
    echo "🚨 Module changes detected; run ./scripts/bash/rebuild-with-modules.sh to rebuild source images."
  else
    rm -f "$rebuild_sentinel" 2>/dev/null || true
    if [ -n "$host_rebuild_sentinel" ]; then
      rm -f "$host_rebuild_sentinel" 2>/dev/null || true
    fi
  fi

  local target_dir="${MODULES_HOST_DIR:-$(pwd)}"
  local desired_user
  desired_user="$(id -u):$(id -g)"
  if [ -d "$target_dir" ]; then
    chown -R "$desired_user" "$target_dir" >/dev/null 2>&1 || true
    chmod -R ug+rwX "$target_dir" >/dev/null 2>&1 || true
  fi
}

# Hook failures (exit >= 2, or a hook named in the manifest that doesn't exist).
# Host-side runs prepare sources for build.sh, so a failure stops the build.
# ac-modules runs record them for stage-modules.sh to report at the end of the
# deploy instead of failing the container: the worldserver doesn't wait on
# ac-modules, so failing it would only block ac-post-install (first-install
# realm setup).
report_hook_failures(){
  local record="${STATE_DIR%/}/.modules-meta/hook-failures.txt"
  if [ "${#HOOK_FAILURES[@]}" -eq 0 ]; then
    rm -f "$record" 2>/dev/null || true
    return 0
  fi

  err "${#HOOK_FAILURES[@]} post-install hook(s) failed:"
  printf '   - %s\n' "${HOOK_FAILURES[@]}" >&2

  if [ "${MODULES_LOCAL_RUN:-0}" = "1" ]; then
    fatal "Post-install hook failures; aborting before the build"
  fi

  if ! { mkdir -p "$(dirname "$record")" && printf '%s\n' "${HOOK_FAILURES[@]}" > "$record"; }; then
    warn "Could not record hook failures at $record"
  fi
}

main(){
  # Python is already checked at script start via require_cmd

  if [ "${MODULES_LOCAL_RUN:-0}" != "1" ]; then
    cd /modules || fatal "Modules directory /modules not found"
  fi
  MODULES_ROOT="$(pwd)"

  MANIFEST_PATH="$(resolve_manifest_path)"
  STATE_DIR="${MODULES_HOST_DIR:-$MODULES_ROOT}"

  setup_git_config
  generate_module_state
  remove_disabled_modules
  reset_staged_lua
  install_enabled_modules
  manage_configuration_files
  # NOTE: Module SQL staging is now handled at runtime by stage-modules.sh
  # which copies SQL files to /azerothcore/data/sql/updates/ after containers start.
  # Build-time SQL staging has been removed as it created files that were never processed.

  track_module_state
  report_hook_failures

  if [ "${MODULES_INSTALL_FAILED:-0}" = "1" ]; then
    fatal "Module management finished with clone failures; see errors above"
  fi

  echo 'Module management complete.'

  if [ "${MODULES_DEBUG_KEEPALIVE:-0}" = "1" ]; then
    tail -f /dev/null
  fi
}

# Tests source this file for its functions; only run main when executed.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

# Summary, path setup, and output helpers for setup.sh

print_summary() {
  # setup.sh -> scripts/bash/setup/ui.sh (say)
  local SUMMARY_MODE_TEXT="$MODULE_MODE_LABEL"
  if [ -z "$SUMMARY_MODE_TEXT" ]; then
    SUMMARY_MODE_TEXT="${CLI_MODULE_MODE:-}"
  fi

  say HEADER "SUMMARY"
  printf "  %-18s %s\n" "Server Address:" "$SERVER_ADDRESS"
  printf "  %-18s Realm:%s  Auth:%s  SOAP:%s  MySQL:%s\n" "Ports:" "$REALM_PORT" "$AUTH_EXTERNAL_PORT" "$SOAP_EXTERNAL_PORT" "$MYSQL_EXTERNAL_PORT"
  printf "  %-18s %s\n" "Storage Path:" "$STORAGE_PATH"
  printf "  %-18s %s\n" "Container User:" "$CONTAINER_USER"
  printf "  %-18s Daily %s:00 UTC, keep %sd/%sh\n" "Backups:" "$BACKUP_DAILY_TIME" "$BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_HOURS"
  printf "  %-18s %s\n" "Modules images:" "$DEFAULT_AUTH_IMAGE_MODULES | $DEFAULT_WORLD_IMAGE_MODULES"

  printf "  %-18s %s\n" "Modules preset:" "$SUMMARY_MODE_TEXT"
  printf "  %-18s %s\n" "Playerbot Min Bots:" "$PLAYERBOT_MIN_BOTS"
  printf "  %-18s %s\n" "Playerbot Max Bots:" "$PLAYERBOT_MAX_BOTS"
  printf "  %-18s" "Enabled Modules:"
  local enabled_modules=()
  for module_var in "${MODULE_KEYS[@]}"; do
    eval "value=\${$module_var:-0}"
    if [ "$value" = "1" ]; then
      enabled_modules+=("${module_var#MODULE_}")
    fi
  done

  if [ ${#enabled_modules[@]} -eq 0 ]; then
    printf " none\n"
  else
    printf "\n"
    for module in "${enabled_modules[@]}"; do
      printf "                     • %s\n" "$module"
    done
  fi
  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    printf "  %-18s detected (source rebuild required)\n" "C++ modules:"
  fi
}

configure_local_storage_paths() {
  LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-./local-storage}"
  LOCAL_STORAGE_ROOT="${LOCAL_STORAGE_ROOT%/}"
  [ -z "$LOCAL_STORAGE_ROOT" ] && LOCAL_STORAGE_ROOT="."
  LOCAL_STORAGE_ROOT_ABS="$LOCAL_STORAGE_ROOT"
  if [[ "$LOCAL_STORAGE_ROOT_ABS" != /* ]]; then
    LOCAL_STORAGE_ROOT_ABS="$SCRIPT_DIR/${LOCAL_STORAGE_ROOT_ABS#./}"
  fi
  LOCAL_STORAGE_ROOT_ABS="${LOCAL_STORAGE_ROOT_ABS%/}"
  STORAGE_PATH_LOCAL="$LOCAL_STORAGE_ROOT"

  export STORAGE_PATH STORAGE_PATH_LOCAL
  local module_export_var
  for module_export_var in "${MODULE_KEYS[@]}"; do
    export "$module_export_var"
  done
}

handle_rebuild_sentinel() {
  # setup.sh -> scripts/bash/setup/ui.sh (say)
  if [ "$NEEDS_CXX_REBUILD" != "1" ]; then
    return 0
  fi

  echo ""
  say WARNING "These modules require compiling AzerothCore from source."
  say INFO "Run './build.sh' to compile your custom modules before deployment."

  local sentinel="$LOCAL_STORAGE_ROOT_ABS/modules/.requires_rebuild"
  mkdir -p "$(dirname "$sentinel")"
  if touch "$sentinel" 2>/dev/null; then
    say INFO "Build sentinel created at $sentinel"
    return 0
  fi

  say WARNING "Could not create build sentinel at $sentinel (permissions/ownership); forcing with sudo..."
  if command -v sudo >/dev/null 2>&1; then
    if sudo mkdir -p "$(dirname "$sentinel")" \
      && sudo chown -R "$(id -u):$(id -g)" "$(dirname "$sentinel")" \
      && sudo touch "$sentinel"; then
      say INFO "Build sentinel created at $sentinel (after fixing ownership)"
    else
      say ERROR "Failed to force build sentinel creation at $sentinel. Fix permissions and rerun setup."
      exit 1
    fi
  else
    say ERROR "Cannot force build sentinel creation (sudo unavailable). Fix permissions on $(dirname "$sentinel") and rerun setup."
    exit 1
  fi
}

set_rebuild_source_path() {
  local default_source_rel="${LOCAL_STORAGE_ROOT}/source/azerothcore"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    default_source_rel="${LOCAL_STORAGE_ROOT}/source/azerothcore-playerbots"
  fi

  # Persist rebuild source path for downstream build scripts
  MODULES_REBUILD_SOURCE_PATH="$default_source_rel"
}

print_final_next_steps() {
  say INFO "Ready to bring your realm online:"
  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    printf '  🔨 First, build custom modules: ./build.sh\n'
    printf '  🚀 Then deploy your realm: ./deploy.sh\n'
  else
    printf '  🚀 Quick deploy: ./deploy.sh\n'
  fi
}

# Interactive configuration flow for setup.sh

select_deployment_type() {
  # setup.sh -> scripts/bash/setup/ui.sh (say)
  say HEADER "DEPLOYMENT TYPE"
  echo "1) 🏠 Local Development (${DEFAULT_LOCAL_ADDRESS})"
  echo "2) 🌐 LAN Server (local network IP) (autodetect)"
  echo "3) ☁️ Public Server (domain or public IP) (manual)"
  local DEPLOYMENT_TYPE_INPUT="${CLI_DEPLOYMENT_TYPE}"
  if [ "$NON_INTERACTIVE" = "1" ] && [ -z "$DEPLOYMENT_TYPE_INPUT" ]; then
    DEPLOYMENT_TYPE_INPUT="local"
  fi
  while true; do
    if [ -z "$DEPLOYMENT_TYPE_INPUT" ]; then
      read -p "$(echo -e "${YELLOW}🔧 Select deployment type [1-3]: ${NC}")" DEPLOYMENT_TYPE_INPUT
    fi
    case "${DEPLOYMENT_TYPE_INPUT,,}" in
      1|local)
        DEPLOYMENT_TYPE=local
        ;;
      2|lan)
        DEPLOYMENT_TYPE=lan
        ;;
      3|public)
        DEPLOYMENT_TYPE=public
        ;;
      *)
        if [ -n "$CLI_DEPLOYMENT_TYPE" ] || [ "$NON_INTERACTIVE" = "1" ]; then
          say ERROR "Invalid deployment type: ${DEPLOYMENT_TYPE_INPUT}"
          exit 1
        fi
        say ERROR "Please select 1, 2, or 3"
        DEPLOYMENT_TYPE_INPUT=""
        continue
        ;;
    esac
    break
  done
  if [ -n "$CLI_DEPLOYMENT_TYPE" ] || [ "$NON_INTERACTIVE" = "1" ]; then
    say INFO "Deployment type set to ${DEPLOYMENT_TYPE}."
  fi
}

configure_server() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask, validate_ip, validate_port)
  say HEADER "SERVER CONFIGURATION"
  if [ -n "$CLI_SERVER_ADDRESS" ]; then
    SERVER_ADDRESS="$CLI_SERVER_ADDRESS"
  elif [ "$DEPLOYMENT_TYPE" = "local" ]; then
    SERVER_ADDRESS=$DEFAULT_LOCAL_ADDRESS
  elif [ "$DEPLOYMENT_TYPE" = "lan" ]; then
    local LAN_IP
    LAN_IP=$(ip route get $ROUTE_DETECTION_IP 2>/dev/null | awk 'NR==1{print $7}')
    SERVER_ADDRESS=$(ask "Enter server IP address" "${CLI_SERVER_ADDRESS:-${LAN_IP:-$DEFAULT_FALLBACK_LAN_IP}}" validate_ip)
  else
    SERVER_ADDRESS=$(ask "Enter server address (IP or domain)" "${CLI_SERVER_ADDRESS:-$DEFAULT_DOMAIN_PLACEHOLDER}" )
  fi

  REALM_PORT=$(ask "Enter client connection port" "${CLI_REALM_PORT:-$DEFAULT_REALM_PORT}" validate_port)
  AUTH_EXTERNAL_PORT=$(ask "Enter auth server port" "${CLI_AUTH_PORT:-$DEFAULT_AUTH_PORT}" validate_port)
  SOAP_EXTERNAL_PORT=$(ask "Enter SOAP API port" "${CLI_SOAP_PORT:-$DEFAULT_SOAP_PORT}" validate_port)
  MYSQL_EXTERNAL_PORT=$(ask "Enter MySQL external port" "${CLI_MYSQL_PORT:-$DEFAULT_MYSQL_PORT}" validate_port)
}

choose_permission_scheme() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask, validate_number)
  say HEADER "PERMISSION SCHEME"
  local CURRENT_UID CURRENT_GID CURRENT_USER_PAIR CURRENT_USER_NAME CURRENT_GROUP_NAME
  CURRENT_UID="$(id -u 2>/dev/null || echo 1000)"
  CURRENT_GID="$(id -g 2>/dev/null || echo 1000)"
  CURRENT_USER_NAME="$(id -un 2>/dev/null || echo user)"
  CURRENT_GROUP_NAME="$(id -gn 2>/dev/null || echo users)"
  CURRENT_USER_PAIR="${CURRENT_UID}:${CURRENT_GID}"
  echo "1) 🏠 Local Root (${PERMISSION_LOCAL_USER})"
  echo "2) 🗂️ Current User (${CURRENT_USER_NAME}:${CURRENT_GROUP_NAME} → ${CURRENT_USER_PAIR})"
  echo "3) ⚙️ Custom"
  local PERMISSION_SCHEME_INPUT="${CLI_PERMISSION_SCHEME}"
  if [ "$NON_INTERACTIVE" = "1" ] && [ -z "$PERMISSION_SCHEME_INPUT" ]; then
    PERMISSION_SCHEME_INPUT="local"
  fi
  while true; do
    if [ -z "$PERMISSION_SCHEME_INPUT" ]; then
      read -p "$(echo -e "${YELLOW}🔧 Select permission scheme [1-3]: ${NC}")" PERMISSION_SCHEME_INPUT
    fi
    case "${PERMISSION_SCHEME_INPUT,,}" in
      1|local)
        CONTAINER_USER="$PERMISSION_LOCAL_USER"
        PERMISSION_SCHEME_NAME="local"
        ;;
      2|nfs|user)
        CONTAINER_USER="$CURRENT_USER_PAIR"
        PERMISSION_SCHEME_NAME="user"
        ;;
      3|custom)
        local uid gid
        uid="${CLI_CUSTOM_UID:-$(ask "Enter PUID (user id)" $DEFAULT_CUSTOM_UID validate_number)}"
        gid="${CLI_CUSTOM_GID:-$(ask "Enter PGID (group id)" $DEFAULT_CUSTOM_GID validate_number)}"
        CONTAINER_USER="${uid}:${gid}"
        PERMISSION_SCHEME_NAME="custom"
        ;;
      *)
        if [ -n "$CLI_PERMISSION_SCHEME" ] || [ "$NON_INTERACTIVE" = "1" ]; then
          say ERROR "Invalid permission scheme: ${PERMISSION_SCHEME_INPUT}"
          exit 1
        fi
        say ERROR "Please select 1, 2, or 3"
        PERMISSION_SCHEME_INPUT=""
        continue
        ;;
    esac
    break
  done
  if [ -n "$CLI_PERMISSION_SCHEME" ] || [ "$NON_INTERACTIVE" = "1" ]; then
    say INFO "Permission scheme set to ${PERMISSION_SCHEME_NAME:-$PERMISSION_SCHEME_INPUT}."
  fi
}

configure_database() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask)
  say HEADER "DATABASE CONFIGURATION"
  MYSQL_ROOT_PASSWORD=$(ask "Enter MySQL root password" "${CLI_MYSQL_PASSWORD:-$DEFAULT_MYSQL_PASSWORD}")
}

configure_storage() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask)
  say HEADER "STORAGE CONFIGURATION"
  if [ -n "$CLI_STORAGE_PATH" ]; then
    STORAGE_PATH="$CLI_STORAGE_PATH"
  elif [ "$NON_INTERACTIVE" = "1" ]; then
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
      STORAGE_PATH=$DEFAULT_LOCAL_STORAGE
    else
      STORAGE_PATH=$DEFAULT_MOUNT_STORAGE
    fi
  else
    echo "1) 💾 ${DEFAULT_LOCAL_STORAGE} (local)"
    echo "2) 🌐 ${DEFAULT_NFS_STORAGE} (NFS)"
    echo "3) 📁 Custom"
    while true; do
      read -p "$(echo -e "${YELLOW}🔧 Select storage option [1-3]: ${NC}")" s
      case "$s" in
        1) STORAGE_PATH=$DEFAULT_LOCAL_STORAGE; break;;
        2) STORAGE_PATH=$DEFAULT_NFS_STORAGE; break;;
        3) STORAGE_PATH=$(ask "Enter custom storage path" "$DEFAULT_MOUNT_STORAGE"); break;;
        *) say ERROR "Please select 1, 2, or 3";;
      esac
    done
  fi
  say INFO "Storage path set to ${STORAGE_PATH}"
}

configure_backups() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask, validate_number)
  say HEADER "BACKUP CONFIGURATION"
  BACKUP_RETENTION_DAYS=$(ask "Daily backups retention (days)" "${CLI_BACKUP_DAYS:-$DEFAULT_BACKUP_DAYS}" validate_number)
  BACKUP_RETENTION_HOURS=$(ask "Hourly backups retention (hours)" "${CLI_BACKUP_HOURS:-$DEFAULT_BACKUP_HOURS}" validate_number)
  BACKUP_DAILY_TIME=$(ask "Daily backup hour (00-23, UTC)" "${CLI_BACKUP_TIME:-$DEFAULT_BACKUP_TIME}" validate_number)
}

select_server_preset() {
  # setup.sh -> scripts/bash/setup/ui.sh (say, ask)
  if [ "$ENABLE_CONFIG_PRESETS" = "1" ]; then
    say HEADER "SERVER CONFIGURATION PRESET"

    if [ -n "$CLI_CONFIG_PRESET" ]; then
      SERVER_CONFIG_PRESET="$CLI_CONFIG_PRESET"
      say INFO "Using preset from command line: $SERVER_CONFIG_PRESET"
      return 0
    fi

    declare -A CONFIG_PRESET_NAMES=()
    declare -A CONFIG_PRESET_DESCRIPTIONS=()
    declare -A CONFIG_MENU_INDEX=()
    local config_dir="$SCRIPT_DIR/config/presets"
    local menu_index=1

    echo "Choose a server configuration preset:"

    # setup.sh -> scripts/python/parse-config-presets.py (preset metadata)
    if [ -x "$SCRIPT_DIR/scripts/python/parse-config-presets.py" ] && [ -d "$config_dir" ]; then
      while IFS=$'\t' read -r preset_key preset_name preset_desc; do
        [ -n "$preset_key" ] || continue
        CONFIG_PRESET_NAMES["$preset_key"]="$preset_name"
        CONFIG_PRESET_DESCRIPTIONS["$preset_key"]="$preset_desc"
        CONFIG_MENU_INDEX[$menu_index]="$preset_key"
        echo "$menu_index) $preset_name"
        echo "   $preset_desc"
        menu_index=$((menu_index + 1))
      done < <(python3 "$SCRIPT_DIR/scripts/python/parse-config-presets.py" list --presets-dir "$config_dir")
    else
      # Fallback if parser script not available
      CONFIG_MENU_INDEX[1]="none"
      CONFIG_PRESET_NAMES["none"]="Default (No Preset)"
      CONFIG_PRESET_DESCRIPTIONS["none"]="Use default AzerothCore settings"
      echo "1) Default (No Preset)"
      echo "   Use default AzerothCore settings without any modifications"
    fi

    local max_config_option=$((menu_index - 1))

    if [ "$NON_INTERACTIVE" = "1" ]; then
      SERVER_CONFIG_PRESET="none"
      say INFO "Non-interactive mode: Using default configuration preset"
      return 0
    fi

    while true; do
      read -p "$(echo -e "${YELLOW}🎯 Select server configuration [1-$max_config_option]: ${NC}")" choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max_config_option" ]; then
        SERVER_CONFIG_PRESET="${CONFIG_MENU_INDEX[$choice]}"
        local chosen_name="${CONFIG_PRESET_NAMES[$SERVER_CONFIG_PRESET]}"
        say INFO "Selected: $chosen_name"
        break
      else
        say ERROR "Please select a number between 1 and $max_config_option"
      fi
    done
  else
    # Config presets disabled - use default
    SERVER_CONFIG_PRESET="none"
    say INFO "Server configuration presets disabled - using default settings"
  fi
}

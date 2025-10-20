#!/bin/bash
set -e

# ==============================================
# ac-compose - Interactive .env generator
# ==============================================
# Mirrors options from scripts/setup-server.sh but targets ac-compose/.env

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'
say(){ local t=$1; shift; case "$t" in
  INFO) echo -e "${BLUE}ℹ️  $*${NC}";;
  SUCCESS) echo -e "${GREEN}✅ $*${NC}";;
  WARNING) echo -e "${YELLOW}⚠️  $*${NC}";;
  ERROR) echo -e "${RED}❌ $*${NC}";;
  HEADER) echo -e "\n${MAGENTA}=== $* ===${NC}";;
esac }

validate_ip(){ [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
validate_port(){ [[ $1 =~ ^[0-9]+$ ]] && [ $1 -ge 1 ] && [ $1 -le 65535 ]; }
validate_number(){ [[ $1 =~ ^[0-9]+$ ]]; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NON_INTERACTIVE=0

ask(){
  local prompt="$1"; local def="$2"; local validator="$3"; local v
  while true; do
    if [ "$NON_INTERACTIVE" = "1" ]; then
      v="$def"
    else
      if [ -n "$def" ]; then
        read -p "$(echo -e "${YELLOW}🔧 ${prompt} [${def}]: ${NC}")" v; v=${v:-$def}
      else
        read -p "$(echo -e "${YELLOW}🔧 ${prompt}: ${NC}")" v
      fi
    fi
    if [ -z "$v" ] && [ "$NON_INTERACTIVE" = "1" ]; then
      say ERROR "Non-interactive mode requires a value for '${prompt}'."
      exit 1
    fi
    if [ -z "$validator" ] || $validator "$v"; then
      echo "$v"
      return 0
    fi
    if [ "$NON_INTERACTIVE" = "1" ]; then
      say ERROR "Invalid value '${v}' provided for '${prompt}' in non-interactive mode."
      exit 1
    fi
    say ERROR "Invalid input. Please try again."
  done
}

ask_yn(){
  local p="$1"; local d="$2"; local v
  if [ "$NON_INTERACTIVE" = "1" ]; then
    if [ "$d" = "y" ]; then
      echo 1
    else
      echo 0
    fi
    return 0
  fi
  while true; do
    if [ "$d" = "y" ]; then
      read -p "$(echo -e "${YELLOW}🔧 ${p} [Y/n]: ${NC}")" v; v=${v:-y}
    else
      read -p "$(echo -e "${YELLOW}🔧 ${p} [y/N]: ${NC}")" v; v=${v:-n}
    fi
    case "$v" in
      [Yy]*) echo 1; return 0;;
      [Nn]*) echo 0; return 0;;
    esac
    say ERROR "Please answer y or n"
  done
}

normalize_module_name(){
  local mod="$1"
  mod="${mod^^}"
  mod="${mod//-/_}"
  mod="${mod//./_}"
  mod="${mod// /_}"
  if [[ "$mod" = MOD_* ]]; then
    mod="${mod#MOD_}"
  fi
  if [[ "$mod" != MODULE_* ]]; then
    mod="MODULE_${mod}"
  fi
  echo "$mod"
}

declare -A MODULE_ENABLE_SET=()

KNOWN_MODULE_VARS=(
  MODULE_PLAYERBOTS
  MODULE_AOE_LOOT
  MODULE_LEARN_SPELLS
  MODULE_FIREWORKS
  MODULE_INDIVIDUAL_PROGRESSION
  MODULE_AHBOT
  MODULE_AUTOBALANCE
  MODULE_TRANSMOG
  MODULE_NPC_BUFFER
  MODULE_DYNAMIC_XP
  MODULE_SOLO_LFG
  MODULE_1V1_ARENA
  MODULE_PHASED_DUELS
  MODULE_BREAKING_NEWS
  MODULE_BOSS_ANNOUNCER
  MODULE_ACCOUNT_ACHIEVEMENTS
  MODULE_AUTO_REVIVE
  MODULE_GAIN_HONOR_GUARD
  MODULE_ARAC
  MODULE_TIME_IS_TIME
  MODULE_POCKET_PORTAL
  MODULE_RANDOM_ENCHANTS
  MODULE_SOLOCRAFT
  MODULE_PVP_TITLES
  MODULE_NPC_BEASTMASTER
  MODULE_NPC_ENCHANTER
  MODULE_INSTANCE_RESET
  MODULE_LEVEL_GRANT
  MODULE_CHALLENGE_MODES
  MODULE_OLLAMA_CHAT
  MODULE_SKELETON_MODULE
  MODULE_BG_SLAVERYVALLEY
  MODULE_ELUNA_TS
  MODULE_PLAYER_BOT_LEVEL_BRACKETS
  MODULE_STATBOOSTER
  MODULE_DUNGEON_RESPAWN
  MODULE_AZEROTHSHARD
  MODULE_WORGOBLIN
  MODULE_ASSISTANT
  MODULE_REAGENT_BANK
  MODULE_BLACK_MARKET_AUCTION_HOUSE
)

declare -A KNOWN_MODULE_LOOKUP=()
for __mod in "${KNOWN_MODULE_VARS[@]}"; do
  KNOWN_MODULE_LOOKUP["$__mod"]=1
done
unset __mod

module_default(){
  local key="$1"
  if [ "${MODULE_ENABLE_SET[$key]}" = "1" ]; then
    echo y
  else
    echo n
  fi
}

apply_module_preset(){
  local preset_list="$1"
  local IFS=','
  for item in $preset_list; do
    local mod="${item//[[:space:]]/}"
    [ -z "$mod" ] && continue
    if [ -n "${KNOWN_MODULE_LOOKUP[$mod]:-}" ]; then
      eval "$mod=1"
    else
      say WARNING "Preset references unknown module $mod"
    fi
  done
}

DEFAULT_PRESET_SUGGESTED="suggested-modules"
DEFAULT_PRESET_PLAYERBOTS="playerbots-suggested-modules"

show_wow_header(){
  echo -e "\n${BLUE}    ⚔️  AZEROTHCORE DEPLOYMENT SYSTEM  ⚔️${NC}"
  echo -e "${BLUE}    ═══════════════════════════════════════${NC}"
  echo -e "${BLUE}         🏰 Build Your Own WoW Server 🏰${NC}\n"
}

show_realm_configured(){
  echo -e "\n${GREEN}⚔️ Your realm configuration has been forged! ⚔️${NC}"
  echo -e "${GREEN}🏰 Ready to deploy your World of Warcraft server${NC}"
  echo -e "${GREEN}🗡️ May your realm bring epic adventures!${NC}\n"
}

main(){
  local CLI_DEPLOYMENT_TYPE=""
  local CLI_PERMISSION_SCHEME=""
  local CLI_CUSTOM_UID=""
  local CLI_CUSTOM_GID=""
  local CLI_SERVER_ADDRESS=""
  local CLI_REALM_PORT=""
  local CLI_AUTH_PORT=""
  local CLI_SOAP_PORT=""
  local CLI_MYSQL_PORT=""
  local CLI_MYSQL_PASSWORD=""
  local CLI_STORAGE_PATH=""
  local CLI_BACKUP_DAYS=""
  local CLI_BACKUP_HOURS=""
  local CLI_BACKUP_TIME=""
  local CLI_MODULE_MODE=""
  local CLI_MODULE_PRESET=""
  local CLI_PLAYERBOT_ENABLED=""
  local CLI_PLAYERBOT_MAX=""
  local CLI_AUTO_REBUILD=0
  local CLI_RUN_REBUILD=0
  local CLI_MODULES_SOURCE=""
  local FORCE_OVERWRITE=0
  local CLI_ENABLE_MODULES_RAW=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cat <<'EOF'
Usage: ./setup.sh [options]

Description:
  Interactive wizard that generates ac-compose/.env for the
  profiles-based compose. Prompts for deployment type, ports, storage,
  MySQL credentials, backup retention, and module presets or manual
  toggles.

Options:
  -h, --help                      Show this help message and exit
  --non-interactive               Use defaults/arguments without prompting
  --deployment-type TYPE          Deployment type: local, lan, or public
  --permission-scheme SCHEME      Permissions: local, nfs, or custom
  --custom-uid UID                UID when --permission-scheme=custom
  --custom-gid GID                GID when --permission-scheme=custom
  --server-address ADDRESS        Realm/public address
  --realm-port PORT               Client connection port (default 8215)
  --auth-port PORT                Authserver external port (default 3784)
  --soap-port PORT                SOAP external port (default 7778)
  --mysql-port PORT               MySQL external port (default 64306)
  --mysql-password PASSWORD       MySQL root password (default azerothcore123)
  --storage-path PATH             Storage directory
  --backup-retention-days N       Daily backup retention (default 3)
  --backup-retention-hours N      Hourly backup retention (default 6)
  --backup-daily-time HH          Daily backup hour 00-23 (default 09)
  --module-mode MODE              suggested, playerbots, manual, or none
  --module-config NAME            Use preset NAME from configurations/<NAME>.conf
  --enable-modules LIST           Comma-separated module list (MODULE_* or shorthand)
  --playerbot-enabled 0|1         Override PLAYERBOT_ENABLED flag
  --playerbot-max-bots N          Override PLAYERBOT_MAX_BOTS value
  --auto-rebuild-on-deploy        Enable automatic rebuild during deploys
  --run-rebuild-now               Trigger module rebuild after setup completes
  --modules-rebuild-source PATH   Source checkout used for module rebuilds
  --force                         Overwrite existing .env without prompting
EOF
        exit 0
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --deployment-type)
        [[ $# -ge 2 ]] || { say ERROR "--deployment-type requires a value"; exit 1; }
        CLI_DEPLOYMENT_TYPE="$2"; shift 2
        ;;
      --deployment-type=*)
        CLI_DEPLOYMENT_TYPE="${1#*=}"; shift
        ;;
      --permission-scheme)
        [[ $# -ge 2 ]] || { say ERROR "--permission-scheme requires a value"; exit 1; }
        CLI_PERMISSION_SCHEME="$2"; shift 2
        ;;
      --permission-scheme=*)
        CLI_PERMISSION_SCHEME="${1#*=}"; shift
        ;;
      --custom-uid)
        [[ $# -ge 2 ]] || { say ERROR "--custom-uid requires a value"; exit 1; }
        CLI_CUSTOM_UID="$2"; shift 2
        ;;
      --custom-uid=*)
        CLI_CUSTOM_UID="${1#*=}"; shift
        ;;
      --custom-gid)
        [[ $# -ge 2 ]] || { say ERROR "--custom-gid requires a value"; exit 1; }
        CLI_CUSTOM_GID="$2"; shift 2
        ;;
      --custom-gid=*)
        CLI_CUSTOM_GID="${1#*=}"; shift
        ;;
      --server-address)
        [[ $# -ge 2 ]] || { say ERROR "--server-address requires a value"; exit 1; }
        CLI_SERVER_ADDRESS="$2"; shift 2
        ;;
      --server-address=*)
        CLI_SERVER_ADDRESS="${1#*=}"; shift
        ;;
      --realm-port)
        [[ $# -ge 2 ]] || { say ERROR "--realm-port requires a value"; exit 1; }
        CLI_REALM_PORT="$2"; shift 2
        ;;
      --realm-port=*)
        CLI_REALM_PORT="${1#*=}"; shift
        ;;
      --auth-port)
        [[ $# -ge 2 ]] || { say ERROR "--auth-port requires a value"; exit 1; }
        CLI_AUTH_PORT="$2"; shift 2
        ;;
      --auth-port=*)
        CLI_AUTH_PORT="${1#*=}"; shift
        ;;
      --soap-port)
        [[ $# -ge 2 ]] || { say ERROR "--soap-port requires a value"; exit 1; }
        CLI_SOAP_PORT="$2"; shift 2
        ;;
      --soap-port=*)
        CLI_SOAP_PORT="${1#*=}"; shift
        ;;
      --mysql-port)
        [[ $# -ge 2 ]] || { say ERROR "--mysql-port requires a value"; exit 1; }
        CLI_MYSQL_PORT="$2"; shift 2
        ;;
      --mysql-port=*)
        CLI_MYSQL_PORT="${1#*=}"; shift
        ;;
      --mysql-password)
        [[ $# -ge 2 ]] || { say ERROR "--mysql-password requires a value"; exit 1; }
        CLI_MYSQL_PASSWORD="$2"; shift 2
        ;;
      --mysql-password=*)
        CLI_MYSQL_PASSWORD="${1#*=}"; shift
        ;;
      --storage-path)
        [[ $# -ge 2 ]] || { say ERROR "--storage-path requires a value"; exit 1; }
        CLI_STORAGE_PATH="$2"; shift 2
        ;;
      --storage-path=*)
        CLI_STORAGE_PATH="${1#*=}"; shift
        ;;
      --backup-retention-days)
        [[ $# -ge 2 ]] || { say ERROR "--backup-retention-days requires a value"; exit 1; }
        CLI_BACKUP_DAYS="$2"; shift 2
        ;;
      --backup-retention-days=*)
        CLI_BACKUP_DAYS="${1#*=}"; shift
        ;;
      --backup-retention-hours)
        [[ $# -ge 2 ]] || { say ERROR "--backup-retention-hours requires a value"; exit 1; }
        CLI_BACKUP_HOURS="$2"; shift 2
        ;;
      --backup-retention-hours=*)
        CLI_BACKUP_HOURS="${1#*=}"; shift
        ;;
      --backup-daily-time)
        [[ $# -ge 2 ]] || { say ERROR "--backup-daily-time requires a value"; exit 1; }
        CLI_BACKUP_TIME="$2"; shift 2
        ;;
      --backup-daily-time=*)
        CLI_BACKUP_TIME="${1#*=}"; shift
        ;;
      --module-mode)
        [[ $# -ge 2 ]] || { say ERROR "--module-mode requires a value"; exit 1; }
        CLI_MODULE_MODE="$2"; shift 2
        ;;
      --module-mode=*)
        CLI_MODULE_MODE="${1#*=}"; shift
        ;;
      --module-config)
        [[ $# -ge 2 ]] || { say ERROR "--module-config requires a value"; exit 1; }
        CLI_MODULE_PRESET="$2"; shift 2
        ;;
      --module-config=*)
        CLI_MODULE_PRESET="${1#*=}"; shift
        ;;
      --enable-modules)
        [[ $# -ge 2 ]] || { say ERROR "--enable-modules requires a value"; exit 1; }
        CLI_ENABLE_MODULES_RAW+=("$2"); shift 2
        ;;
      --enable-modules=*)
        CLI_ENABLE_MODULES_RAW+=("${1#*=}"); shift
        ;;
      --playerbot-enabled)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-enabled requires 0 or 1"; exit 1; }
        CLI_PLAYERBOT_ENABLED="$2"; shift 2
        ;;
      --playerbot-enabled=*)
        CLI_PLAYERBOT_ENABLED="${1#*=}"; shift
        ;;
      --playerbot-max-bots)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-max-bots requires a value"; exit 1; }
        CLI_PLAYERBOT_MAX="$2"; shift 2
        ;;
      --playerbot-max-bots=*)
        CLI_PLAYERBOT_MAX="${1#*=}"; shift
        ;;
      --auto-rebuild-on-deploy)
        CLI_AUTO_REBUILD=1
        shift
        ;;
      --run-rebuild-now)
        CLI_RUN_REBUILD=1
        shift
        ;;
      --modules-rebuild-source)
        [[ $# -ge 2 ]] || { say ERROR "--modules-rebuild-source requires a value"; exit 1; }
        CLI_MODULES_SOURCE="$2"; shift 2
        ;;
      --modules-rebuild-source=*)
        CLI_MODULES_SOURCE="${1#*=}"; shift
        ;;
      --force)
        FORCE_OVERWRITE=1
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        echo "Use --help for usage" >&2
        exit 1
        ;;
    esac
  done

  if [ ${#CLI_ENABLE_MODULES_RAW[@]} -gt 0 ]; then
    local raw part norm
    for raw in "${CLI_ENABLE_MODULES_RAW[@]}"; do
      IFS=',' read -ra parts <<<"$raw"
      for part in "${parts[@]}"; do
        part="${part//[[:space:]]/}"
        [ -z "$part" ] && continue
        norm="$(normalize_module_name "$part")"
        if [ -z "${KNOWN_MODULE_LOOKUP[$norm]}" ]; then
          say WARNING "Ignoring unknown module identifier: ${part}"
          continue
        fi
        MODULE_ENABLE_SET["$norm"]=1
      done
    done
    unset raw part norm parts
  fi

  if [ ${#CLI_ENABLE_MODULES_RAW[@]} -gt 0 ] && [ -z "$CLI_MODULE_MODE" ]; then
    CLI_MODULE_MODE="manual"
  fi

  show_wow_header
  say INFO "This will create ac-compose/.env for compose profiles."

  # Deployment type
  say HEADER "DEPLOYMENT TYPE"
  echo "1) 🏠 Local Development (127.0.0.1, local storage)"
  echo "2) 🌐 LAN Server (local network IP)"
  echo "3) ☁️  Public Server (domain or public IP)"
local DEPLOYMENT_TYPE_INPUT="${CLI_DEPLOYMENT_TYPE}"
local DEPLOYMENT_TYPE=""
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

  # Server config
  say HEADER "SERVER CONFIGURATION"
  local SERVER_ADDRESS=""
  if [ -n "$CLI_SERVER_ADDRESS" ]; then
    SERVER_ADDRESS="$CLI_SERVER_ADDRESS"
  elif [ "$DEPLOYMENT_TYPE" = "local" ]; then
    SERVER_ADDRESS=127.0.0.1
  elif [ "$DEPLOYMENT_TYPE" = "lan" ]; then
    local LAN_IP
    LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $7}')
    SERVER_ADDRESS=$(ask "Enter server IP address" "${CLI_SERVER_ADDRESS:-${LAN_IP:-192.168.1.100}}" validate_ip)
  else
    SERVER_ADDRESS=$(ask "Enter server address (IP or domain)" "${CLI_SERVER_ADDRESS:-your-domain.com}" )
  fi

  local REALM_PORT AUTH_EXTERNAL_PORT SOAP_EXTERNAL_PORT MYSQL_EXTERNAL_PORT
  REALM_PORT=$(ask "Enter client connection port" "${CLI_REALM_PORT:-8215}" validate_port)
  AUTH_EXTERNAL_PORT=$(ask "Enter auth server port" "${CLI_AUTH_PORT:-3784}" validate_port)
  SOAP_EXTERNAL_PORT=$(ask "Enter SOAP API port" "${CLI_SOAP_PORT:-7778}" validate_port)
  MYSQL_EXTERNAL_PORT=$(ask "Enter MySQL external port" "${CLI_MYSQL_PORT:-64306}" validate_port)

  # Permission scheme
  say HEADER "PERMISSION SCHEME"
  echo "1) 🏠 Local Dev (0:0)"
  echo "2) 🗂️  NFS Server (1001:1000)"
  echo "3) ⚙️  Custom"
  local PERMISSION_SCHEME_INPUT="${CLI_PERMISSION_SCHEME}"
  local PERMISSION_SCHEME_NAME=""
  local CONTAINER_USER
  if [ "$NON_INTERACTIVE" = "1" ] && [ -z "$PERMISSION_SCHEME_INPUT" ]; then
    PERMISSION_SCHEME_INPUT="local"
  fi
  while true; do
    if [ -z "$PERMISSION_SCHEME_INPUT" ]; then
      read -p "$(echo -e "${YELLOW}🔧 Select permission scheme [1-3]: ${NC}")" PERMISSION_SCHEME_INPUT
    fi
    case "${PERMISSION_SCHEME_INPUT,,}" in
      1|local)
        CONTAINER_USER="0:0"
        PERMISSION_SCHEME_NAME="local"
        ;;
      2|nfs)
        CONTAINER_USER="1001:1000"
        PERMISSION_SCHEME_NAME="nfs"
        ;;
      3|custom)
        local uid gid
        uid="${CLI_CUSTOM_UID:-$(ask "Enter PUID (user id)" 1000 validate_number)}"
        gid="${CLI_CUSTOM_GID:-$(ask "Enter PGID (group id)" 1000 validate_number)}"
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
  # DB config
  say HEADER "DATABASE CONFIGURATION"
  local MYSQL_ROOT_PASSWORD; MYSQL_ROOT_PASSWORD=$(ask "Enter MySQL root password" "${CLI_MYSQL_PASSWORD:-azerothcore123}")

  # Storage
  say HEADER "STORAGE CONFIGURATION"
  local STORAGE_PATH
  if [ -n "$CLI_STORAGE_PATH" ]; then
    STORAGE_PATH="$CLI_STORAGE_PATH"
  elif [ "$DEPLOYMENT_TYPE" = "local" ]; then
    STORAGE_PATH=./storage
  else
    if [ "$NON_INTERACTIVE" = "1" ]; then
      STORAGE_PATH=/mnt/azerothcore-data
    else
      echo "1) 💾 ./storage (local)"
      echo "2) 🌐 /nfs/azerothcore (NFS)"
      echo "3) 📁 Custom"
      while true; do
        read -p "$(echo -e "${YELLOW}🔧 Select storage option [1-3]: ${NC}")" s
        case "$s" in
          1) STORAGE_PATH=./storage; break;;
          2) STORAGE_PATH=/nfs/azerothcore; break;;
          3) STORAGE_PATH=$(ask "Enter custom storage path" "/mnt/azerothcore-data"); break;;
          *) say ERROR "Please select 1, 2, or 3";;
        esac
      done
    fi
  fi

  # Backup
  say HEADER "BACKUP CONFIGURATION"
  local BACKUP_RETENTION_DAYS BACKUP_RETENTION_HOURS BACKUP_DAILY_TIME
  BACKUP_RETENTION_DAYS=$(ask "Daily backups retention (days)" "${CLI_BACKUP_DAYS:-3}" validate_number)
  BACKUP_RETENTION_HOURS=$(ask "Hourly backups retention (hours)" "${CLI_BACKUP_HOURS:-6}" validate_number)
  BACKUP_DAILY_TIME=$(ask "Daily backup hour (00-23, UTC)" "${CLI_BACKUP_TIME:-09}" validate_number)

  local MODE=""
  local MODE_PRESET_NAME=""
  declare -A MODULE_PRESET_CONFIGS=()
  declare -a MODULE_PRESET_ORDER=()
  local CONFIG_DIR="$SCRIPT_DIR/configurations"
  if [ -d "$CONFIG_DIR" ]; then
    while IFS= read -r preset_path; do
      [ -n "$preset_path" ] || continue
      local preset_name
      preset_name="$(basename "$preset_path" .conf)"
      local preset_value
      preset_value="$(tr -d '\r' < "$preset_path" | tr '\n' ',' | sed -E 's/,+/,/g; s/^,//; s/,$//')"
      MODULE_PRESET_CONFIGS["$preset_name"]="$preset_value"
      MODULE_PRESET_ORDER+=("$preset_name")
    done < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name '*.conf' -print | sort)
  fi

  local missing_presets=0
  for required_preset in "$DEFAULT_PRESET_SUGGESTED" "$DEFAULT_PRESET_PLAYERBOTS"; do
    if [ -z "${MODULE_PRESET_CONFIGS[$required_preset]:-}" ]; then
      say ERROR "Missing module preset configurations/${required_preset}.conf"
      missing_presets=1
    fi
  done
  if [ "$missing_presets" -eq 1 ]; then
    exit 1
  fi

  if [ -n "$CLI_MODULE_PRESET" ]; then
    if [ -n "${MODULE_PRESET_CONFIGS[$CLI_MODULE_PRESET]:-}" ]; then
      MODE="preset"
      MODE_PRESET_NAME="$CLI_MODULE_PRESET"
    else
      say ERROR "Unknown module preset: $CLI_MODULE_PRESET"
      exit 1
    fi
  fi

  if [ -n "$MODE" ] && [ "$MODE" != "preset" ]; then
    MODE_PRESET_NAME=""
  fi

  if [ -n "$CLI_MODULE_MODE" ]; then
    case "${CLI_MODULE_MODE,,}" in
      1|suggested) MODE=1 ;;
      2|playerbots) MODE=2 ;;
      3|manual) MODE=3 ;;
      4|none) MODE=4 ;;
      *) say ERROR "Invalid module mode: ${CLI_MODULE_MODE}"; exit 1 ;;
    esac
    if [ "$MODE" = "1" ]; then
      MODE_PRESET_NAME="$DEFAULT_PRESET_SUGGESTED"
    elif [ "$MODE" = "2" ]; then
      MODE_PRESET_NAME="$DEFAULT_PRESET_PLAYERBOTS"
    fi
  fi

  if [ -z "$MODE" ] && [ ${#MODULE_ENABLE_SET[@]} -gt 0 ]; then
    MODE=3
  fi
  if [ ${#MODULE_ENABLE_SET[@]} -gt 0 ] && [ -n "$MODE" ] && [ "$MODE" != "3" ] && [ "$MODE" != "4" ]; then
    say INFO "Switching module preset to manual to honor --enable-modules list."
    MODE=3
  fi
  if [ "$MODE" = "4" ] && [ ${#MODULE_ENABLE_SET[@]} -gt 0 ]; then
    say ERROR "--enable-modules cannot be used together with module-mode=none."
    exit 1
  fi

  local MODE_PRESET_NAME=""
  if [ "$MODE" = "preset" ] && [ -n "$CLI_MODULE_PRESET" ]; then
    MODE_PRESET_NAME="$CLI_MODULE_PRESET"
  fi

  # Module config
  say HEADER "MODULE PRESET"
  echo "1) ⭐ Suggested Modules"
  echo "2) 🤖 Playerbots + Suggested modules"
  echo "3) ⚙️  Manual selection"
  echo "4) 🚫 No modules"

  local menu_index=5
  declare -A MENU_PRESET_INDEX=()
  if [ ${#MODULE_PRESET_ORDER[@]} -gt 0 ]; then
    for preset_name in "${MODULE_PRESET_ORDER[@]}"; do
      if [ "$preset_name" = "$DEFAULT_PRESET_SUGGESTED" ] || [ "$preset_name" = "$DEFAULT_PRESET_PLAYERBOTS" ]; then
        continue
      fi
      local pretty_name
      pretty_name=$(echo "$preset_name" | tr '_-' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')
      echo "${menu_index}) 🧩 ${pretty_name} (configurations/${preset_name}.conf)"
      MENU_PRESET_INDEX[$menu_index]="$preset_name"
      menu_index=$((menu_index + 1))
    done
  fi
  local max_option=$((menu_index - 1))

  if [ "$NON_INTERACTIVE" = "1" ] && [ -z "$MODE" ]; then
    MODE=1
  fi

  if [ -z "$MODE" ]; then
    local MODE_SELECTION
    while true; do
      read -p "$(echo -e "${YELLOW}🔧 Select module configuration [1-${max_option}]: ${NC}")" MODE_SELECTION
      if [[ "$MODE_SELECTION" =~ ^[0-9]+$ ]] && [ "$MODE_SELECTION" -ge 1 ] && [ "$MODE_SELECTION" -le "$max_option" ]; then
        if [ -n "${MENU_PRESET_INDEX[$MODE_SELECTION]:-}" ]; then
          MODE="preset"
          MODE_PRESET_NAME="${MENU_PRESET_INDEX[$MODE_SELECTION]}"
        else
          MODE="$MODE_SELECTION"
        fi
        break
      fi
      say ERROR "Please select a number between 1 and ${max_option}"
    done
  else
    if [ "$MODE" = "preset" ]; then
      say INFO "Module preset set to ${MODE_PRESET_NAME}."
    else
      say INFO "Module preset set to ${MODE}."
    fi
  fi

  # Initialize toggles
  local MODULE_PLAYERBOTS=0 MODULE_AOE_LOOT=0 MODULE_LEARN_SPELLS=0 MODULE_FIREWORKS=0 MODULE_INDIVIDUAL_PROGRESSION=0 \
        MODULE_AHBOT=0 MODULE_AUTOBALANCE=0 MODULE_TRANSMOG=0 MODULE_NPC_BUFFER=0 MODULE_DYNAMIC_XP=0 MODULE_SOLO_LFG=0 \
        MODULE_1V1_ARENA=0 MODULE_PHASED_DUELS=0 MODULE_BREAKING_NEWS=0 MODULE_BOSS_ANNOUNCER=0 MODULE_ACCOUNT_ACHIEVEMENTS=0 \
        MODULE_AUTO_REVIVE=0 MODULE_GAIN_HONOR_GUARD=0 MODULE_TIME_IS_TIME=0 MODULE_POCKET_PORTAL=0 \
        MODULE_RANDOM_ENCHANTS=0 MODULE_SOLOCRAFT=0 MODULE_PVP_TITLES=0 MODULE_NPC_BEASTMASTER=0 MODULE_NPC_ENCHANTER=0 \
        MODULE_INSTANCE_RESET=0 MODULE_LEVEL_GRANT=0 MODULE_ASSISTANT=0 MODULE_REAGENT_BANK=0 MODULE_BLACK_MARKET_AUCTION_HOUSE=0 MODULE_ARAC=0 \
        MODULE_CHALLENGE_MODES=0 MODULE_OLLAMA_CHAT=0 MODULE_SKELETON_MODULE=0 MODULE_BG_SLAVERYVALLEY=0 MODULE_ELUNA_TS=0 \
        MODULE_PLAYER_BOT_LEVEL_BRACKETS=0 MODULE_STATBOOSTER=0 MODULE_DUNGEON_RESPAWN=0 MODULE_AZEROTHSHARD=0 MODULE_WORGOBLIN=0
  local DEFAULT_AUTH_IMAGE_PLAYERBOTS="uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot"
  local DEFAULT_WORLD_IMAGE_PLAYERBOTS="uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot"
  local AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_AUTH_IMAGE_PLAYERBOTS"
  local AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_WORLD_IMAGE_PLAYERBOTS"

  local mod_var
  for mod_var in "${!MODULE_ENABLE_SET[@]}"; do
    if [ -n "${KNOWN_MODULE_LOOKUP[$mod_var]}" ]; then
      eval "$mod_var=1"
    fi
  done

  if { [ "${MODULE_PLAYER_BOT_LEVEL_BRACKETS}" = "1" ] || [ "${MODULE_OLLAMA_CHAT}" = "1" ]; } && [ "$MODULE_PLAYERBOTS" != "1" ]; then
    MODULE_PLAYERBOTS=1
    MODULE_ENABLE_SET["MODULE_PLAYERBOTS"]=1
    if [ ${#MODULE_ENABLE_SET[@]} -gt 0 ]; then
      say INFO "Automatically enabling MODULE_PLAYERBOTS to satisfy playerbot-dependent modules."
    fi
  fi

  declare -A DISABLED_MODULE_REASONS=(
    [MODULE_AHBOT]="Requires upstream Addmod_ahbotScripts symbol (fails link)"
    [MODULE_LEVEL_GRANT]="QuestCountLevel module relies on removed ConfigMgr APIs and fails to build"
  )

  local PLAYERBOT_ENABLED=0 PLAYERBOT_MAX_BOTS=40

  local AUTO_REBUILD_ON_DEPLOY=$CLI_AUTO_REBUILD
  local MODULES_REBUILD_SOURCE_PATH_VALUE="${CLI_MODULES_SOURCE}"
  local RUN_REBUILD_NOW=$CLI_RUN_REBUILD
  local NEEDS_CXX_REBUILD=0

  if [ "$MODE" = "1" ]; then
    MODE_PRESET_NAME="$DEFAULT_PRESET_SUGGESTED"
    apply_module_preset "${MODULE_PRESET_CONFIGS[$DEFAULT_PRESET_SUGGESTED]}"
  elif [ "$MODE" = "2" ]; then
    MODE_PRESET_NAME="$DEFAULT_PRESET_PLAYERBOTS"
    apply_module_preset "${MODULE_PRESET_CONFIGS[$DEFAULT_PRESET_PLAYERBOTS]}"
  elif [ "$MODE" = "3" ]; then
    MODE_PRESET_NAME=""
    say INFO "Answer y/n for each module"
    for key in "${!DISABLED_MODULE_REASONS[@]}"; do
      say WARNING "${key#MODULE_}: ${DISABLED_MODULE_REASONS[$key]}"
    done
    # Core Gameplay
    MODULE_PLAYERBOTS=$(ask_yn "Playerbots - AI companions" "$(module_default MODULE_PLAYERBOTS)")
    MODULE_PLAYER_BOT_LEVEL_BRACKETS=$(ask_yn "Playerbot Level Brackets - Evenly distribute bot levels" "$(module_default MODULE_PLAYER_BOT_LEVEL_BRACKETS)")
    MODULE_OLLAMA_CHAT=$(ask_yn "Ollama Chat - LLM dialogue for playerbots (requires external Ollama API)" "$(module_default MODULE_OLLAMA_CHAT)")
    MODULE_SOLO_LFG=$(ask_yn "Solo LFG - Solo dungeon finder" "$(module_default MODULE_SOLO_LFG)")
    MODULE_SOLOCRAFT=$(ask_yn "Solocraft - Scale dungeons/raids for solo" "$(module_default MODULE_SOLOCRAFT)")
    MODULE_CHALLENGE_MODES=$(ask_yn "Challenge Modes - Timed dungeon keystones" "$(module_default MODULE_CHALLENGE_MODES)")
    MODULE_AUTOBALANCE=$(ask_yn "Autobalance - Dynamic difficulty" "$(module_default MODULE_AUTOBALANCE)")
    # QoL
    MODULE_TRANSMOG=$(ask_yn "Transmog - Appearance changes" "$(module_default MODULE_TRANSMOG)")
    MODULE_NPC_BUFFER=$(ask_yn "NPC Buffer - Buff NPCs" "$(module_default MODULE_NPC_BUFFER)")
    MODULE_LEARN_SPELLS=$(ask_yn "Learn Spells - Auto-learn" "$(module_default MODULE_LEARN_SPELLS)")
    MODULE_AOE_LOOT=$(ask_yn "AOE Loot - Multi-corpse loot" "$(module_default MODULE_AOE_LOOT)")
    MODULE_FIREWORKS=$(ask_yn "Fireworks - Level-up FX" "$(module_default MODULE_FIREWORKS)")
    MODULE_ASSISTANT=$(ask_yn "Assistant - Multi-service NPC" "$(module_default MODULE_ASSISTANT)")
    MODULE_STATBOOSTER=$(ask_yn "Stat Booster - Random enchant upgrades" "$(module_default MODULE_STATBOOSTER)")
    MODULE_DUNGEON_RESPAWN=$(ask_yn "Dungeon Respawn - Return to entrance on death" "$(module_default MODULE_DUNGEON_RESPAWN)")
    MODULE_SKELETON_MODULE=$(ask_yn "Skeleton Module - Blank module template" "$(module_default MODULE_SKELETON_MODULE)")
    # Economy
    MODULE_AHBOT=$(ask_yn "AH Bot - Auction automation" "$(module_default MODULE_AHBOT)")
    MODULE_REAGENT_BANK=$(ask_yn "Reagent Bank - Materials storage" "$(module_default MODULE_REAGENT_BANK)")
    MODULE_BLACK_MARKET_AUCTION_HOUSE=$(ask_yn "Black Market - MoP-style" "$(module_default MODULE_BLACK_MARKET_AUCTION_HOUSE)")
    # PvP
    MODULE_1V1_ARENA=$(ask_yn "1v1 Arena - Solo arena queue system" "$(module_default MODULE_1V1_ARENA)")
    MODULE_PHASED_DUELS=$(ask_yn "Phased Duels - Isolated duel instances" "$(module_default MODULE_PHASED_DUELS)")
    MODULE_PVP_TITLES=$(ask_yn "PvP Titles - Classic honor rank titles" "$(module_default MODULE_PVP_TITLES)")
    MODULE_BG_SLAVERYVALLEY=$(ask_yn "Slavery Valley - Custom battleground" "$(module_default MODULE_BG_SLAVERYVALLEY)")
    # Progression
    MODULE_INDIVIDUAL_PROGRESSION=$(ask_yn "Individual Progression (Vanilla→TBC→WotLK)" "$(module_default MODULE_INDIVIDUAL_PROGRESSION)")
    MODULE_DYNAMIC_XP=$(ask_yn "Dynamic XP - Adaptive experience rates" "$(module_default MODULE_DYNAMIC_XP)")
    MODULE_ACCOUNT_ACHIEVEMENTS=$(ask_yn "Account Achievements - Share progress across characters" "$(module_default MODULE_ACCOUNT_ACHIEVEMENTS)")
    MODULE_AZEROTHSHARD=$(ask_yn "AzerothShard - Blended custom features" "$(module_default MODULE_AZEROTHSHARD)")
    # Server Features
    MODULE_BREAKING_NEWS=$(ask_yn "Breaking News - Server announcement system" "$(module_default MODULE_BREAKING_NEWS)")
    MODULE_BOSS_ANNOUNCER=$(ask_yn "Boss Announcer - Broadcast boss kills" "$(module_default MODULE_BOSS_ANNOUNCER)")
    MODULE_AUTO_REVIVE=$(ask_yn "Auto Revive - Automatic resurrection system" "$(module_default MODULE_AUTO_REVIVE)")
    MODULE_ELUNA_TS=$(ask_yn "Eluna TS - TypeScript toolchain for Lua" "$(module_default MODULE_ELUNA_TS)")
    # Utility
    MODULE_NPC_BEASTMASTER=$(ask_yn "NPC Beastmaster - Rare pet vendor" "$(module_default MODULE_NPC_BEASTMASTER)")
    MODULE_NPC_ENCHANTER=$(ask_yn "NPC Enchanter - Gear enchanting service" "$(module_default MODULE_NPC_ENCHANTER)")
    MODULE_RANDOM_ENCHANTS=$(ask_yn "Random Enchants - Suffix property system" "$(module_default MODULE_RANDOM_ENCHANTS)")
    MODULE_POCKET_PORTAL=$(ask_yn "Pocket Portal - Personal teleportation device" "$(module_default MODULE_POCKET_PORTAL)")
    MODULE_INSTANCE_RESET=$(ask_yn "Instance Reset - Dungeon lockout management" "$(module_default MODULE_INSTANCE_RESET)")
    MODULE_TIME_IS_TIME=$(ask_yn "Time is Time - Real-time clock system" "$(module_default MODULE_TIME_IS_TIME)")
    MODULE_GAIN_HONOR_GUARD=$(ask_yn "Gain Honor Guard - Honor from guard kills" "$(module_default MODULE_GAIN_HONOR_GUARD)")
    MODULE_ARAC=$(ask_yn "All Races All Classes (requires client patch)" "$(module_default MODULE_ARAC)")
    MODULE_WORGOBLIN=$(ask_yn "Worgoblin - Worgen & Goblin races (client patch required)" "$(module_default MODULE_WORGOBLIN)")
  elif [ "$MODE" = "preset" ]; then
    local preset_modules="${MODULE_PRESET_CONFIGS[$MODE_PRESET_NAME]}"
    if [ -n "$preset_modules" ]; then
      apply_module_preset "$preset_modules"
      say INFO "Applied preset '${MODE_PRESET_NAME}'."
    else
      say WARNING "Preset '${MODE_PRESET_NAME}' did not contain any module selections."
    fi
  fi

  if [ -n "$CLI_PLAYERBOT_ENABLED" ]; then
    if [[ "$CLI_PLAYERBOT_ENABLED" != "0" && "$CLI_PLAYERBOT_ENABLED" != "1" ]]; then
      say ERROR "--playerbot-enabled must be 0 or 1"
      exit 1
    fi
    PLAYERBOT_ENABLED="$CLI_PLAYERBOT_ENABLED"
  fi
  if [ -n "$CLI_PLAYERBOT_MAX" ]; then
    if ! [[ "$CLI_PLAYERBOT_MAX" =~ ^[0-9]+$ ]]; then
      say ERROR "--playerbot-max-bots must be numeric"
      exit 1
    fi
    PLAYERBOT_MAX_BOTS="$CLI_PLAYERBOT_MAX"
  fi

  if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    if [ -z "$CLI_PLAYERBOT_ENABLED" ]; then
      PLAYERBOT_ENABLED=1
    fi
    PLAYERBOT_MAX_BOTS=$(ask "Maximum concurrent playerbots" "${CLI_PLAYERBOT_MAX:-40}" validate_number)
  fi

  for mod_var in MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT MODULE_ARAC MODULE_ASSISTANT MODULE_REAGENT_BANK MODULE_BLACK_MARKET_AUCTION_HOUSE MODULE_PLAYER_BOT_LEVEL_BRACKETS MODULE_OLLAMA_CHAT MODULE_CHALLENGE_MODES MODULE_STATBOOSTER MODULE_DUNGEON_RESPAWN MODULE_SKELETON_MODULE MODULE_BG_SLAVERYVALLEY MODULE_AZEROTHSHARD MODULE_WORGOBLIN; do
    eval "value=\$$mod_var"
    if [ "$value" = "1" ]; then
      NEEDS_CXX_REBUILD=1
      break
    fi
  done

  if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_AUTH_IMAGE_PLAYERBOTS"
    AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_WORLD_IMAGE_PLAYERBOTS"
  fi

  local SUMMARY_MODE_TEXT
  case "$MODE" in
    1) SUMMARY_MODE_TEXT="preset 1 (Suggested)" ;;
    2) SUMMARY_MODE_TEXT="preset 2 (Playerbots + Suggested)" ;;
    3) SUMMARY_MODE_TEXT="preset 3 (Manual)" ;;
    4) SUMMARY_MODE_TEXT="preset 4 (No modules)" ;;
    preset) SUMMARY_MODE_TEXT="preset (${MODE_PRESET_NAME})" ;;
    *) SUMMARY_MODE_TEXT="$MODE" ;;
  esac

  # Summary
  say HEADER "SUMMARY"
  printf "  %-18s %s\n" "Server Address:" "$SERVER_ADDRESS"
  printf "  %-18s Realm:%s  Auth:%s  SOAP:%s  MySQL:%s\n" "Ports:" "$REALM_PORT" "$AUTH_EXTERNAL_PORT" "$SOAP_EXTERNAL_PORT" "$MYSQL_EXTERNAL_PORT"
  printf "  %-18s %s\n" "Storage Path:" "$STORAGE_PATH"
  printf "  %-18s %s\n" "Container User:" "$CONTAINER_USER"
  printf "  %-18s Daily %s:00 UTC, keep %sd/%sh\n" "Backups:" "$BACKUP_DAILY_TIME" "$BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_HOURS"

  printf "  %-18s %s\n" "Modules preset:" "$SUMMARY_MODE_TEXT"
  printf "  %-18s %s\n" "Playerbot Max Bots:" "$PLAYERBOT_MAX_BOTS"
  printf "  %-18s" "Enabled Modules:"
  local first=1
  for module_var in "${KNOWN_MODULE_VARS[@]}"; do
    eval "value=\$$module_var"
    if [ "$value" = "1" ]; then
      if [ $first -eq 1 ]; then
        printf " %s" "${module_var#MODULE_}"
        first=0
      else
        printf ", %s" "${module_var#MODULE_}"
      fi
    fi
  done
  if [ $first -eq 1 ]; then
    printf " none"
  fi
  printf "\n"
  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    printf "  %-18s detected (source rebuild required)\n" "C++ modules:"
  fi

  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    echo ""
    say WARNING "These modules require compiling AzerothCore from source."
    if [ "$CLI_RUN_REBUILD" = "1" ]; then
      RUN_REBUILD_NOW=1
    else
      RUN_REBUILD_NOW=$(ask_yn "Run module rebuild immediately?" n)
    fi
    if [ "$CLI_AUTO_REBUILD" = "1" ]; then
      AUTO_REBUILD_ON_DEPLOY=1
    else
      AUTO_REBUILD_ON_DEPLOY=$(ask_yn "Enable automatic rebuild during future deploys?" "$( [ "$AUTO_REBUILD_ON_DEPLOY" = "1" ] && echo y || echo n )")
    fi
    if [ "$RUN_REBUILD_NOW" = "1" ] || [ "$AUTO_REBUILD_ON_DEPLOY" = "1" ]; then
      if [ -z "$MODULES_REBUILD_SOURCE_PATH_VALUE" ]; then
        MODULES_REBUILD_SOURCE_PATH_VALUE="./source/azerothcore"
        say INFO "Using default source path: ${MODULES_REBUILD_SOURCE_PATH_VALUE}"
      fi
    fi
  fi

  if [ "$RUN_REBUILD_NOW" = "1" ]; then
    if ! ./scripts/rebuild-with-modules.sh --yes --skip-stop; then
      say WARNING "Module rebuild failed; run ./scripts/rebuild-with-modules.sh manually."
    fi
  fi

  # Confirm write

  local ENV_OUT="$(dirname "$0")/.env"
  if [ -f "$ENV_OUT" ]; then
    say WARNING ".env already exists at $(realpath "$ENV_OUT" 2>/dev/null || echo "$ENV_OUT"). It will be overwritten."
    local cont
    if [ "$FORCE_OVERWRITE" = "1" ]; then
      cont=1
    else
      cont=$(ask_yn "Continue and overwrite?" n)
    fi
    [ "$cont" = "1" ] || { say ERROR "Aborted"; exit 1; }
  fi

  if [ -z "$MODULES_REBUILD_SOURCE_PATH_VALUE" ]; then
    MODULES_REBUILD_SOURCE_PATH_VALUE="./source/azerothcore"
  fi

  DB_PLAYERBOTS_NAME=${DB_PLAYERBOTS_NAME:-acore_playerbots}

  cat > "$ENV_OUT" <<EOF
# Generated by ac-compose/setup.sh

COMPOSE_PROJECT_NAME=ac-compose

STORAGE_PATH=$STORAGE_PATH
TZ=UTC

# Database
MYSQL_IMAGE=mysql:8.0
CONTAINER_MYSQL=ac-mysql
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_ROOT_HOST=%
MYSQL_USER=root
MYSQL_PORT=3306
MYSQL_EXTERNAL_PORT=$MYSQL_EXTERNAL_PORT
MYSQL_CHARACTER_SET=utf8mb4
MYSQL_COLLATION=utf8mb4_unicode_ci
MYSQL_MAX_CONNECTIONS=1000
MYSQL_INNODB_BUFFER_POOL_SIZE=256M
MYSQL_INNODB_LOG_FILE_SIZE=64M
DB_AUTH_NAME=acore_auth
DB_WORLD_NAME=acore_world
DB_CHARACTERS_NAME=acore_characters
DB_PLAYERBOTS_NAME=$DB_PLAYERBOTS_NAME
AC_DB_IMPORT_IMAGE=acore/ac-wotlk-db-import:14.0.0-dev

# Services (images)
AC_AUTHSERVER_IMAGE=acore/ac-wotlk-authserver:14.0.0-dev
AC_WORLDSERVER_IMAGE=acore/ac-wotlk-worldserver:14.0.0-dev
AC_AUTHSERVER_IMAGE_PLAYERBOTS=${AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE}
AC_WORLDSERVER_IMAGE_PLAYERBOTS=${AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE}

# Client data images
AC_CLIENT_DATA_IMAGE=acore/ac-wotlk-client-data:14.0.0-dev
AC_CLIENT_DATA_IMAGE_PLAYERBOTS=uprightbass360/azerothcore-wotlk-playerbots:client-data-Playerbot

# Ports
AUTH_EXTERNAL_PORT=$AUTH_EXTERNAL_PORT
AUTH_PORT=3724
WORLD_EXTERNAL_PORT=$REALM_PORT
WORLD_PORT=8085
SOAP_EXTERNAL_PORT=$SOAP_EXTERNAL_PORT
SOAP_PORT=7878

# Realm
SERVER_ADDRESS=$SERVER_ADDRESS
REALM_PORT=$REALM_PORT

# Backups
BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS
BACKUP_RETENTION_HOURS=$BACKUP_RETENTION_HOURS
BACKUP_DAILY_TIME=$BACKUP_DAILY_TIME

# Container user
CONTAINER_USER=$CONTAINER_USER

# Modules
MODULE_PLAYERBOTS=$MODULE_PLAYERBOTS
MODULE_AOE_LOOT=$MODULE_AOE_LOOT
MODULE_LEARN_SPELLS=$MODULE_LEARN_SPELLS
MODULE_FIREWORKS=$MODULE_FIREWORKS
MODULE_INDIVIDUAL_PROGRESSION=$MODULE_INDIVIDUAL_PROGRESSION
MODULE_AHBOT=$MODULE_AHBOT
MODULE_AUTOBALANCE=$MODULE_AUTOBALANCE
MODULE_TRANSMOG=$MODULE_TRANSMOG
MODULE_NPC_BUFFER=$MODULE_NPC_BUFFER
MODULE_DYNAMIC_XP=$MODULE_DYNAMIC_XP
MODULE_SOLO_LFG=$MODULE_SOLO_LFG
MODULE_1V1_ARENA=$MODULE_1V1_ARENA
MODULE_PHASED_DUELS=$MODULE_PHASED_DUELS
MODULE_BREAKING_NEWS=$MODULE_BREAKING_NEWS
MODULE_BOSS_ANNOUNCER=$MODULE_BOSS_ANNOUNCER
MODULE_ACCOUNT_ACHIEVEMENTS=$MODULE_ACCOUNT_ACHIEVEMENTS
MODULE_AUTO_REVIVE=$MODULE_AUTO_REVIVE
MODULE_GAIN_HONOR_GUARD=$MODULE_GAIN_HONOR_GUARD
MODULE_ARAC=$MODULE_ARAC
MODULE_TIME_IS_TIME=$MODULE_TIME_IS_TIME
MODULE_POCKET_PORTAL=$MODULE_POCKET_PORTAL
MODULE_RANDOM_ENCHANTS=$MODULE_RANDOM_ENCHANTS
MODULE_SOLOCRAFT=$MODULE_SOLOCRAFT
MODULE_PVP_TITLES=$MODULE_PVP_TITLES
MODULE_NPC_BEASTMASTER=$MODULE_NPC_BEASTMASTER
MODULE_NPC_ENCHANTER=$MODULE_NPC_ENCHANTER
MODULE_INSTANCE_RESET=$MODULE_INSTANCE_RESET
MODULE_LEVEL_GRANT=$MODULE_LEVEL_GRANT
MODULE_CHALLENGE_MODES=$MODULE_CHALLENGE_MODES
MODULE_OLLAMA_CHAT=$MODULE_OLLAMA_CHAT
MODULE_SKELETON_MODULE=$MODULE_SKELETON_MODULE
MODULE_BG_SLAVERYVALLEY=$MODULE_BG_SLAVERYVALLEY
MODULE_ELUNA_TS=$MODULE_ELUNA_TS
MODULE_PLAYER_BOT_LEVEL_BRACKETS=$MODULE_PLAYER_BOT_LEVEL_BRACKETS
MODULE_STATBOOSTER=$MODULE_STATBOOSTER
MODULE_DUNGEON_RESPAWN=$MODULE_DUNGEON_RESPAWN
MODULE_AZEROTHSHARD=$MODULE_AZEROTHSHARD
MODULE_WORGOBLIN=$MODULE_WORGOBLIN
MODULE_ASSISTANT=$MODULE_ASSISTANT
MODULE_REAGENT_BANK=$MODULE_REAGENT_BANK
MODULE_BLACK_MARKET_AUCTION_HOUSE=$MODULE_BLACK_MARKET_AUCTION_HOUSE

# Client data
CLIENT_DATA_VERSION=${CLIENT_DATA_VERSION:-v16}

# Playerbot runtime
PLAYERBOT_ENABLED=$PLAYERBOT_ENABLED
PLAYERBOT_MAX_BOTS=$PLAYERBOT_MAX_BOTS

# Rebuild automation
AUTO_REBUILD_ON_DEPLOY=$AUTO_REBUILD_ON_DEPLOY
MODULES_REBUILD_SOURCE_PATH=$MODULES_REBUILD_SOURCE_PATH_VALUE

# Eluna
AC_ELUNA_ENABLED=1
AC_ELUNA_TRACE_BACK=1
AC_ELUNA_AUTO_RELOAD=1
AC_ELUNA_BYTECODE_CACHE=1
AC_ELUNA_SCRIPT_PATH=lua_scripts
AC_ELUNA_REQUIRE_PATHS=
AC_ELUNA_REQUIRE_CPATHS=
AC_ELUNA_AUTO_RELOAD_INTERVAL=1

# Tools
PMA_HOST=ac-mysql
PMA_PORT=3306
PMA_USER=root
PMA_EXTERNAL_PORT=8081
PMA_ARBITRARY=1
PMA_ABSOLUTE_URI=
PMA_UPLOAD_LIMIT=300M
PMA_MEMORY_LIMIT=512M
PMA_MAX_EXECUTION_TIME=600
KEIRA3_EXTERNAL_PORT=4201
KEIRA_DATABASE_HOST=ac-mysql
KEIRA_DATABASE_PORT=3306

# Networking
NETWORK_NAME=azerothcore
NETWORK_SUBNET=172.20.0.0/16
NETWORK_GATEWAY=172.20.0.1
EOF

  say SUCCESS ".env written to $ENV_OUT"
  show_realm_configured

  if [ "$RUN_REBUILD_NOW" = "1" ]; then
    echo ""
    say HEADER "MODULE REBUILD"
    if [ -n "$MODULES_REBUILD_SOURCE_PATH_VALUE" ]; then
      if ./scripts/rebuild-with-modules.sh --yes --source "$MODULES_REBUILD_SOURCE_PATH_VALUE"; then
        say SUCCESS "Module rebuild completed"
      else
        say WARNING "Module rebuild failed; run ./scripts/rebuild-with-modules.sh manually once issues are resolved."
      fi
    else
      say WARNING "Rebuild path was not provided; skipping automatic rebuild."
    fi
  fi

  say INFO "Ready to bring your realm online:"
  if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    echo "  🚀 Quick deploy: ./deploy.sh"
    echo "  🔧 Manual: docker compose --profile db --profile services-playerbots --profile client-data-bots --profile modules up -d"
  else
    echo "  🚀 Quick deploy: ./deploy.sh"
    echo "  🔧 Manual: docker compose --profile db --profile services-standard --profile client-data --profile modules up -d"
  fi
}

main "$@"

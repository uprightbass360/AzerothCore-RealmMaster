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

ask(){
  local prompt="$1"; local def="$2"; local validator="$3"; local v
  while true; do
    if [ -n "$def" ]; then
      read -p "$(echo -e "${YELLOW}🔧 ${prompt} [${def}]: ${NC}")" v; v=${v:-$def}
    else
      read -p "$(echo -e "${YELLOW}🔧 ${prompt}: ${NC}")" v
    fi
    if [ -z "$validator" ] || $validator "$v"; then echo "$v"; return 0; fi
    say ERROR "Invalid input. Please try again."
  done
}

ask_yn(){ local p="$1"; local d="$2"; local v; while true; do
  if [ "$d" = "y" ]; then read -p "$(echo -e "${YELLOW}🔧 ${p} [Y/n]: ${NC}")" v; v=${v:-y}; else read -p "$(echo -e "${YELLOW}🔧 ${p} [y/N]: ${NC}")" v; v=${v:-n}; fi
  case "$v" in [Yy]*) echo 1; return 0;; [Nn]*) echo 0; return 0;; esac; say ERROR "Please answer y or n"; done; }

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
  # Basic arg handling for help
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        cat <<'EOF'
Usage: ./setup.sh

Description:
  Interactive wizard that generates ac-compose/.env for the
  profiles-based compose. Prompts for deployment type, ports, storage,
  MySQL credentials, backup retention, and module presets or manual
  toggles.

Notes:
  - The generated .env is read automatically by docker compose.
  - Run deploy with: deploy.sh or docker compose --profile ... up -d
EOF
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        echo "Use --help for usage" >&2
        exit 1
        ;;
    esac
  fi
  show_wow_header
  say INFO "This will create ac-compose/.env for compose profiles."

  # Deployment type
  say HEADER "DEPLOYMENT TYPE"
  echo "1) 🏠 Local Development (127.0.0.1, local storage)"
  echo "2) 🌐 LAN Server (local network IP)"
  echo "3) ☁️  Public Server (domain or public IP)"
  local DEPLOYMENT_TYPE
  while true; do
    read -p "$(echo -e "${YELLOW}🔧 Select deployment type [1-3]: ${NC}")" x
    case "$x" in
      1) DEPLOYMENT_TYPE=local; break;;
      2) DEPLOYMENT_TYPE=lan; break;;
      3) DEPLOYMENT_TYPE=public; break;;
      *) say ERROR "Please select 1, 2, or 3";;
    esac
  done

  # Permission scheme
  say HEADER "PERMISSION SCHEME"
  echo "1) 🏠 Local Dev (0:0)"
  echo "2) 🗂️  NFS Server (1001:1000)"
  echo "3) ⚙️  Custom"
  local CONTAINER_USER
  while true; do
    read -p "$(echo -e "${YELLOW}🔧 Select permission scheme [1-3]: ${NC}")" x
    case "$x" in
      1) CONTAINER_USER="0:0"; break;;
      2) CONTAINER_USER="1001:1000"; break;;
      3) local uid gid; uid=$(ask "Enter PUID (user id)" 1000 validate_number); gid=$(ask "Enter PGID (group id)" 1000 validate_number); CONTAINER_USER="${uid}:${gid}"; break;;
      *) say ERROR "Please select 1, 2, or 3";;
    esac
  done

  # Server config
  say HEADER "SERVER CONFIGURATION"
  local SERVER_ADDRESS
  if [ "$DEPLOYMENT_TYPE" = "local" ]; then
    SERVER_ADDRESS=127.0.0.1
  elif [ "$DEPLOYMENT_TYPE" = "lan" ]; then
    local LAN_IP; LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $7}')
    SERVER_ADDRESS=$(ask "Enter server IP address" "${LAN_IP:-192.168.1.100}" validate_ip)
  else
    SERVER_ADDRESS=$(ask "Enter server address (IP or domain)" "your-domain.com" )
  fi

  local REALM_PORT AUTH_EXTERNAL_PORT SOAP_EXTERNAL_PORT MYSQL_EXTERNAL_PORT
  REALM_PORT=$(ask "Enter client connection port" 8215 validate_port)
  AUTH_EXTERNAL_PORT=$(ask "Enter auth server port" 3784 validate_port)
  SOAP_EXTERNAL_PORT=$(ask "Enter SOAP API port" 7778 validate_port)
  MYSQL_EXTERNAL_PORT=$(ask "Enter MySQL external port" 64306 validate_port)

  # DB config
  say HEADER "DATABASE CONFIGURATION"
  local MYSQL_ROOT_PASSWORD; MYSQL_ROOT_PASSWORD=$(ask "Enter MySQL root password" "azerothcore123")

  # Storage
  say HEADER "STORAGE CONFIGURATION"
  local STORAGE_PATH
  if [ "$DEPLOYMENT_TYPE" = "local" ]; then
    STORAGE_PATH=./storage
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

  # Backup
  say HEADER "BACKUP CONFIGURATION"
  local BACKUP_RETENTION_DAYS BACKUP_RETENTION_HOURS BACKUP_DAILY_TIME
  BACKUP_RETENTION_DAYS=$(ask "Daily backups retention (days)" 3 validate_number)
  BACKUP_RETENTION_HOURS=$(ask "Hourly backups retention (hours)" 6 validate_number)
  BACKUP_DAILY_TIME=$(ask "Daily backup hour (00-23, UTC)" 09 validate_number)

  # Module config
  say HEADER "MODULE PRESET"
  echo "1) ⭐ Suggested Modules"
  echo "2) 🤖 Playerbots + Suggested modules"
  echo "3) ⚙️  Manual selection"
  echo "4) 🚫 No modules"
  local MODE; while true; do
    read -p "$(echo -e "${YELLOW}🔧 Select module configuration [1-4]: ${NC}")" MODE
    case "$MODE" in 1|2|3|4) break;; *) say ERROR "Please select 1, 2, 3, or 4";; esac
  done

  # Initialize toggles
  local MODULE_PLAYERBOTS=0 MODULE_AOE_LOOT=0 MODULE_LEARN_SPELLS=0 MODULE_FIREWORKS=0 MODULE_INDIVIDUAL_PROGRESSION=0 \
        MODULE_AHBOT=0 MODULE_AUTOBALANCE=0 MODULE_TRANSMOG=0 MODULE_NPC_BUFFER=0 MODULE_DYNAMIC_XP=0 MODULE_SOLO_LFG=0 \
        MODULE_1V1_ARENA=0 MODULE_PHASED_DUELS=0 MODULE_BREAKING_NEWS=0 MODULE_BOSS_ANNOUNCER=0 MODULE_ACCOUNT_ACHIEVEMENTS=0 \
        MODULE_AUTO_REVIVE=0 MODULE_GAIN_HONOR_GUARD=0 MODULE_TIME_IS_TIME=0 MODULE_POCKET_PORTAL=0 \
        MODULE_RANDOM_ENCHANTS=0 MODULE_SOLOCRAFT=0 MODULE_PVP_TITLES=0 MODULE_NPC_BEASTMASTER=0 MODULE_NPC_ENCHANTER=0 \
        MODULE_INSTANCE_RESET=0 MODULE_LEVEL_GRANT=0 MODULE_ASSISTANT=0 MODULE_REAGENT_BANK=0 MODULE_BLACK_MARKET_AUCTION_HOUSE=0 MODULE_ARAC=0

  declare -A DISABLED_MODULE_REASONS=(
    [MODULE_AHBOT]="Requires upstream Addmod_ahbotScripts symbol (fails link)"
    [MODULE_LEVEL_GRANT]="QuestCountLevel module relies on removed ConfigMgr APIs and fails to build"
  )

  local PLAYERBOT_ENABLED=0 PLAYERBOT_MAX_BOTS=40

  local AUTO_REBUILD_ON_DEPLOY=0
  local MODULES_REBUILD_SOURCE_PATH_VALUE=""
  local RUN_REBUILD_NOW=0
  local NEEDS_CXX_REBUILD=0

  if [ "$MODE" = "1" ]; then
    MODULE_SOLO_LFG=1; MODULE_SOLOCRAFT=1; MODULE_AUTOBALANCE=1; MODULE_TRANSMOG=1; MODULE_NPC_BUFFER=1; MODULE_LEARN_SPELLS=1; MODULE_FIREWORKS=1
  elif [ "$MODE" = "2" ]; then
    MODULE_PLAYERBOTS=1; MODULE_SOLO_LFG=1; MODULE_SOLOCRAFT=1; MODULE_AUTOBALANCE=1; MODULE_TRANSMOG=1; MODULE_NPC_BUFFER=1; MODULE_LEARN_SPELLS=1; MODULE_FIREWORKS=1
  elif [ "$MODE" = "3" ]; then
    say INFO "Answer y/n for each module"
    for key in "${!DISABLED_MODULE_REASONS[@]}"; do
      say WARNING "${key#MODULE_}: ${DISABLED_MODULE_REASONS[$key]}"
    done
    # Core Gameplay
    MODULE_PLAYERBOTS=$(ask_yn "Playerbots - AI companions" n)
    MODULE_SOLO_LFG=$(ask_yn "Solo LFG - Solo dungeon finder" n)
    MODULE_SOLOCRAFT=$(ask_yn "Solocraft - Scale dungeons/raids for solo" n)
    MODULE_AUTOBALANCE=$(ask_yn "Autobalance - Dynamic difficulty" n)
    # QoL
    MODULE_TRANSMOG=$(ask_yn "Transmog - Appearance changes" n)
    MODULE_NPC_BUFFER=$(ask_yn "NPC Buffer - Buff NPCs" n)
    MODULE_LEARN_SPELLS=$(ask_yn "Learn Spells - Auto-learn" n)
    MODULE_AOE_LOOT=$(ask_yn "AOE Loot - Multi-corpse loot" n)
    MODULE_FIREWORKS=$(ask_yn "Fireworks - Level-up FX" n)
    MODULE_ASSISTANT=$(ask_yn "Assistant - Multi-service NPC" n)
    # Economy
    MODULE_AHBOT=$(ask_yn "AH Bot - Auction automation" n)
    MODULE_REAGENT_BANK=$(ask_yn "Reagent Bank - Materials storage" n)
    MODULE_BLACK_MARKET_AUCTION_HOUSE=$(ask_yn "Black Market - MoP-style" n)
    # PvP
    MODULE_1V1_ARENA=$(ask_yn "1v1 Arena" n)
    MODULE_PHASED_DUELS=$(ask_yn "Phased Duels" n)
    MODULE_PVP_TITLES=$(ask_yn "PvP Titles" n)
    # Progression
    MODULE_INDIVIDUAL_PROGRESSION=$(ask_yn "Individual Progression (Vanilla→TBC→WotLK)" n)
    MODULE_DYNAMIC_XP=$(ask_yn "Dynamic XP" n)
    MODULE_ACCOUNT_ACHIEVEMENTS=$(ask_yn "Account Achievements" n)
    # Server Features
    MODULE_BREAKING_NEWS=$(ask_yn "Breaking News" n)
    MODULE_BOSS_ANNOUNCER=$(ask_yn "Boss Announcer" n)
    MODULE_AUTO_REVIVE=$(ask_yn "Auto Revive" n)
    # Utility
    MODULE_NPC_BEASTMASTER=$(ask_yn "NPC Beastmaster" n)
    MODULE_NPC_ENCHANTER=$(ask_yn "NPC Enchanter" n)
    MODULE_RANDOM_ENCHANTS=$(ask_yn "Random Enchants" n)
    MODULE_POCKET_PORTAL=$(ask_yn "Pocket Portal" n)
    MODULE_INSTANCE_RESET=$(ask_yn "Instance Reset" n)
    MODULE_TIME_IS_TIME=$(ask_yn "Time is Time" n)
    MODULE_GAIN_HONOR_GUARD=$(ask_yn "Gain Honor Guard" n)
    MODULE_ARAC=$(ask_yn "All Races All Classes (requires client patch)" n)
  fi

  for mod_var in MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT MODULE_ARAC MODULE_ASSISTANT MODULE_REAGENT_BANK MODULE_BLACK_MARKET_AUCTION_HOUSE; do
    eval "value=\$$mod_var"
    if [ "$value" = "1" ]; then
      NEEDS_CXX_REBUILD=1
      break
    fi
  done

  # Summary
  say HEADER "SUMMARY"
  printf "  %-18s %s\n" "Server Address:" "$SERVER_ADDRESS"
  printf "  %-18s Realm:%s  Auth:%s  SOAP:%s  MySQL:%s\n" "Ports:" "$REALM_PORT" "$AUTH_EXTERNAL_PORT" "$SOAP_EXTERNAL_PORT" "$MYSQL_EXTERNAL_PORT"
  printf "  %-18s %s\n" "Storage Path:" "$STORAGE_PATH"
  printf "  %-18s %s\n" "Container User:" "$CONTAINER_USER"
  printf "  %-18s Daily %s:00 UTC, keep %sd/%sh\n" "Backups:" "$BACKUP_DAILY_TIME" "$BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_HOURS"
  printf "  %-18s preset %s (playerbots=%s solo_lfg=%s autobalance=%s transmog=%s npc_buffer=%s learn_spells=%s fireworks=%s)\n" \
    "Modules:" "$MODE" "$MODULE_PLAYERBOTS" "$MODULE_SOLO_LFG" "$MODULE_AUTOBALANCE" "$MODULE_TRANSMOG" "$MODULE_NPC_BUFFER" "$MODULE_LEARN_SPELLS" "$MODULE_FIREWORKS"
  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    printf "  %-18s detected (source rebuild required)\n" "C++ modules:"
  fi

  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    echo ""
    say WARNING "These modules require compiling AzerothCore from source."
    RUN_REBUILD_NOW=$(ask_yn "Run module rebuild immediately?" n)
    AUTO_REBUILD_ON_DEPLOY=$(ask_yn "Enable automatic rebuild during future deploys?" n)
    if [ "$RUN_REBUILD_NOW" = "1" ] || [ "$AUTO_REBUILD_ON_DEPLOY" = "1" ]; then
      if [ -z "$MODULES_REBUILD_SOURCE_PATH_VALUE" ]; then
        MODULES_REBUILD_SOURCE_PATH_VALUE="./source/azerothcore"
        say INFO "Using default source path: ${MODULES_REBUILD_SOURCE_PATH_VALUE}"
      fi
    fi
  fi

  # Confirm write
  local ENV_OUT="$(dirname "$0")/.env"
  if [ -f "$ENV_OUT" ]; then
    say WARNING ".env already exists at $(realpath "$ENV_OUT" 2>/dev/null || echo "$ENV_OUT"). It will be overwritten."
    local cont; cont=$(ask_yn "Continue and overwrite?" n); [ "$cont" = "1" ] || { say ERROR "Aborted"; exit 1; }
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
AC_AUTHSERVER_IMAGE_PLAYERBOTS=uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot
AC_WORLDSERVER_IMAGE_PLAYERBOTS=uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot

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
  if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    PLAYERBOT_ENABLED=1
    PLAYERBOT_MAX_BOTS=$(ask "Maximum concurrent playerbots" 40 validate_number)
  fi

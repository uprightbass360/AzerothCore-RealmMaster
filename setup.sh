#!/bin/bash
set -e
clear

# ==============================================
# AzerothCore-RealmMaster - Interactive .env generator
# ==============================================
# Mirrors options from scripts/setup-server.sh but targets .env

# Get script directory for template reading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default project name (can be overridden by COMPOSE_PROJECT_NAME in .env)
ENV_FILE="$SCRIPT_DIR/.env"
TEMPLATE_FILE="$SCRIPT_DIR/.env.template"
source "$SCRIPT_DIR/scripts/bash/project_name.sh"
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"

# ==============================================
# Feature Flags
# ==============================================
# Set to 0 to disable server configuration preset selection
ENABLE_CONFIG_PRESETS="${ENABLE_CONFIG_PRESETS:-0}"

# ==============================================
# Constants (auto-loaded from .env.template)
# ==============================================

# Function to read value from .env.template (required)
get_template_value() {
  local key="$1"
  local template_file="$SCRIPT_DIR/.env.template"

  if [ ! -f "$template_file" ]; then
    echo "ERROR: .env.template file not found at $template_file" >&2
    echo "This file is required for setup.sh to function properly." >&2
    exit 1
  fi

  # Extract value, handling variable expansion syntax like ${VAR:-default}
  local value
  local raw_line
  raw_line=$(grep "^${key}=" "$template_file" | head -1)
  if [ -z "$raw_line" ]; then
    echo "ERROR: Required key '$key' not found in .env.template" >&2
    exit 1
  fi
  value="${raw_line#*=}"
  value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')

  # Handle ${VAR:-default} syntax by extracting the default value
  if [[ "$value" =~ ^\$\{[^}]*:-([^}]*)\}$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  echo "$value"
}

sanitize_project_name(){
  project_name::sanitize "$1"
}

resolve_project_image_tag(){
  local project="$1" tag="$2"
  echo "${project}:${tag}"
}

declare -A TEMPLATE_VALUE_MAP=(
  [DEFAULT_MYSQL_PASSWORD]=MYSQL_ROOT_PASSWORD
  [DEFAULT_REALM_PORT]=WORLD_EXTERNAL_PORT
  [DEFAULT_AUTH_PORT]=AUTH_EXTERNAL_PORT
  [DEFAULT_SOAP_PORT]=SOAP_EXTERNAL_PORT
  [DEFAULT_MYSQL_PORT]=MYSQL_EXTERNAL_PORT
  [DEFAULT_PLAYERBOT_MIN]=PLAYERBOT_MIN_BOTS
  [DEFAULT_PLAYERBOT_MAX]=PLAYERBOT_MAX_BOTS
  [DEFAULT_LOCAL_STORAGE]=STORAGE_PATH
  [DEFAULT_BACKUP_PATH]=BACKUP_PATH
  [DEFAULT_COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED]=COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED
  [DEFAULT_COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED]=COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED
  [PERMISSION_LOCAL_USER]=DEFAULT_PERMISSION_LOCAL_USER
  [PERMISSION_NFS_USER]=DEFAULT_PERMISSION_NFS_USER
  [DEFAULT_CUSTOM_UID]=DEFAULT_CUSTOM_UID
  [DEFAULT_CUSTOM_GID]=DEFAULT_CUSTOM_GID
  [DEFAULT_LOCAL_ADDRESS]=SERVER_ADDRESS
  [DEFAULT_BACKUP_DAYS]=BACKUP_RETENTION_DAYS
  [DEFAULT_BACKUP_HOURS]=BACKUP_RETENTION_HOURS
  [DEFAULT_BACKUP_TIME]=BACKUP_DAILY_TIME
  [DEFAULT_BACKUP_HEALTHCHECK_MAX_MINUTES]=BACKUP_HEALTHCHECK_MAX_MINUTES
  [DEFAULT_BACKUP_HEALTHCHECK_GRACE_SECONDS]=BACKUP_HEALTHCHECK_GRACE_SECONDS
  [DEFAULT_NFS_STORAGE]=DEFAULT_NFS_STORAGE_PATH
  [DEFAULT_MOUNT_STORAGE]=DEFAULT_MOUNT_STORAGE_PATH
  [DEFAULT_MYSQL_IMAGE]=MYSQL_IMAGE
  [DEFAULT_AC_DB_IMPORT_IMAGE]=AC_DB_IMPORT_IMAGE
  [DEFAULT_AC_AUTHSERVER_IMAGE]=AC_AUTHSERVER_IMAGE
  [DEFAULT_AC_WORLDSERVER_IMAGE]=AC_WORLDSERVER_IMAGE
  [DEFAULT_AC_CLIENT_DATA_IMAGE]=AC_CLIENT_DATA_IMAGE
  [DEFAULT_DOCKER_IMAGE_TAG]=DOCKER_IMAGE_TAG
  [DEFAULT_AUTHSERVER_IMAGE_BASE]=AC_AUTHSERVER_IMAGE_BASE
  [DEFAULT_WORLDSERVER_IMAGE_BASE]=AC_WORLDSERVER_IMAGE_BASE
  [DEFAULT_DB_IMPORT_IMAGE_BASE]=AC_DB_IMPORT_IMAGE_BASE
  [DEFAULT_CLIENT_DATA_IMAGE_BASE]=AC_CLIENT_DATA_IMAGE_BASE
  [DEFAULT_AUTH_IMAGE_PLAYERBOTS]=AC_AUTHSERVER_IMAGE_PLAYERBOTS
  [DEFAULT_WORLD_IMAGE_PLAYERBOTS]=AC_WORLDSERVER_IMAGE_PLAYERBOTS
  [DEFAULT_CLIENT_DATA_IMAGE_PLAYERBOTS]=AC_CLIENT_DATA_IMAGE_PLAYERBOTS
  [DEFAULT_AUTH_IMAGE_MODULES]=AC_AUTHSERVER_IMAGE_MODULES
  [DEFAULT_WORLD_IMAGE_MODULES]=AC_WORLDSERVER_IMAGE_MODULES
  [DEFAULT_ALPINE_GIT_IMAGE]=ALPINE_GIT_IMAGE
  [DEFAULT_ALPINE_IMAGE]=ALPINE_IMAGE
  [DEFAULT_DB_AUTH_NAME]=DB_AUTH_NAME
  [DEFAULT_DB_WORLD_NAME]=DB_WORLD_NAME
  [DEFAULT_DB_CHARACTERS_NAME]=DB_CHARACTERS_NAME
  [DEFAULT_DB_PLAYERBOTS_NAME]=DB_PLAYERBOTS_NAME
  [DEFAULT_CONTAINER_MYSQL]=CONTAINER_MYSQL
  [DEFAULT_CONTAINER_DB_IMPORT]=CONTAINER_DB_IMPORT
  [DEFAULT_CONTAINER_DB_INIT]=CONTAINER_DB_INIT
  [DEFAULT_CONTAINER_BACKUP]=CONTAINER_BACKUP
  [DEFAULT_CONTAINER_MODULES]=CONTAINER_MODULES
  [DEFAULT_CONTAINER_POST_INSTALL]=CONTAINER_POST_INSTALL
  [DEFAULT_COMPOSE_PROJECT_NAME]=COMPOSE_PROJECT_NAME
  [DEFAULT_CLIENT_DATA_PATH]=CLIENT_DATA_PATH
  [DEFAULT_CLIENT_DATA_CACHE_PATH]=CLIENT_DATA_CACHE_PATH
  [DEFAULT_CLIENT_DATA_VERSION]=CLIENT_DATA_VERSION
  [DEFAULT_NETWORK_NAME]=NETWORK_NAME
  [DEFAULT_NETWORK_SUBNET]=NETWORK_SUBNET
  [DEFAULT_NETWORK_GATEWAY]=NETWORK_GATEWAY
  [DEFAULT_MYSQL_CHARACTER_SET]=MYSQL_CHARACTER_SET
  [DEFAULT_MYSQL_COLLATION]=MYSQL_COLLATION
  [DEFAULT_MYSQL_MAX_CONNECTIONS]=MYSQL_MAX_CONNECTIONS
  [DEFAULT_MYSQL_INNODB_BUFFER_POOL_SIZE]=MYSQL_INNODB_BUFFER_POOL_SIZE
  [DEFAULT_MYSQL_INNODB_LOG_FILE_SIZE]=MYSQL_INNODB_LOG_FILE_SIZE
  [DEFAULT_MYSQL_INNODB_REDO_LOG_CAPACITY]=MYSQL_INNODB_REDO_LOG_CAPACITY
  [DEFAULT_MYSQL_RUNTIME_TMPFS_SIZE]=MYSQL_RUNTIME_TMPFS_SIZE
  [DEFAULT_MYSQL_DISABLE_BINLOG]=MYSQL_DISABLE_BINLOG
  [DEFAULT_MYSQL_CONFIG_DIR]=MYSQL_CONFIG_DIR
  [DEFAULT_MYSQL_HOST]=MYSQL_HOST
  [DEFAULT_DB_WAIT_RETRIES]=DB_WAIT_RETRIES
  [DEFAULT_DB_WAIT_SLEEP]=DB_WAIT_SLEEP
  [DEFAULT_DB_RECONNECT_SECONDS]=DB_RECONNECT_SECONDS
  [DEFAULT_DB_RECONNECT_ATTEMPTS]=DB_RECONNECT_ATTEMPTS
  [DEFAULT_DB_UPDATES_ALLOWED_MODULES]=DB_UPDATES_ALLOWED_MODULES
  [DEFAULT_DB_UPDATES_REDUNDANCY]=DB_UPDATES_REDUNDANCY
  [DEFAULT_DB_LOGIN_WORKER_THREADS]=DB_LOGIN_WORKER_THREADS
  [DEFAULT_DB_WORLD_WORKER_THREADS]=DB_WORLD_WORKER_THREADS
  [DEFAULT_DB_CHARACTER_WORKER_THREADS]=DB_CHARACTER_WORKER_THREADS
  [DEFAULT_DB_LOGIN_SYNCH_THREADS]=DB_LOGIN_SYNCH_THREADS
  [DEFAULT_DB_WORLD_SYNCH_THREADS]=DB_WORLD_SYNCH_THREADS
  [DEFAULT_DB_CHARACTER_SYNCH_THREADS]=DB_CHARACTER_SYNCH_THREADS
  [DEFAULT_HOST_ZONEINFO_PATH]=HOST_ZONEINFO_PATH
  [DEFAULT_ELUNA_SCRIPT_PATH]=AC_ELUNA_SCRIPT_PATH
  [DEFAULT_PMA_EXTERNAL_PORT]=PMA_EXTERNAL_PORT
  [DEFAULT_PMA_UPLOAD_LIMIT]=PMA_UPLOAD_LIMIT
  [DEFAULT_PMA_MEMORY_LIMIT]=PMA_MEMORY_LIMIT
  [DEFAULT_PMA_MAX_EXECUTION_TIME]=PMA_MAX_EXECUTION_TIME
  [DEFAULT_KEIRA3_EXTERNAL_PORT]=KEIRA3_EXTERNAL_PORT
  [DEFAULT_PMA_USER]=PMA_USER
  [DEFAULT_PMA_ARBITRARY]=PMA_ARBITRARY
  [DEFAULT_PMA_ABSOLUTE_URI]=PMA_ABSOLUTE_URI
  [DEFAULT_AUTH_INTERNAL_PORT]=AUTH_PORT
  [DEFAULT_WORLD_INTERNAL_PORT]=WORLD_PORT
  [DEFAULT_SOAP_INTERNAL_PORT]=SOAP_PORT
  [DEFAULT_MYSQL_INTERNAL_PORT]=MYSQL_PORT
  [DEFAULT_TZ]=TZ
  [DEFAULT_MYSQL_ROOT_HOST]=MYSQL_ROOT_HOST
  [DEFAULT_MYSQL_USER]=MYSQL_USER
  [DEFAULT_ELUNA_ENABLED]=AC_ELUNA_ENABLED
  [DEFAULT_ELUNA_TRACE_BACK]=AC_ELUNA_TRACE_BACK
  [DEFAULT_ELUNA_AUTO_RELOAD]=AC_ELUNA_AUTO_RELOAD
  [DEFAULT_ELUNA_BYTECODE_CACHE]=AC_ELUNA_BYTECODE_CACHE
  [DEFAULT_ELUNA_AUTO_RELOAD_INTERVAL]=AC_ELUNA_AUTO_RELOAD_INTERVAL
  [DEFAULT_ELUNA_REQUIRE_PATHS]=AC_ELUNA_REQUIRE_PATHS
  [DEFAULT_ELUNA_REQUIRE_CPATHS]=AC_ELUNA_REQUIRE_CPATHS
  [DEFAULT_MODULE_ELUNA]=MODULE_ELUNA
)

for __template_var in "${!TEMPLATE_VALUE_MAP[@]}"; do
  __template_key="${TEMPLATE_VALUE_MAP[$__template_var]}"
  __template_value="$(get_template_value "${__template_key}")"
  printf -v "${__template_var}" '%s' "${__template_value}"
  readonly "${__template_var}"
done
unset __template_var __template_key __template_value

# Static values
readonly DEFAULT_FALLBACK_LAN_IP="192.168.1.100"
readonly DEFAULT_DOMAIN_PLACEHOLDER="your-domain.com"

# Module preset names (not in template)
readonly DEFAULT_PRESET_SUGGESTED="suggested-modules"
readonly DEFAULT_PRESET_PLAYERBOTS="suggested-modules-playerbots"

# Health check configuration (loaded via loop)
readonly -a HEALTHCHECK_KEYS=(
  MYSQL_HEALTHCHECK_INTERVAL
  MYSQL_HEALTHCHECK_TIMEOUT
  MYSQL_HEALTHCHECK_RETRIES
  MYSQL_HEALTHCHECK_START_PERIOD
  AUTH_HEALTHCHECK_INTERVAL
  AUTH_HEALTHCHECK_TIMEOUT
  AUTH_HEALTHCHECK_RETRIES
  AUTH_HEALTHCHECK_START_PERIOD
  WORLD_HEALTHCHECK_INTERVAL
  WORLD_HEALTHCHECK_TIMEOUT
  WORLD_HEALTHCHECK_RETRIES
  WORLD_HEALTHCHECK_START_PERIOD
  BACKUP_HEALTHCHECK_INTERVAL
  BACKUP_HEALTHCHECK_TIMEOUT
  BACKUP_HEALTHCHECK_RETRIES
  BACKUP_HEALTHCHECK_START_PERIOD
)
for __hc_key in "${HEALTHCHECK_KEYS[@]}"; do
  __hc_value="$(get_template_value "${__hc_key}")"
  printf -v "DEFAULT_${__hc_key}" '%s' "$__hc_value"
  readonly "DEFAULT_${__hc_key}"
done
unset __hc_key __hc_value

# Route detection IP (not in template)
readonly ROUTE_DETECTION_IP="1.1.1.1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
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

module_default(){
  local key="$1"
  if [ "${MODULE_ENABLE_SET[$key]:-0}" = "1" ]; then
    echo y
    return
  fi
  local current
  eval "current=\${$key:-${MODULE_DEFAULT_VALUES[$key]:-0}}"
  if [ "$current" = "1" ]; then
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
      printf -v "$mod" '%s' "1"
    else
      say WARNING "Preset references unknown module $mod"
    fi
  done
}


show_wow_header() {
    if [ -t 1 ] && command -v clear >/dev/null 2>&1; then
        clear >/dev/null 2>&1 || true
    fi
    echo -e "${RED}"
    cat <<'EOF'

                       ##                                                                                                                      
                       ###                                        :*                                                                           
                      #####                                       .**#                                                                         
                      ######                                       ***##                                                                       
                     ****###*                                      *****##.                                                                    
                     ******##-                                     ******###.                                                                  
                    .*********###=                                 ********###                                                                 
                     ************#####           #****###:+*       ********####                                                                
                      ***********+****##########**********##**#    ********#####                                                               
                       ********=+***********######**********######*#**+*******###+                                                             
                       -+*****=**************#######*******####**#####**##*****####-                                                           
                        ++**++****************#########**####***####***#####****####:                                                          
                          :++*******************#*******####*****#****######***##*****#######                                                  
              *=             -++++++******************************###**********###******######                                                 
               .+***.          :++++++++***************************#+*#*-*******************#**+                                               
                 ++*****=        =+++=+++***************************+**###**************++*#####*                                              
                  -++*****+++-    -=++++++++*********+++++**###**+++=+*###**+*********##+++*+++##                                              
                    +++*********+++=-=+++++++++****+++***+++++*####***+++**=**#*==***#####*++***+*+                                            
                     +++++***********++=-=++++++++*++****=++*++*#######**+=-=+****+*#########***==+*#*                                         
                       =+++++++*****++++===-++++++++=+++++=++*+=-+#**#**=####****#**+-+**************##*                                       
                           ++++++++++++++======++++++++=====+++++=-+++*+##########*****==*######*****####                                      
                               +++++++=++++++====++++++++++========---++++*****#######**==***#*******####*                                     
                                  ++===++++++++=====+++++++=+++:::--:::.++++++*****####**+=**************#                                     
                     =+++++=:  =+=====-+++++++++++++++++++++==+++--==----:-++++++****####****+=+*+*******:                                     
                         ++++++++++++++++==+++++++++++++++++++++=+=-===-----:+++++++++**+++****####***+++                                      
                            =++++++++++++++++++++++++++++++++++++=++++======----==+++++++=+************:                                       
                                 :++++++++++++++=+++++++++++++++++++======-------:-====+****************.                                      
                                    =----=+++-==++++++*******++++++++++++++===============****************=                                    
                                    -=---==-=====--+++++++++++++++++++++++++++===+++++++********++#***#++******                                
                                  +++++========+=====----++++++++++++++++===+++++===--=**********+=++*++********                               
                               +++==========-=============-----:-=++=====+++++++++++++++=-=***********+*********                               
                                     ==----=+===+=================+++++++++++++++++++++++++=-********************                              
                                  .======++++++===============---:::::==++++++++++++++++++++++=**********++*******:                            
                               +++==--::-=+++++++++++++========+===--=+- :::=-=++++++++++++++++++++++ +*****++**+***                           
                                     .-----::::-=++++++++++++++++++==::-----++. :=+++++++++++++++++++*..-+*********=                           
                                                       :=+++++++++++++++++==.:--===-+++++++++++**++++++:::-********                            
                                                               ++++++++++++++++++=+++++++++++++**+++++*****==******                            
                                                                    .++++++++++++=-:.-+++++++++***++++************+                            
                                                                         +++=========:.=+=-::++*****+*************                             
                                                                            -++++++++==+: ..::=-.  ..::::=********                             
                                                                               .+========+==+++==========---::-+*-                             
                                                                                  ++++++++++++=======-======                                   
                                                                                    ++++++++++++++======++                                     
                                                                                         -=======++++++:                                       
                                                                                                ...                         
    :::.     :::::::::.,:::::: :::::::..       ...   :::::::::::: ::   .:    .,-:::::     ...    :::::::..  .,::::::
    ;;`;;    '`````;;;;;;;'''' ;;;;``;;;;   .;;;;;;;.;;;;;;;;'''',;;   ;;, ,;;;'````'  .;;;;;;;. ;;;;``;;;; ;;;;''''
   ,[[ '[[,      .n[[' [[cccc   [[[,/[[['  ,[[     \[[,   [[    ,[[[,,,[[[ [[[        ,[[     \[[,[[[,/[[['  [[cccc
  c$$$cc$$$c   ,$$P"   $$""""   $$$$$$c    $$$,     $$$   $$    "$$$"""$$$ $$$        $$$,     $$$$$$$$$c    $$""""
   888   888,,888bo,_  888oo,__ 888b "88bo,"888,_ _,88P   88,    888   "88o`88bo,__,o,"888,_ _,88P888b "88bo,888oo,__
   YMM   ""`  `""*UMM  """"YUMMMMMMM   "W"   "YMMMMMP"    MMM    MMM    YMM  "YUMMMMMP" "YMMMMMP" MMMM   "W" """"\MMM		
EOF
    echo -e "${NC}"
}

# ==============================
# Module metadata / defaults
# ==============================

MODULE_MANIFEST_PATH="$SCRIPT_DIR/config/module-manifest.json"
MODULE_MANIFEST_HELPER="$SCRIPT_DIR/scripts/python/setup_manifest.py"
MODULE_PROFILES_HELPER="$SCRIPT_DIR/scripts/python/setup_profiles.py"
ENV_TEMPLATE_FILE="$SCRIPT_DIR/.env.template"

declare -a MODULE_KEYS=()
declare -a MODULE_KEYS_SORTED=()
declare -A MODULE_NAME_MAP=()
declare -A MODULE_TYPE_MAP=()
declare -A MODULE_STATUS_MAP=()
declare -A MODULE_BLOCK_REASON_MAP=()
declare -A MODULE_NEEDS_BUILD_MAP=()
declare -A MODULE_REQUIRES_MAP=()
declare -A MODULE_NOTES_MAP=()
declare -A MODULE_DESCRIPTION_MAP=()
declare -A MODULE_CATEGORY_MAP=()
declare -A MODULE_SPECIAL_MESSAGE_MAP=()
declare -A MODULE_REPO_MAP=()
declare -A MODULE_DEFAULT_VALUES=()
declare -A KNOWN_MODULE_LOOKUP=()
declare -A ENV_TEMPLATE_VALUES=()
MODULE_METADATA_INITIALIZED=0

load_env_template_values() {
  local template_file="$ENV_TEMPLATE_FILE"
  if [ ! -f "$template_file" ]; then
    echo "ERROR: .env.template file not found at $template_file" >&2
    exit 1
  fi

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    local line="${raw_line%%#*}"
    line="${line%%$'\r'}"
    line="$(echo "$line" | sed 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    [[ "$line" == *=* ]] || continue
    local key="${line%%=*}"
    local value="${line#*=}"
    key="$(echo "$key" | sed 's/[[:space:]]//g')"
    value="$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$key" ] || continue
    ENV_TEMPLATE_VALUES["$key"]="$value"
  done < "$template_file"
}

load_module_manifest_metadata() {
  if [ ! -f "$MODULE_MANIFEST_PATH" ]; then
    echo "ERROR: Module manifest not found at $MODULE_MANIFEST_PATH" >&2
    exit 1
  fi
  if [ ! -x "$MODULE_MANIFEST_HELPER" ]; then
    echo "ERROR: Manifest helper not found or not executable at $MODULE_MANIFEST_HELPER" >&2
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to read $MODULE_MANIFEST_PATH" >&2
    exit 1
  fi

  mapfile -t MODULE_KEYS < <(
    python3 "$MODULE_MANIFEST_HELPER" keys "$MODULE_MANIFEST_PATH"
  )

  if [ ${#MODULE_KEYS[@]} -eq 0 ]; then
    echo "ERROR: No modules defined in manifest $MODULE_MANIFEST_PATH" >&2
    exit 1
  fi

  while IFS=$'\t' read -r key name needs_build module_type status block_reason requires notes description category special_message repo; do
    [ -n "$key" ] || continue
    # Convert placeholder back to empty string
    [ "$block_reason" = "-" ] && block_reason=""
    [ "$requires" = "-" ] && requires=""
    [ "$notes" = "-" ] && notes=""
    [ "$description" = "-" ] && description=""
    [ "$category" = "-" ] && category=""
    [ "$special_message" = "-" ] && special_message=""
    [ "$repo" = "-" ] && repo=""
    MODULE_NAME_MAP["$key"]="$name"
    MODULE_NEEDS_BUILD_MAP["$key"]="$needs_build"
    MODULE_TYPE_MAP["$key"]="$module_type"
    MODULE_STATUS_MAP["$key"]="$status"
    MODULE_BLOCK_REASON_MAP["$key"]="$block_reason"
    MODULE_REQUIRES_MAP["$key"]="$requires"
    MODULE_NOTES_MAP["$key"]="$notes"
    MODULE_DESCRIPTION_MAP["$key"]="$description"
    MODULE_CATEGORY_MAP["$key"]="$category"
    MODULE_SPECIAL_MESSAGE_MAP["$key"]="$special_message"
    MODULE_REPO_MAP["$key"]="$repo"
    KNOWN_MODULE_LOOKUP["$key"]=1
  done < <(python3 "$MODULE_MANIFEST_HELPER" metadata "$MODULE_MANIFEST_PATH")

  mapfile -t MODULE_KEYS_SORTED < <(
    python3 "$MODULE_MANIFEST_HELPER" sorted-keys "$MODULE_MANIFEST_PATH"
  )
}

initialize_module_defaults() {
  if [ "$MODULE_METADATA_INITIALIZED" = "1" ]; then
    return
  fi
  load_env_template_values
  load_module_manifest_metadata

  for key in "${MODULE_KEYS[@]}"; do
    if [ -z "${ENV_TEMPLATE_VALUES[$key]+_}" ]; then
      echo "ERROR: .env.template missing default value for ${key}" >&2
      exit 1
    fi
    local default="${ENV_TEMPLATE_VALUES[$key]}"
    MODULE_DEFAULT_VALUES["$key"]="$default"
    printf -v "$key" '%s' "$default"
  done
  MODULE_METADATA_INITIALIZED=1
}

reset_modules_to_defaults() {
  for key in "${MODULE_KEYS[@]}"; do
    printf -v "$key" '%s' "${MODULE_DEFAULT_VALUES[$key]}"
  done
}

module_display_name() {
  local key="$1"
  local name="${MODULE_NAME_MAP[$key]:-$key}"
  local note="${MODULE_NOTES_MAP[$key]}"
  if [ -n "$note" ]; then
    echo "${name} - ${note}"
  else
    echo "$name"
  fi
}

auto_enable_module_dependencies() {
  local changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    for key in "${MODULE_KEYS[@]}"; do
      local enabled
      eval "enabled=\${$key:-0}"
      [ "$enabled" = "1" ] || continue
      local requires_csv="${MODULE_REQUIRES_MAP[$key]}"
      IFS=',' read -r -a deps <<< "${requires_csv}"
      for dep in "${deps[@]}"; do
        dep="${dep//[[:space:]]/}"
        [ -n "$dep" ] || continue
        [ -n "${KNOWN_MODULE_LOOKUP[$dep]:-}" ] || continue
        local dep_value
        eval "dep_value=\${$dep:-0}"
        if [ "$dep_value" != "1" ]; then
          say INFO "Automatically enabling ${dep#MODULE_} (required by ${key#MODULE_})."
          printf -v "$dep" '%s' "1"
          MODULE_ENABLE_SET["$dep"]=1
          changed=1
        fi
      done
    done
  done
}

ensure_module_platforms() {
  local needs_platform=0
  local key
  for key in "${MODULE_KEYS[@]}"; do
    case "$key" in
      MODULE_ELUNA|MODULE_AIO) continue ;;
    esac
    local value
    eval "value=\${$key:-0}"
    if [ "$value" = "1" ]; then
      needs_platform=1
      break
    fi
  done
  if [ "$needs_platform" != "1" ]; then
    return 0
  fi

  local platform
  for platform in MODULE_ELUNA MODULE_AIO; do
    [ -n "${KNOWN_MODULE_LOOKUP[$platform]:-}" ] || continue
    local platform_value
    eval "platform_value=\${$platform:-0}"
    if [ "$platform_value" != "1" ]; then
      local platform_name="${MODULE_NAME_MAP[$platform]:-${platform#MODULE_}}"
      say INFO "Automatically enabling ${platform_name} to support selected modules."
      printf -v "$platform" '%s' "1"
      MODULE_ENABLE_SET["$platform"]=1
    fi
  done
  return 0
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
  local CLI_PLAYERBOT_MIN=""
  local CLI_PLAYERBOT_MAX=""
  local FORCE_OVERWRITE=0
  local CLI_ENABLE_MODULES_RAW=()

  initialize_module_defaults
  reset_modules_to_defaults

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cat <<'EOF'
Usage: ./setup.sh [options]

Description:
  Interactive wizard that generates .env for the
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
  --module-config NAME            Use preset NAME from config/module-profiles/<NAME>.json
  --server-config NAME            Use server preset NAME from config/presets/<NAME>.conf
  --enable-modules LIST           Comma-separated module list (MODULE_* or shorthand)
  --playerbot-enabled 0|1         Override PLAYERBOT_ENABLED flag
    --playerbot-min-bots N          Override PLAYERBOT_MIN_BOTS value
    --playerbot-max-bots N          Override PLAYERBOT_MAX_BOTS value
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
      --server-config)
        [[ $# -ge 2 ]] || { say ERROR "--server-config requires a value"; exit 1; }
        CLI_CONFIG_PRESET="$2"; shift 2
        ;;
      --server-config=*)
        CLI_CONFIG_PRESET="${1#*=}"; shift
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
      --playerbot-min-bots)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-min-bots requires a value"; exit 1; }
        CLI_PLAYERBOT_MIN="$2"; shift 2
        ;;
      --playerbot-min-bots=*)
        CLI_PLAYERBOT_MIN="${1#*=}"; shift
        ;;
      --playerbot-max-bots)
        CLI_PLAYERBOT_MAX="$2"; shift 2
        ;;
      --playerbot-max-bots=*)
        CLI_PLAYERBOT_MAX="${1#*=}"; shift
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
  say INFO "This will create .env for compose profiles."

  # Deployment type
  say HEADER "DEPLOYMENT TYPE"
  echo "1) 🏠 Local Development (127.0.0.1)"
  echo "2) 🌐 LAN Server (local network IP) (autodetect)"
  echo "3) ☁️ Public Server (domain or public IP) (manual)"
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
    SERVER_ADDRESS=$DEFAULT_LOCAL_ADDRESS
  elif [ "$DEPLOYMENT_TYPE" = "lan" ]; then
    local LAN_IP
    LAN_IP=$(ip route get $ROUTE_DETECTION_IP 2>/dev/null | awk 'NR==1{print $7}')
    SERVER_ADDRESS=$(ask "Enter server IP address" "${CLI_SERVER_ADDRESS:-${LAN_IP:-$DEFAULT_FALLBACK_LAN_IP}}" validate_ip)
  else
    SERVER_ADDRESS=$(ask "Enter server address (IP or domain)" "${CLI_SERVER_ADDRESS:-$DEFAULT_DOMAIN_PLACEHOLDER}" )
  fi

  local REALM_PORT AUTH_EXTERNAL_PORT SOAP_EXTERNAL_PORT MYSQL_EXTERNAL_PORT
  REALM_PORT=$(ask "Enter client connection port" "${CLI_REALM_PORT:-$DEFAULT_REALM_PORT}" validate_port)
  AUTH_EXTERNAL_PORT=$(ask "Enter auth server port" "${CLI_AUTH_PORT:-$DEFAULT_AUTH_PORT}" validate_port)
  SOAP_EXTERNAL_PORT=$(ask "Enter SOAP API port" "${CLI_SOAP_PORT:-$DEFAULT_SOAP_PORT}" validate_port)
  MYSQL_EXTERNAL_PORT=$(ask "Enter MySQL external port" "${CLI_MYSQL_PORT:-$DEFAULT_MYSQL_PORT}" validate_port)

  # Permission scheme
  say HEADER "PERMISSION SCHEME"
  local CURRENT_UID CURRENT_GID CURRENT_USER_PAIR CURRENT_USER_NAME CURRENT_GROUP_NAME
  CURRENT_UID="$(id -u 2>/dev/null || echo 1000)"
  CURRENT_GID="$(id -g 2>/dev/null || echo 1000)"
  CURRENT_USER_NAME="$(id -un 2>/dev/null || echo user)"
  CURRENT_GROUP_NAME="$(id -gn 2>/dev/null || echo users)"
  CURRENT_USER_PAIR="${CURRENT_UID}:${CURRENT_GID}"
  echo "1) 🏠 Local Root (0:0)"
  echo "2) 🗂️ Current User (${CURRENT_USER_NAME}:${CURRENT_GROUP_NAME} → ${CURRENT_USER_PAIR})"
  echo "3) ⚙️ Custom"
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
  # DB config
  say HEADER "DATABASE CONFIGURATION"
  local MYSQL_ROOT_PASSWORD; MYSQL_ROOT_PASSWORD=$(ask "Enter MySQL root password" "${CLI_MYSQL_PASSWORD:-$DEFAULT_MYSQL_PASSWORD}")

  # Storage
  say HEADER "STORAGE CONFIGURATION"
  local STORAGE_PATH
  if [ -n "$CLI_STORAGE_PATH" ]; then
    STORAGE_PATH="$CLI_STORAGE_PATH"
  elif [ "$NON_INTERACTIVE" = "1" ]; then
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
      STORAGE_PATH=$DEFAULT_LOCAL_STORAGE
    else
      STORAGE_PATH=$DEFAULT_MOUNT_STORAGE
    fi
  else
    echo "1) 💾 ./storage (local)"
    echo "2) 🌐 /nfs/azerothcore (NFS)"
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

  # Backup
  say HEADER "BACKUP CONFIGURATION"
  local BACKUP_RETENTION_DAYS BACKUP_RETENTION_HOURS BACKUP_DAILY_TIME
  BACKUP_RETENTION_DAYS=$(ask "Daily backups retention (days)" "${CLI_BACKUP_DAYS:-$DEFAULT_BACKUP_DAYS}" validate_number)
  BACKUP_RETENTION_HOURS=$(ask "Hourly backups retention (hours)" "${CLI_BACKUP_HOURS:-$DEFAULT_BACKUP_HOURS}" validate_number)
  BACKUP_DAILY_TIME=$(ask "Daily backup hour (00-23, UTC)" "${CLI_BACKUP_TIME:-$DEFAULT_BACKUP_TIME}" validate_number)

  # Server configuration
  local SERVER_CONFIG_PRESET

  if [ "$ENABLE_CONFIG_PRESETS" = "1" ]; then
    say HEADER "SERVER CONFIGURATION PRESET"

    if [ -n "$CLI_CONFIG_PRESET" ]; then
      SERVER_CONFIG_PRESET="$CLI_CONFIG_PRESET"
      say INFO "Using preset from command line: $SERVER_CONFIG_PRESET"
    else
      declare -A CONFIG_PRESET_NAMES=()
      declare -A CONFIG_PRESET_DESCRIPTIONS=()
      declare -A CONFIG_MENU_INDEX=()
      local config_dir="$SCRIPT_DIR/config/presets"
      local menu_index=1

      echo "Choose a server configuration preset:"

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
      else
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
      fi
    fi
  else
    # Config presets disabled - use default
    SERVER_CONFIG_PRESET="none"
    say INFO "Server configuration presets disabled - using default settings"
  fi

  local MODE_SELECTION=""
  local MODE_PRESET_NAME=""
  declare -A MODULE_PRESET_CONFIGS=()
  declare -A MODULE_PRESET_LABELS=()
  declare -A MODULE_PRESET_DESCRIPTIONS=()
  declare -A MODULE_PRESET_ORDER=()
  local CONFIG_DIR="$SCRIPT_DIR/config/module-profiles"
  if [ ! -x "$MODULE_PROFILES_HELPER" ]; then
    say ERROR "Profile helper not found or not executable at $MODULE_PROFILES_HELPER"
    exit 1
  fi
  if [ -d "$CONFIG_DIR" ]; then
    while IFS=$'\t' read -r preset_name preset_modules preset_label preset_desc preset_order; do
      [ -n "$preset_name" ] || continue
      MODULE_PRESET_CONFIGS["$preset_name"]="$preset_modules"
      MODULE_PRESET_LABELS["$preset_name"]="$preset_label"
      MODULE_PRESET_DESCRIPTIONS["$preset_name"]="$preset_desc"
      MODULE_PRESET_ORDER["$preset_name"]="${preset_order:-10000}"
    done < <(python3 "$MODULE_PROFILES_HELPER" list "$CONFIG_DIR")
  fi

  local missing_presets=0
  for required_preset in "$DEFAULT_PRESET_SUGGESTED" "$DEFAULT_PRESET_PLAYERBOTS"; do
    if [ -z "${MODULE_PRESET_CONFIGS[$required_preset]:-}" ]; then
      say ERROR "Missing module preset config/module-profiles/${required_preset}.json"
      missing_presets=1
    fi
  done
  if [ "$missing_presets" -eq 1 ]; then
    exit 1
  fi

  if [ -n "$CLI_MODULE_PRESET" ]; then
    if [ -n "${MODULE_PRESET_CONFIGS[$CLI_MODULE_PRESET]:-}" ]; then
      MODE_SELECTION="preset"
      MODE_PRESET_NAME="$CLI_MODULE_PRESET"
    else
      say ERROR "Unknown module preset: $CLI_MODULE_PRESET"
      exit 1
    fi
  fi

  if [ -n "$MODE_SELECTION" ] && [ "$MODE_SELECTION" != "preset" ]; then
    MODE_PRESET_NAME=""
  fi

  if [ -n "$CLI_MODULE_MODE" ]; then
    case "${CLI_MODULE_MODE,,}" in
      1|suggested) MODE_SELECTION=1 ;;
      2|playerbots) MODE_SELECTION=2 ;;
      3|manual) MODE_SELECTION=3 ;;
      4|none) MODE_SELECTION=4 ;;
      *) say ERROR "Invalid module mode: ${CLI_MODULE_MODE}"; exit 1 ;;
    esac
    if [ "$MODE_SELECTION" = "1" ]; then
      MODE_PRESET_NAME="$DEFAULT_PRESET_SUGGESTED"
    elif [ "$MODE_SELECTION" = "2" ]; then
      MODE_PRESET_NAME="$DEFAULT_PRESET_PLAYERBOTS"
    fi
  fi

  if [ -z "$MODE_SELECTION" ] && [ ${#MODULE_ENABLE_SET[@]} -gt 0 ]; then
    MODE_SELECTION=3
  fi
  if [ ${#MODULE_ENABLE_SET[@]} -gt 0 ] && [ -n "$MODE_SELECTION" ] && [ "$MODE_SELECTION" != "3" ] && [ "$MODE_SELECTION" != "4" ]; then
    say INFO "Switching module preset to manual to honor --enable-modules list."
    MODE_SELECTION=3
  fi
  if [ "$MODE_SELECTION" = "4" ] && [ ${#MODULE_ENABLE_SET[@]} -gt 0 ]; then
    say ERROR "--enable-modules cannot be used together with module-mode=none."
    exit 1
  fi

  if [ "$MODE_SELECTION" = "preset" ] && [ -n "$CLI_MODULE_PRESET" ]; then
    MODE_PRESET_NAME="$CLI_MODULE_PRESET"
  fi

  # Function to determine source branch for a preset
  get_preset_source_branch() {
    local preset_name="$1"
    local preset_modules="${MODULE_PRESET_CONFIGS[$preset_name]:-}"

    # Check if playerbots module is in the preset
    if [[ "$preset_modules" == *"MODULE_PLAYERBOTS"* ]]; then
      echo "azerothcore-playerbots"
    else
      echo "azerothcore-wotlk"
    fi
  }

  # Module config
  say HEADER "MODULE PRESET"
  printf " %s) %s\n" "1" "⭐ Suggested Modules"
  printf "    %s (%s)\n" "Baseline solo-friendly quality of life mix" "azerothcore-wotlk"
  printf " %s) %s\n" "2" "🤖 Playerbots + Suggested modules"
  printf "    %s (%s)\n" "Suggested stack plus playerbots enabled" "azerothcore-playerbots"
  printf " %s) %s\n" "3" "⚙️ Manual selection"
  printf "    %s (%s)\n" "Choose individual modules manually" "(depends on modules)"
  printf " %s) %s\n" "4" "🚫 No modules"
  printf "    %s (%s)\n" "Pure AzerothCore with no modules" "azerothcore-wotlk"

  local menu_index=5
  declare -A MENU_PRESET_INDEX=()
  local -a ORDERED_PRESETS=()
  for preset_name in "${!MODULE_PRESET_CONFIGS[@]}"; do
    if [ "$preset_name" = "$DEFAULT_PRESET_SUGGESTED" ] || [ "$preset_name" = "$DEFAULT_PRESET_PLAYERBOTS" ]; then
      continue
    fi
    local order="${MODULE_PRESET_ORDER[$preset_name]:-10000}"
    ORDERED_PRESETS+=("$(printf '%05d::%s' "$order" "$preset_name")")
  done
  if [ ${#ORDERED_PRESETS[@]} -gt 0 ]; then
    IFS=$'\n' ORDERED_PRESETS=($(printf '%s\n' "${ORDERED_PRESETS[@]}" | sort))
  fi

  for entry in "${ORDERED_PRESETS[@]}"; do
    local preset_name="${entry#*::}"
    [ -n "${MODULE_PRESET_CONFIGS[$preset_name]:-}" ] || continue
    local pretty_name preset_desc
    if [ -n "${MODULE_PRESET_LABELS[$preset_name]:-}" ]; then
      pretty_name="${MODULE_PRESET_LABELS[$preset_name]}"
    else
      pretty_name=$(echo "$preset_name" | tr '_-' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')
    fi
    preset_desc="${MODULE_PRESET_DESCRIPTIONS[$preset_name]:-No description available}"
    local source_branch=$(get_preset_source_branch "$preset_name")
    printf " %s) %s\n" "$menu_index" "$pretty_name"
    printf "    %s (%s)\n" "$preset_desc" "$source_branch"
    MENU_PRESET_INDEX[$menu_index]="$preset_name"
    menu_index=$((menu_index + 1))
  done
  local max_option=$((menu_index - 1))

  if [ "$NON_INTERACTIVE" = "1" ] && [ -z "$MODE_SELECTION" ]; then
    MODE_SELECTION=1
  fi

  if [ -z "$MODE_SELECTION" ]; then
    local selection_input
    while true; do
      read -p "$(echo -e "${YELLOW}🔧 Select module configuration [1-${max_option}]: ${NC}")" selection_input
      if [[ "$selection_input" =~ ^[0-9]+$ ]] && [ "$selection_input" -ge 1 ] && [ "$selection_input" -le "$max_option" ]; then
        if [ -n "${MENU_PRESET_INDEX[$selection_input]:-}" ]; then
          MODE_SELECTION="preset"
          MODE_PRESET_NAME="${MENU_PRESET_INDEX[$selection_input]}"
        else
          MODE_SELECTION="$selection_input"
        fi
        break
      fi
      say ERROR "Please select a number between 1 and ${max_option}"
    done
  else
    if [ "$MODE_SELECTION" = "preset" ]; then
      say INFO "Module preset set to ${MODE_PRESET_NAME}."
    else
      say INFO "Module preset set to ${MODE_SELECTION}."
    fi
  fi


  local AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_AUTH_IMAGE_PLAYERBOTS"
  local AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_WORLD_IMAGE_PLAYERBOTS"
  local AC_AUTHSERVER_IMAGE_MODULES_VALUE="$DEFAULT_AUTH_IMAGE_MODULES"
  local AC_WORLDSERVER_IMAGE_MODULES_VALUE="$DEFAULT_WORLD_IMAGE_MODULES"
  local AC_CLIENT_DATA_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_CLIENT_DATA_IMAGE_PLAYERBOTS"
  local AC_DB_IMPORT_IMAGE_VALUE="$DEFAULT_AC_DB_IMPORT_IMAGE"

  local mod_var
  for mod_var in "${!MODULE_ENABLE_SET[@]}"; do
    if [ -n "${KNOWN_MODULE_LOOKUP[$mod_var]:-}" ]; then
      printf -v "$mod_var" '%s' "1"
    fi
  done

  auto_enable_module_dependencies
  ensure_module_platforms

  if [ "${MODULE_OLLAMA_CHAT:-0}" = "1" ] && [ "${MODULE_PLAYERBOTS:-0}" != "1" ]; then
    say INFO "Automatically enabling MODULE_PLAYERBOTS for MODULE_OLLAMA_CHAT."
    MODULE_PLAYERBOTS=1
    MODULE_ENABLE_SET["MODULE_PLAYERBOTS"]=1
  fi

  declare -A DISABLED_MODULE_REASONS=(
    [MODULE_AHBOT]="Requires upstream Addmod_ahbotScripts symbol (fails link)"
    [MODULE_LEVEL_GRANT]="QuestCountLevel module relies on removed ConfigMgr APIs and fails to build"
  )

  local PLAYERBOT_ENABLED=0
  local PLAYERBOT_MIN_BOTS="${DEFAULT_PLAYERBOT_MIN:-40}"
  local PLAYERBOT_MAX_BOTS="${DEFAULT_PLAYERBOT_MAX:-40}"

  local NEEDS_CXX_REBUILD=0

  local module_mode_label=""
  if [ "$MODE_SELECTION" = "1" ]; then
    MODE_PRESET_NAME="$DEFAULT_PRESET_SUGGESTED"
    apply_module_preset "${MODULE_PRESET_CONFIGS[$DEFAULT_PRESET_SUGGESTED]}"
    local preset_label="${MODULE_PRESET_LABELS[$DEFAULT_PRESET_SUGGESTED]:-Suggested Modules}"
    module_mode_label="preset 1 (${preset_label})"
  elif [ "$MODE_SELECTION" = "2" ]; then
    MODE_PRESET_NAME="$DEFAULT_PRESET_PLAYERBOTS"
    apply_module_preset "${MODULE_PRESET_CONFIGS[$DEFAULT_PRESET_PLAYERBOTS]}"
    local preset_label="${MODULE_PRESET_LABELS[$DEFAULT_PRESET_PLAYERBOTS]:-Playerbots + Suggested}"
    module_mode_label="preset 2 (${preset_label})"
  elif [ "$MODE_SELECTION" = "3" ]; then
    MODE_PRESET_NAME=""
    say INFO "Answer y/n for each module (organized by category)"
    for key in "${!DISABLED_MODULE_REASONS[@]}"; do
      say WARNING "${key#MODULE_}: ${DISABLED_MODULE_REASONS[$key]}"
    done
    local -a selection_keys=("${MODULE_KEYS_SORTED[@]}")
    if [ ${#selection_keys[@]} -eq 0 ]; then
      selection_keys=("${MODULE_KEYS[@]}")
    fi

    # Define category display order and titles
    local -a category_order=(
      "automation" "quality-of-life" "gameplay-enhancement" "npc-service"
      "pvp" "progression" "economy" "social" "account-wide"
      "customization" "scripting" "admin" "premium" "minigame"
      "content" "rewards" "developer" "database" "tooling" "uncategorized"
    )
    declare -A category_titles=(
      ["automation"]="🤖 Automation"
      ["quality-of-life"]="✨ Quality of Life"
      ["gameplay-enhancement"]="⚔️ Gameplay Enhancement"
      ["npc-service"]="🏪 NPC Services"
      ["pvp"]="⚡ PvP"
      ["progression"]="📈 Progression"
      ["economy"]="💰 Economy"
      ["social"]="👥 Social"
      ["account-wide"]="👤 Account-Wide"
      ["customization"]="🎨 Customization"
      ["scripting"]="📜 Scripting"
      ["admin"]="🔧 Admin Tools"
      ["premium"]="💎 Premium/VIP"
      ["minigame"]="🎮 Mini-Games"
      ["content"]="🏰 Content"
      ["rewards"]="🎁 Rewards"
      ["developer"]="🛠️ Developer Tools"
      ["database"]="🗄️ Database"
      ["tooling"]="🔨 Tooling"
      ["uncategorized"]="📦 Miscellaneous"
    )
    declare -A processed_categories=()

    render_category() {
      local cat="$1"
      local module_list="${modules_by_category[$cat]:-}"
      [ -n "$module_list" ] || return 0

      local has_valid_modules=0
      local -a module_array
      IFS=' ' read -ra module_array <<< "$module_list"
      for key in "${module_array[@]}"; do
        [ -n "${KNOWN_MODULE_LOOKUP[$key]:-}" ] || continue
        local status_lc="${MODULE_STATUS_MAP[$key],,}"
        if [ -z "$status_lc" ] || [ "$status_lc" = "active" ]; then
          has_valid_modules=1
          break
        fi
      done

      [ "$has_valid_modules" = "1" ] || return 0

      local cat_title="${category_titles[$cat]:-$cat}"
      printf '\n%b\n' "${BOLD}${CYAN}═══ ${cat_title} ═══${NC}"

      local first_in_cat=1
      for key in "${module_array[@]}"; do
        [ -n "${KNOWN_MODULE_LOOKUP[$key]:-}" ] || continue
        local status_lc="${MODULE_STATUS_MAP[$key],,}"
        if [ -n "$status_lc" ] && [ "$status_lc" != "active" ]; then
          local reason="${MODULE_BLOCK_REASON_MAP[$key]:-Blocked in manifest}"
          say WARNING "${key#MODULE_} is blocked: ${reason}"
          printf -v "$key" '%s' "0"
          continue
        fi
        if [ "$first_in_cat" -ne 1 ]; then
          printf '\n'
        fi
        first_in_cat=0
        local prompt_label
        prompt_label="$(module_display_name "$key")"
        if [ "${MODULE_NEEDS_BUILD_MAP[$key]}" = "1" ]; then
          prompt_label="${prompt_label} (requires build)"
        fi
        local description="${MODULE_DESCRIPTION_MAP[$key]:-}"
        if [ -n "$description" ]; then
          printf '%b\n' "${BLUE}ℹ️  ${MODULE_NAME_MAP[$key]:-$key}: ${description}${NC}"
        fi
        local special_message="${MODULE_SPECIAL_MESSAGE_MAP[$key]:-}"
        if [ -n "$special_message" ]; then
          printf '%b\n' "${MAGENTA}💡 ${special_message}${NC}"
        fi
        local repo="${MODULE_REPO_MAP[$key]:-}"
        if [ -n "$repo" ]; then
          printf '%b\n' "${GREEN}🔗 ${repo}${NC}"
        fi
        local default_answer
        default_answer="$(module_default "$key")"
        local response
        response=$(ask_yn "$prompt_label" "$default_answer")
        if [ "$response" = "1" ]; then
          printf -v "$key" '%s' "1"
        else
          printf -v "$key" '%s' "0"
        fi
      done
      processed_categories["$cat"]=1
    }

    # Group modules by category using arrays
    declare -A modules_by_category
    local key
    for key in "${selection_keys[@]}"; do
      [ -n "${KNOWN_MODULE_LOOKUP[$key]:-}" ] || continue
      local category="${MODULE_CATEGORY_MAP[$key]:-uncategorized}"
      if [ -z "${modules_by_category[$category]:-}" ]; then
        modules_by_category[$category]="$key"
      else
        modules_by_category[$category]="${modules_by_category[$category]} $key"
      fi
    done

    # Process modules by category (ordered, then any new categories)
    local cat
    for cat in "${category_order[@]}"; do
      render_category "$cat"
    done
    for cat in "${!modules_by_category[@]}"; do
      [ -n "${processed_categories[$cat]:-}" ] && continue
      render_category "$cat"
    done
    module_mode_label="preset 3 (Manual)"
  elif [ "$MODE_SELECTION" = "4" ]; then
    for key in "${MODULE_KEYS[@]}"; do
      printf -v "$key" '%s' "0"
    done
    module_mode_label="preset 4 (No modules)"
  elif [ "$MODE_SELECTION" = "preset" ]; then
    local preset_modules="${MODULE_PRESET_CONFIGS[$MODE_PRESET_NAME]}"
    if [ -n "$preset_modules" ]; then
      apply_module_preset "$preset_modules"
      say INFO "Applied preset '${MODE_PRESET_NAME}'."
    else
      say WARNING "Preset '${MODE_PRESET_NAME}' did not contain any module selections."
    fi
    local preset_label="${MODULE_PRESET_LABELS[$MODE_PRESET_NAME]:-$MODE_PRESET_NAME}"
    module_mode_label="preset (${preset_label})"
  fi

  auto_enable_module_dependencies
  ensure_module_platforms

  if [ -n "$CLI_PLAYERBOT_ENABLED" ]; then
    if [[ "$CLI_PLAYERBOT_ENABLED" != "0" && "$CLI_PLAYERBOT_ENABLED" != "1" ]]; then
      say ERROR "--playerbot-enabled must be 0 or 1"
      exit 1
    fi
    PLAYERBOT_ENABLED="$CLI_PLAYERBOT_ENABLED"
  fi
  if [ -n "$CLI_PLAYERBOT_MIN" ]; then
    if ! [[ "$CLI_PLAYERBOT_MIN" =~ ^[0-9]+$ ]]; then
      say ERROR "--playerbot-min-bots must be numeric"
      exit 1
    fi
    PLAYERBOT_MIN_BOTS="$CLI_PLAYERBOT_MIN"
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
    PLAYERBOT_MIN_BOTS=$(ask "Minimum concurrent playerbots" "${CLI_PLAYERBOT_MIN:-$DEFAULT_PLAYERBOT_MIN}" validate_number)
    PLAYERBOT_MAX_BOTS=$(ask "Maximum concurrent playerbots" "${CLI_PLAYERBOT_MAX:-$DEFAULT_PLAYERBOT_MAX}" validate_number)
  fi

  if [ -n "$PLAYERBOT_MIN_BOTS" ] && [ -n "$PLAYERBOT_MAX_BOTS" ]; then
    if [ "$PLAYERBOT_MAX_BOTS" -lt "$PLAYERBOT_MIN_BOTS" ]; then
      say WARNING "Playerbot max bots ($PLAYERBOT_MAX_BOTS) lower than min ($PLAYERBOT_MIN_BOTS); adjusting max to match min."
      PLAYERBOT_MAX_BOTS="$PLAYERBOT_MIN_BOTS"
    fi
  fi

  for mod_var in "${MODULE_KEYS[@]}"; do
    if [ "${MODULE_NEEDS_BUILD_MAP[$mod_var]}" = "1" ]; then
      eval "value=\${$mod_var:-0}"
      if [ "$value" = "1" ]; then
        NEEDS_CXX_REBUILD=1
        break
      fi
    fi
  done

  local enabled_module_keys=()
  local enabled_cpp_module_keys=()
  for mod_var in "${MODULE_KEYS[@]}"; do
    eval "value=\${$mod_var:-0}"
    if [ "$value" = "1" ]; then
      enabled_module_keys+=("$mod_var")
      if [ "${MODULE_NEEDS_BUILD_MAP[$mod_var]}" = "1" ]; then
        enabled_cpp_module_keys+=("$mod_var")
      fi
    fi
  done

  local MODULES_ENABLED_LIST=""
  local MODULES_CPP_LIST=""
  if [ ${#enabled_module_keys[@]} -gt 0 ]; then
    MODULES_ENABLED_LIST="$(IFS=','; printf '%s' "${enabled_module_keys[*]}")"
  fi
  if [ ${#enabled_cpp_module_keys[@]} -gt 0 ]; then
    MODULES_CPP_LIST="$(IFS=','; printf '%s' "${enabled_cpp_module_keys[*]}")"
  fi

  # Determine source variant based ONLY on playerbots module
  local STACK_SOURCE_VARIANT="core"
  if [ "$MODULE_PLAYERBOTS" = "1" ] || [ "$PLAYERBOT_ENABLED" = "1" ]; then
    STACK_SOURCE_VARIANT="playerbots"
  fi

  # Determine image mode based on source variant and build requirements
  local STACK_IMAGE_MODE="standard"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    STACK_IMAGE_MODE="playerbots"
  elif [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    STACK_IMAGE_MODE="modules"
  fi

  local MODULES_REQUIRES_CUSTOM_BUILD="$NEEDS_CXX_REBUILD"
  local MODULES_REQUIRES_PLAYERBOT_SOURCE="0"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    MODULES_REQUIRES_PLAYERBOT_SOURCE="1"
  fi

  export NEEDS_CXX_REBUILD

  local SUMMARY_MODE_TEXT="$module_mode_label"
  if [ -z "$SUMMARY_MODE_TEXT" ]; then
    SUMMARY_MODE_TEXT="$MODE_SELECTION"
  fi

  # Summary
  say HEADER "SUMMARY"
  printf "  %-18s %s\n" "Server Address:" "$SERVER_ADDRESS"
  printf "  %-18s Realm:%s  Auth:%s  SOAP:%s  MySQL:%s\n" "Ports:" "$REALM_PORT" "$AUTH_EXTERNAL_PORT" "$SOAP_EXTERNAL_PORT" "$MYSQL_EXTERNAL_PORT"
  printf "  %-18s %s\n" "Storage Path:" "$STORAGE_PATH"
  printf "  %-18s %s\n" "Container User:" "$CONTAINER_USER"
  printf "  %-18s Daily %s:00 UTC, keep %sd/%sh\n" "Backups:" "$BACKUP_DAILY_TIME" "$BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_HOURS"
  printf "  %-18s %s\n" "Modules images:" "$AC_AUTHSERVER_IMAGE_MODULES_VALUE | $AC_WORLDSERVER_IMAGE_MODULES_VALUE"

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

  local LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-./local-storage}"
  LOCAL_STORAGE_ROOT="${LOCAL_STORAGE_ROOT%/}"
  [ -z "$LOCAL_STORAGE_ROOT" ] && LOCAL_STORAGE_ROOT="."
  local LOCAL_STORAGE_ROOT_ABS="$LOCAL_STORAGE_ROOT"
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

  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    echo ""
    say WARNING "These modules require compiling AzerothCore from source."
    say INFO "Run './build.sh' to compile your custom modules before deployment."

    # Set build sentinel to indicate rebuild is needed
    local sentinel="$LOCAL_STORAGE_ROOT_ABS/modules/.requires_rebuild"
    mkdir -p "$(dirname "$sentinel")"
    if touch "$sentinel" 2>/dev/null; then
      say INFO "Build sentinel created at $sentinel"
    else
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
    fi
  fi

  local default_source_rel="${LOCAL_STORAGE_ROOT}/source/azerothcore"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    default_source_rel="${LOCAL_STORAGE_ROOT}/source/azerothcore-playerbots"
  fi

  # Persist rebuild source path for downstream build scripts
  MODULES_REBUILD_SOURCE_PATH="$default_source_rel"

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

  DB_PLAYERBOTS_NAME=${DB_PLAYERBOTS_NAME:-$DEFAULT_DB_PLAYERBOTS_NAME}
  HOST_ZONEINFO_PATH=${HOST_ZONEINFO_PATH:-$DEFAULT_HOST_ZONEINFO_PATH}
  MYSQL_INNODB_REDO_LOG_CAPACITY=${MYSQL_INNODB_REDO_LOG_CAPACITY:-$DEFAULT_MYSQL_INNODB_REDO_LOG_CAPACITY}
  MYSQL_RUNTIME_TMPFS_SIZE=${MYSQL_RUNTIME_TMPFS_SIZE:-$DEFAULT_MYSQL_RUNTIME_TMPFS_SIZE}
  COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED=${COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED:-$DEFAULT_COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED}
  COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED=${COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED:-$DEFAULT_COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED}
  MYSQL_DISABLE_BINLOG=${MYSQL_DISABLE_BINLOG:-$DEFAULT_MYSQL_DISABLE_BINLOG}
  MYSQL_CONFIG_DIR=${MYSQL_CONFIG_DIR:-$DEFAULT_MYSQL_CONFIG_DIR}
  CLIENT_DATA_PATH=${CLIENT_DATA_PATH:-$DEFAULT_CLIENT_DATA_PATH}
  BACKUP_HEALTHCHECK_MAX_MINUTES=${BACKUP_HEALTHCHECK_MAX_MINUTES:-$DEFAULT_BACKUP_HEALTHCHECK_MAX_MINUTES}
  BACKUP_HEALTHCHECK_GRACE_SECONDS=${BACKUP_HEALTHCHECK_GRACE_SECONDS:-$DEFAULT_BACKUP_HEALTHCHECK_GRACE_SECONDS}
  DB_WAIT_RETRIES=${DB_WAIT_RETRIES:-$DEFAULT_DB_WAIT_RETRIES}
  DB_WAIT_SLEEP=${DB_WAIT_SLEEP:-$DEFAULT_DB_WAIT_SLEEP}
  DB_RECONNECT_SECONDS=${DB_RECONNECT_SECONDS:-$DEFAULT_DB_RECONNECT_SECONDS}
  DB_RECONNECT_ATTEMPTS=${DB_RECONNECT_ATTEMPTS:-$DEFAULT_DB_RECONNECT_ATTEMPTS}
  DB_UPDATES_ALLOWED_MODULES=${DB_UPDATES_ALLOWED_MODULES:-$DEFAULT_DB_UPDATES_ALLOWED_MODULES}
  DB_UPDATES_REDUNDANCY=${DB_UPDATES_REDUNDANCY:-$DEFAULT_DB_UPDATES_REDUNDANCY}
  DB_LOGIN_WORKER_THREADS=${DB_LOGIN_WORKER_THREADS:-$DEFAULT_DB_LOGIN_WORKER_THREADS}
  DB_WORLD_WORKER_THREADS=${DB_WORLD_WORKER_THREADS:-$DEFAULT_DB_WORLD_WORKER_THREADS}
  DB_CHARACTER_WORKER_THREADS=${DB_CHARACTER_WORKER_THREADS:-$DEFAULT_DB_CHARACTER_WORKER_THREADS}
  DB_LOGIN_SYNCH_THREADS=${DB_LOGIN_SYNCH_THREADS:-$DEFAULT_DB_LOGIN_SYNCH_THREADS}
  DB_WORLD_SYNCH_THREADS=${DB_WORLD_SYNCH_THREADS:-$DEFAULT_DB_WORLD_SYNCH_THREADS}
  DB_CHARACTER_SYNCH_THREADS=${DB_CHARACTER_SYNCH_THREADS:-$DEFAULT_DB_CHARACTER_SYNCH_THREADS}
  MYSQL_HEALTHCHECK_INTERVAL=${MYSQL_HEALTHCHECK_INTERVAL:-$DEFAULT_MYSQL_HEALTHCHECK_INTERVAL}
  MYSQL_HEALTHCHECK_TIMEOUT=${MYSQL_HEALTHCHECK_TIMEOUT:-$DEFAULT_MYSQL_HEALTHCHECK_TIMEOUT}
  MYSQL_HEALTHCHECK_RETRIES=${MYSQL_HEALTHCHECK_RETRIES:-$DEFAULT_MYSQL_HEALTHCHECK_RETRIES}
  MYSQL_HEALTHCHECK_START_PERIOD=${MYSQL_HEALTHCHECK_START_PERIOD:-$DEFAULT_MYSQL_HEALTHCHECK_START_PERIOD}
  AUTH_HEALTHCHECK_INTERVAL=${AUTH_HEALTHCHECK_INTERVAL:-$DEFAULT_AUTH_HEALTHCHECK_INTERVAL}
  AUTH_HEALTHCHECK_TIMEOUT=${AUTH_HEALTHCHECK_TIMEOUT:-$DEFAULT_AUTH_HEALTHCHECK_TIMEOUT}
  AUTH_HEALTHCHECK_RETRIES=${AUTH_HEALTHCHECK_RETRIES:-$DEFAULT_AUTH_HEALTHCHECK_RETRIES}
  AUTH_HEALTHCHECK_START_PERIOD=${AUTH_HEALTHCHECK_START_PERIOD:-$DEFAULT_AUTH_HEALTHCHECK_START_PERIOD}
  WORLD_HEALTHCHECK_INTERVAL=${WORLD_HEALTHCHECK_INTERVAL:-$DEFAULT_WORLD_HEALTHCHECK_INTERVAL}
  WORLD_HEALTHCHECK_TIMEOUT=${WORLD_HEALTHCHECK_TIMEOUT:-$DEFAULT_WORLD_HEALTHCHECK_TIMEOUT}
  WORLD_HEALTHCHECK_RETRIES=${WORLD_HEALTHCHECK_RETRIES:-$DEFAULT_WORLD_HEALTHCHECK_RETRIES}
  WORLD_HEALTHCHECK_START_PERIOD=${WORLD_HEALTHCHECK_START_PERIOD:-$DEFAULT_WORLD_HEALTHCHECK_START_PERIOD}
  for hc_key in "${HEALTHCHECK_KEYS[@]}"; do
    default_var="DEFAULT_${hc_key}"
    printf -v "$hc_key" '%s' "${!hc_key:-${!default_var}}"
  done
  unset hc_key default_var
  MODULE_ELUNA=${MODULE_ELUNA:-$DEFAULT_MODULE_ELUNA}
  BACKUP_PATH=${BACKUP_PATH:-$DEFAULT_BACKUP_PATH}

  local project_image_prefix
  project_image_prefix="$(sanitize_project_name "$DEFAULT_COMPOSE_PROJECT_NAME")"
  if [ "$STACK_IMAGE_MODE" = "playerbots" ]; then
    AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE="$(resolve_project_image_tag "$project_image_prefix" "authserver-playerbots")"
    AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE="$(resolve_project_image_tag "$project_image_prefix" "worldserver-playerbots")"
    AC_DB_IMPORT_IMAGE_VALUE="$(resolve_project_image_tag "$project_image_prefix" "db-import-playerbots")"
    AC_CLIENT_DATA_IMAGE_PLAYERBOTS_VALUE="$(resolve_project_image_tag "$project_image_prefix" "client-data-playerbots")"
  else
    AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_AUTH_IMAGE_PLAYERBOTS"
    AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_WORLD_IMAGE_PLAYERBOTS"
    AC_DB_IMPORT_IMAGE_VALUE="$DEFAULT_AC_DB_IMPORT_IMAGE"
    AC_CLIENT_DATA_IMAGE_PLAYERBOTS_VALUE="$DEFAULT_CLIENT_DATA_IMAGE_PLAYERBOTS"
  fi
  AC_AUTHSERVER_IMAGE_MODULES_VALUE="$(resolve_project_image_tag "$project_image_prefix" "authserver-modules-latest")"
  AC_WORLDSERVER_IMAGE_MODULES_VALUE="$(resolve_project_image_tag "$project_image_prefix" "worldserver-modules-latest")"

{
    cat <<EOF
# Generated by setup.sh

# Compose overrides (set to 1 to include matching file under compose-overrides/)
# mysql-expose.yml -> exposes MySQL externally via COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED
# worldserver-debug-logging.yml -> raises log verbosity via COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED
COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED=$COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED
COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED=$COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED

COMPOSE_PROJECT_NAME=$DEFAULT_COMPOSE_PROJECT_NAME

STORAGE_PATH=$STORAGE_PATH
STORAGE_PATH_LOCAL=$LOCAL_STORAGE_ROOT
STORAGE_CONFIG_PATH=$(get_template_value "STORAGE_CONFIG_PATH")
STORAGE_LOGS_PATH=$(get_template_value "STORAGE_LOGS_PATH")
STORAGE_MODULES_PATH=$(get_template_value "STORAGE_MODULES_PATH")
STORAGE_LUA_SCRIPTS_PATH=$(get_template_value "STORAGE_LUA_SCRIPTS_PATH")
STORAGE_MODULES_META_PATH=$(get_template_value "STORAGE_MODULES_META_PATH")
STORAGE_MODULE_SQL_PATH=$(get_template_value "STORAGE_MODULE_SQL_PATH")
STORAGE_INSTALL_MARKERS_PATH=$(get_template_value "STORAGE_INSTALL_MARKERS_PATH")
STORAGE_CLIENT_DATA_PATH=$(get_template_value "STORAGE_CLIENT_DATA_PATH")
STORAGE_LOCAL_SOURCE_PATH=$(get_template_value "STORAGE_LOCAL_SOURCE_PATH")
BACKUP_PATH=$BACKUP_PATH
TZ=$DEFAULT_TZ

# Database
MYSQL_IMAGE=$DEFAULT_MYSQL_IMAGE
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_ROOT_HOST=$DEFAULT_MYSQL_ROOT_HOST
MYSQL_USER=$DEFAULT_MYSQL_USER
  MYSQL_PORT=$DEFAULT_MYSQL_INTERNAL_PORT
  MYSQL_EXTERNAL_PORT=$MYSQL_EXTERNAL_PORT
MYSQL_DISABLE_BINLOG=${MYSQL_DISABLE_BINLOG:-$DEFAULT_MYSQL_DISABLE_BINLOG}
MYSQL_CONFIG_DIR=${MYSQL_CONFIG_DIR:-$DEFAULT_MYSQL_CONFIG_DIR}
MYSQL_CHARACTER_SET=$DEFAULT_MYSQL_CHARACTER_SET
MYSQL_COLLATION=$DEFAULT_MYSQL_COLLATION
MYSQL_MAX_CONNECTIONS=$DEFAULT_MYSQL_MAX_CONNECTIONS
MYSQL_INNODB_BUFFER_POOL_SIZE=$DEFAULT_MYSQL_INNODB_BUFFER_POOL_SIZE
MYSQL_INNODB_LOG_FILE_SIZE=$DEFAULT_MYSQL_INNODB_LOG_FILE_SIZE
MYSQL_INNODB_REDO_LOG_CAPACITY=${MYSQL_INNODB_REDO_LOG_CAPACITY:-$DEFAULT_MYSQL_INNODB_REDO_LOG_CAPACITY}
MYSQL_RUNTIME_TMPFS_SIZE=${MYSQL_RUNTIME_TMPFS_SIZE:-$DEFAULT_MYSQL_RUNTIME_TMPFS_SIZE}
MYSQL_HOST=$DEFAULT_MYSQL_HOST
DB_WAIT_RETRIES=$DB_WAIT_RETRIES
DB_WAIT_SLEEP=$DB_WAIT_SLEEP
DB_AUTH_NAME=$DEFAULT_DB_AUTH_NAME
DB_WORLD_NAME=$DEFAULT_DB_WORLD_NAME
DB_CHARACTERS_NAME=$DEFAULT_DB_CHARACTERS_NAME
DB_PLAYERBOTS_NAME=${DB_PLAYERBOTS_NAME:-$DEFAULT_DB_PLAYERBOTS_NAME}
AC_DB_IMPORT_IMAGE=$AC_DB_IMPORT_IMAGE_VALUE

# Database Import Settings
DB_RECONNECT_SECONDS=$DB_RECONNECT_SECONDS
DB_RECONNECT_ATTEMPTS=$DB_RECONNECT_ATTEMPTS
DB_UPDATES_ALLOWED_MODULES=$DB_UPDATES_ALLOWED_MODULES
DB_UPDATES_REDUNDANCY=$DB_UPDATES_REDUNDANCY
DB_LOGIN_WORKER_THREADS=$DB_LOGIN_WORKER_THREADS
DB_WORLD_WORKER_THREADS=$DB_WORLD_WORKER_THREADS
DB_CHARACTER_WORKER_THREADS=$DB_CHARACTER_WORKER_THREADS
DB_LOGIN_SYNCH_THREADS=$DB_LOGIN_SYNCH_THREADS
DB_WORLD_SYNCH_THREADS=$DB_WORLD_SYNCH_THREADS
DB_CHARACTER_SYNCH_THREADS=$DB_CHARACTER_SYNCH_THREADS

# Services (images)
AC_AUTHSERVER_IMAGE=$DEFAULT_AC_AUTHSERVER_IMAGE
AC_WORLDSERVER_IMAGE=$DEFAULT_AC_WORLDSERVER_IMAGE
AC_AUTHSERVER_IMAGE_PLAYERBOTS=${AC_AUTHSERVER_IMAGE_PLAYERBOTS_VALUE}
AC_WORLDSERVER_IMAGE_PLAYERBOTS=${AC_WORLDSERVER_IMAGE_PLAYERBOTS_VALUE}
AC_AUTHSERVER_IMAGE_MODULES=${AC_AUTHSERVER_IMAGE_MODULES_VALUE}
AC_WORLDSERVER_IMAGE_MODULES=${AC_WORLDSERVER_IMAGE_MODULES_VALUE}

# Client data images
AC_CLIENT_DATA_IMAGE=$DEFAULT_AC_CLIENT_DATA_IMAGE
AC_CLIENT_DATA_IMAGE_PLAYERBOTS=$AC_CLIENT_DATA_IMAGE_PLAYERBOTS_VALUE
CLIENT_DATA_CACHE_PATH=$DEFAULT_CLIENT_DATA_CACHE_PATH
CLIENT_DATA_PATH=$CLIENT_DATA_PATH

# Build artifacts
DOCKER_IMAGE_TAG=$DEFAULT_DOCKER_IMAGE_TAG
AC_AUTHSERVER_IMAGE_BASE=$DEFAULT_AUTHSERVER_IMAGE_BASE
AC_WORLDSERVER_IMAGE_BASE=$DEFAULT_WORLDSERVER_IMAGE_BASE
AC_DB_IMPORT_IMAGE_BASE=$DEFAULT_DB_IMPORT_IMAGE_BASE
AC_CLIENT_DATA_IMAGE_BASE=$DEFAULT_CLIENT_DATA_IMAGE_BASE

# Container user
CONTAINER_USER=$CONTAINER_USER

# Containers
CONTAINER_MYSQL=$DEFAULT_CONTAINER_MYSQL
CONTAINER_DB_IMPORT=$DEFAULT_CONTAINER_DB_IMPORT
CONTAINER_DB_INIT=$DEFAULT_CONTAINER_DB_INIT
CONTAINER_DB_GUARD=$(get_template_value "CONTAINER_DB_GUARD")
CONTAINER_BACKUP=$DEFAULT_CONTAINER_BACKUP
CONTAINER_MODULES=$DEFAULT_CONTAINER_MODULES
CONTAINER_POST_INSTALL=$DEFAULT_CONTAINER_POST_INSTALL

# Database Guard Defaults
DB_GUARD_RECHECK_SECONDS=$(get_template_value "DB_GUARD_RECHECK_SECONDS")
DB_GUARD_RETRY_SECONDS=$(get_template_value "DB_GUARD_RETRY_SECONDS")
DB_GUARD_WAIT_ATTEMPTS=$(get_template_value "DB_GUARD_WAIT_ATTEMPTS")
DB_GUARD_HEALTH_MAX_AGE=$(get_template_value "DB_GUARD_HEALTH_MAX_AGE")
DB_GUARD_HEALTHCHECK_INTERVAL=$(get_template_value "DB_GUARD_HEALTHCHECK_INTERVAL")
DB_GUARD_HEALTHCHECK_TIMEOUT=$(get_template_value "DB_GUARD_HEALTHCHECK_TIMEOUT")
DB_GUARD_HEALTHCHECK_RETRIES=$(get_template_value "DB_GUARD_HEALTHCHECK_RETRIES")
DB_GUARD_VERIFY_INTERVAL_SECONDS=$(get_template_value "DB_GUARD_VERIFY_INTERVAL_SECONDS")

# Module SQL staging
STAGE_PATH_MODULE_SQL=$(get_template_value "STAGE_PATH_MODULE_SQL")

# Modules rebuild source path
MODULES_REBUILD_SOURCE_PATH=$MODULES_REBUILD_SOURCE_PATH

# SQL Source Overlay
SOURCE_DIR=$(get_template_value "SOURCE_DIR")
AC_SQL_SOURCE_PATH=$(get_template_value "AC_SQL_SOURCE_PATH")

# Ports
AUTH_EXTERNAL_PORT=$AUTH_EXTERNAL_PORT
AUTH_PORT=$DEFAULT_AUTH_INTERNAL_PORT
WORLD_EXTERNAL_PORT=$REALM_PORT
WORLD_PORT=$DEFAULT_WORLD_INTERNAL_PORT
SOAP_EXTERNAL_PORT=$SOAP_EXTERNAL_PORT
SOAP_PORT=$DEFAULT_SOAP_INTERNAL_PORT

# Realm
SERVER_ADDRESS=$SERVER_ADDRESS
REALM_PORT=$REALM_PORT

# Backups
BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS
BACKUP_RETENTION_HOURS=$BACKUP_RETENTION_HOURS
BACKUP_DAILY_TIME=$BACKUP_DAILY_TIME
BACKUP_INTERVAL_MINUTES=$(get_template_value "BACKUP_INTERVAL_MINUTES")
BACKUP_EXTRA_DATABASES=$(get_template_value "BACKUP_EXTRA_DATABASES")
BACKUP_HEALTHCHECK_MAX_MINUTES=$BACKUP_HEALTHCHECK_MAX_MINUTES
BACKUP_HEALTHCHECK_GRACE_SECONDS=$BACKUP_HEALTHCHECK_GRACE_SECONDS

EOF
    echo
  echo "# Modules"
  for module_key in "${MODULE_KEYS[@]}"; do
    local module_value="${!module_key:-0}"
    # Only write enabled modules (value=1) to .env
    if [ "$module_value" = "1" ]; then
      printf "%s=%s\n" "$module_key" "$module_value"
    fi
  done
  cat <<EOF

# Client data
CLIENT_DATA_VERSION=${CLIENT_DATA_VERSION:-$DEFAULT_CLIENT_DATA_VERSION}

# Server configuration
SERVER_CONFIG_PRESET=$SERVER_CONFIG_PRESET

# Playerbot runtime
PLAYERBOT_ENABLED=$PLAYERBOT_ENABLED
PLAYERBOT_MIN_BOTS=$PLAYERBOT_MIN_BOTS
PLAYERBOT_MAX_BOTS=$PLAYERBOT_MAX_BOTS
STACK_IMAGE_MODE=$STACK_IMAGE_MODE
STACK_SOURCE_VARIANT=$STACK_SOURCE_VARIANT
MODULES_ENABLED_LIST=$MODULES_ENABLED_LIST
MODULES_CPP_LIST=$MODULES_CPP_LIST
MODULES_REQUIRES_CUSTOM_BUILD=$MODULES_REQUIRES_CUSTOM_BUILD
MODULES_REQUIRES_PLAYERBOT_SOURCE=$MODULES_REQUIRES_PLAYERBOT_SOURCE

  # Eluna
  AC_ELUNA_ENABLED=$DEFAULT_ELUNA_ENABLED
AC_ELUNA_TRACE_BACK=$DEFAULT_ELUNA_TRACE_BACK
AC_ELUNA_AUTO_RELOAD=$DEFAULT_ELUNA_AUTO_RELOAD
AC_ELUNA_BYTECODE_CACHE=$DEFAULT_ELUNA_BYTECODE_CACHE
AC_ELUNA_SCRIPT_PATH=$DEFAULT_ELUNA_SCRIPT_PATH
AC_ELUNA_REQUIRE_PATHS=$DEFAULT_ELUNA_REQUIRE_PATHS
AC_ELUNA_REQUIRE_CPATHS=$DEFAULT_ELUNA_REQUIRE_CPATHS
AC_ELUNA_AUTO_RELOAD_INTERVAL=$DEFAULT_ELUNA_AUTO_RELOAD_INTERVAL

# Tools
PMA_HOST=$DEFAULT_CONTAINER_MYSQL
PMA_PORT=$DEFAULT_MYSQL_INTERNAL_PORT
PMA_USER=$DEFAULT_PMA_USER
PMA_EXTERNAL_PORT=$DEFAULT_PMA_EXTERNAL_PORT
PMA_ARBITRARY=$DEFAULT_PMA_ARBITRARY
PMA_ABSOLUTE_URI=$DEFAULT_PMA_ABSOLUTE_URI
PMA_UPLOAD_LIMIT=$DEFAULT_PMA_UPLOAD_LIMIT
PMA_MEMORY_LIMIT=$DEFAULT_PMA_MEMORY_LIMIT
PMA_MAX_EXECUTION_TIME=$DEFAULT_PMA_MAX_EXECUTION_TIME
KEIRA3_EXTERNAL_PORT=$DEFAULT_KEIRA3_EXTERNAL_PORT
KEIRA_DATABASE_HOST=$DEFAULT_CONTAINER_MYSQL
KEIRA_DATABASE_PORT=$DEFAULT_MYSQL_INTERNAL_PORT

# Health checks
EOF
    for hc_key in "${HEALTHCHECK_KEYS[@]}"; do
      printf "%s=%s\n" "$hc_key" "${!hc_key}"
    done
    cat <<EOF

# Networking
NETWORK_NAME=$DEFAULT_NETWORK_NAME
NETWORK_SUBNET=$DEFAULT_NETWORK_SUBNET
NETWORK_GATEWAY=$DEFAULT_NETWORK_GATEWAY

# Storage helpers
HOST_ZONEINFO_PATH=${HOST_ZONEINFO_PATH:-$DEFAULT_HOST_ZONEINFO_PATH}

# Helper images
ALPINE_GIT_IMAGE=$DEFAULT_ALPINE_GIT_IMAGE
ALPINE_IMAGE=$DEFAULT_ALPINE_IMAGE
EOF
  } > "$ENV_OUT"

  local staging_modules_dir="${LOCAL_STORAGE_ROOT_ABS}/modules"
  mkdir -p "$staging_modules_dir"

  local module_state_string=""
  for module_state_var in "${MODULE_KEYS[@]}"; do
    local module_value="${!module_state_var:-0}"
    module_state_string+="${module_state_var}=${module_value}|"
  done
  printf '%s' "$module_state_string" > "${staging_modules_dir}/.modules_state"
  if [ "$NEEDS_CXX_REBUILD" != "1" ]; then
    rm -f "${staging_modules_dir}/.requires_rebuild" 2>/dev/null || true
  fi

  say SUCCESS ".env written to $ENV_OUT"
  show_realm_configured


  say INFO "Ready to bring your realm online:"
  if [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    printf '  🔨 First, build custom modules: ./build.sh\n'
    printf '  🚀 Then deploy your realm: ./deploy.sh\n'
  else
    printf '  🚀 Quick deploy: ./deploy.sh\n'
  fi

}

main "$@"

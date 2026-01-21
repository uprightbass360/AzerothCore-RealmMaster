# Module metadata and helpers for setup.sh

# setup.sh -> scripts/bash/lib/common.sh (shared helpers)
source "$SCRIPT_DIR/scripts/bash/lib/common.sh"

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
  require_cmd python3

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

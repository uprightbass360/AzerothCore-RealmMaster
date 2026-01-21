# Module selection workflow for setup.sh

setup_select_modules() {
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
    local source_branch
    source_branch=$(get_preset_source_branch "$preset_name")
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

  PLAYERBOT_ENABLED=0
  PLAYERBOT_MIN_BOTS="${DEFAULT_PLAYERBOT_MIN:-40}"
  PLAYERBOT_MAX_BOTS="${DEFAULT_PLAYERBOT_MAX:-40}"

  NEEDS_CXX_REBUILD=0

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

  MODULES_ENABLED_LIST=""
  MODULES_CPP_LIST=""
  if [ ${#enabled_module_keys[@]} -gt 0 ]; then
    MODULES_ENABLED_LIST="$(IFS=','; printf '%s' "${enabled_module_keys[*]}")"
  fi
  if [ ${#enabled_cpp_module_keys[@]} -gt 0 ]; then
    MODULES_CPP_LIST="$(IFS=','; printf '%s' "${enabled_cpp_module_keys[*]}")"
  fi

  # Determine source variant based ONLY on playerbots module
  STACK_SOURCE_VARIANT="core"
  if [ "$MODULE_PLAYERBOTS" = "1" ] || [ "$PLAYERBOT_ENABLED" = "1" ]; then
    STACK_SOURCE_VARIANT="playerbots"
  fi

  # Determine image mode based on source variant and build requirements
  STACK_IMAGE_MODE="standard"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    STACK_IMAGE_MODE="playerbots"
  elif [ "$NEEDS_CXX_REBUILD" = "1" ]; then
    STACK_IMAGE_MODE="modules"
  fi

  MODULES_REQUIRES_CUSTOM_BUILD="$NEEDS_CXX_REBUILD"
  MODULES_REQUIRES_PLAYERBOT_SOURCE="0"
  if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    MODULES_REQUIRES_PLAYERBOT_SOURCE="1"
  fi

  export NEEDS_CXX_REBUILD
  MODULE_MODE_LABEL="$module_mode_label"
}

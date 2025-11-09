#!/bin/bash
# Simple wrapper script for server configuration management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}🔧 AzerothCore Configuration Manager${NC}\n"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  apply                   Apply configuration overrides from config/server-overrides.conf
  preset <name>           Apply a preset configuration
  list                    List available presets
  edit                    Open server-overrides.conf in editor
  status                  Show current configuration status

Examples:
  $(basename "$0") apply                 # Apply custom overrides
  $(basename "$0") preset fast-leveling  # Apply fast-leveling preset
  $(basename "$0") list                  # Show available presets
  $(basename "$0") edit                  # Edit configuration file

EOF
}

edit_config() {
    local config_file="$PROJECT_DIR/config/server-overrides.conf"
    local editor="${EDITOR:-nano}"

    echo -e "${YELLOW}📝 Opening configuration file in $editor...${NC}"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${YELLOW}⚠️  Configuration file doesn't exist. Creating template...${NC}"
        mkdir -p "$(dirname "$config_file")"
        # Create a minimal template if it doesn't exist
        cat > "$config_file" << 'EOF'
# AzerothCore Server Configuration Overrides
# Edit this file and run './scripts/bash/configure-server.sh apply' to update settings

[worldserver.conf]
# Example settings - uncomment and modify as needed
# Rate.XP.Kill = 2.0
# Rate.XP.Quest = 2.0
# MaxPlayerLevel = 80

[playerbots.conf]
# Example playerbot settings
# AiPlayerbot.MinRandomBots = 100
# AiPlayerbot.MaxRandomBots = 300
EOF
        echo -e "${GREEN}✅ Created template configuration file${NC}"
    fi

    "$editor" "$config_file"

    echo -e "\n${YELLOW}Would you like to apply these changes now? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        python3 "$SCRIPT_DIR/apply-config.py"
    else
        echo -e "${BLUE}ℹ️  Run '$(basename "$0") apply' when ready to apply changes${NC}"
    fi
}

show_status() {
    echo -e "${BLUE}📊 Configuration Status${NC}\n"

    # Check if config files exist
    local storage_path="${STORAGE_PATH:-./storage}"
    local config_dir="$storage_path/config"

    if [[ -d "$config_dir" ]]; then
        echo -e "${GREEN}✅ Config directory found: $config_dir${NC}"

        local conf_count
        conf_count=$(find "$config_dir" -name "*.conf" -type f | wc -l)
        echo -e "${GREEN}📄 Configuration files: $conf_count${NC}"

        # Show some key files
        for conf in worldserver.conf authserver.conf playerbots.conf; do
            if [[ -f "$config_dir/$conf" ]]; then
                echo -e "${GREEN}   ✅ $conf${NC}"
            else
                echo -e "${YELLOW}   ⚠️  $conf (missing)${NC}"
            fi
        done
    else
        echo -e "${RED}❌ Config directory not found: $config_dir${NC}"
        echo -e "${YELLOW}ℹ️  Run './deploy.sh' first to initialize storage${NC}"
    fi

    # Check override file
    local override_file="$PROJECT_DIR/config/server-overrides.conf"
    if [[ -f "$override_file" ]]; then
        echo -e "${GREEN}✅ Override file: $override_file${NC}"
    else
        echo -e "${YELLOW}⚠️  Override file not found${NC}"
        echo -e "${BLUE}ℹ️  Run '$(basename "$0") edit' to create one${NC}"
    fi

    # Show available presets
    echo -e "\n${BLUE}📋 Available Presets:${NC}"
    python3 "$SCRIPT_DIR/apply-config.py" --list-presets
}

main() {
    print_header

    case "${1:-}" in
        "apply")
            echo -e "${YELLOW}🔄 Applying configuration overrides...${NC}"
            python3 "$SCRIPT_DIR/apply-config.py" "${@:2}"
            echo -e "\n${GREEN}✅ Configuration applied!${NC}"
            echo -e "${YELLOW}ℹ️  Restart your server to apply changes:${NC} docker compose restart"
            ;;
        "preset")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}❌ Please specify a preset name${NC}"
                echo -e "Available presets:"
                python3 "$SCRIPT_DIR/apply-config.py" --list-presets
                exit 1
            fi
            echo -e "${YELLOW}🎯 Applying preset: $2${NC}"
            python3 "$SCRIPT_DIR/apply-config.py" --preset "$2" "${@:3}"
            echo -e "\n${GREEN}✅ Preset '$2' applied!${NC}"
            echo -e "${YELLOW}ℹ️  Restart your server to apply changes:${NC} docker compose restart"
            ;;
        "list")
            python3 "$SCRIPT_DIR/apply-config.py" --list-presets
            ;;
        "edit")
            edit_config
            ;;
        "status")
            show_status
            ;;
        "help"|"--help"|"-h"|"")
            show_usage
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
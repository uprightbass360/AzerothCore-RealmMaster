#!/bin/bash

# ==============================================
# AzerothCore Server Setup Script
# ==============================================
# Interactive script to configure common server settings and generate deployment-ready environment files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}ℹ️  ${message}${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ ${message}${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ ${message}${NC}"
            ;;
        "HEADER")
            echo -e "\n${MAGENTA}=== ${message} ===${NC}"
            ;;
        "PROMPT")
            echo -e "${YELLOW}🔧 ${message}${NC}"
            ;;
    esac
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port number
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to validate number
validate_number() {
    local num=$1
    if [[ $num =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to prompt for input with validation
prompt_input() {
    local prompt=$1
    local default=$2
    local validator=$3
    local value=""

    while true; do
        if [ -n "$default" ]; then
            read -p "$(echo -e "${YELLOW}🔧 ${prompt} [${default}]: ${NC}")" value
            value=${value:-$default}
        else
            read -p "$(echo -e "${YELLOW}🔧 ${prompt}: ${NC}")" value
        fi

        if [ -z "$validator" ] || $validator "$value"; then
            echo "$value"
            return 0
        else
            print_status "ERROR" "Invalid input. Please try again."
        fi
    done
}

# Function to prompt for yes/no input
prompt_yes_no() {
    local prompt=$1
    local default=$2

    while true; do
        if [ "$default" = "y" ]; then
            read -p "$(echo -e "${YELLOW}🔧 ${prompt} [Y/n]: ${NC}")" value
            value=${value:-y}
        else
            read -p "$(echo -e "${YELLOW}🔧 ${prompt} [y/N]: ${NC}")" value
            value=${value:-n}
        fi

        case $value in
            [Yy]*) echo "1"; return 0 ;;
            [Nn]*) echo "0"; return 0 ;;
            *) print_status "ERROR" "Please answer y or n" ;;
        esac
    done
}

# Function to show deployment type info
show_deployment_info() {
    local type=$1
    case $type in
        "local")
            print_status "INFO" "Local Development Setup:"
            echo "  - Server accessible only on this machine"
            echo "  - Server address: 127.0.0.1"
            echo "  - Storage: ./storage (local directory)"
            echo "  - Perfect for development and testing"
            ;;
        "lan")
            print_status "INFO" "LAN Server Setup:"
            echo "  - Server accessible on local network"
            echo "  - Requires your machine's LAN IP address"
            echo "  - Storage: configurable"
            echo "  - Good for home networks or office environments"
            ;;
        "public")
            print_status "INFO" "Public Server Setup:"
            echo "  - Server accessible from the internet"
            echo "  - Requires public IP or domain name"
            echo "  - Requires port forwarding configuration"
            echo "  - Storage: recommended to use persistent storage"
            ;;
    esac
    echo ""
}

# Main configuration function
main() {
    print_status "HEADER" "AZEROTHCORE SERVER SETUP"
    echo "This script will help you configure your AzerothCore server for deployment."
    echo "It will create customized environment files based on your configuration."
    echo ""

    # Check if we're in the right directory
    if [ ! -f "docker-compose-azerothcore-database.env" ] || [ ! -f "docker-compose-azerothcore-services.env" ]; then
        print_status "ERROR" "Environment files not found. Please run this script from the acore-compose directory."
        exit 1
    fi

    # Deployment type selection
    print_status "HEADER" "DEPLOYMENT TYPE"
    echo "Select your deployment type:"
    echo "1) Local Development (single machine)"
    echo "2) LAN Server (local network)"
    echo "3) Public Server (internet accessible)"
    echo ""

    while true; do
        read -p "$(echo -e "${YELLOW}🔧 Select deployment type [1-3]: ${NC}")" deploy_type
        case $deploy_type in
            1)
                DEPLOYMENT_TYPE="local"
                show_deployment_info "local"
                break
                ;;
            2)
                DEPLOYMENT_TYPE="lan"
                show_deployment_info "lan"
                break
                ;;
            3)
                DEPLOYMENT_TYPE="public"
                show_deployment_info "public"
                break
                ;;
            *)
                print_status "ERROR" "Please select 1, 2, or 3"
                ;;
        esac
    done

    # Server configuration
    print_status "HEADER" "SERVER CONFIGURATION"

    # Server address configuration
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
        SERVER_ADDRESS="127.0.0.1"
        print_status "INFO" "Server address set to: $SERVER_ADDRESS"
    else
        if [ "$DEPLOYMENT_TYPE" = "lan" ]; then
            # Try to detect LAN IP
            LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | head -1 | awk '{print $7}' || echo "")
            if [ -n "$LAN_IP" ]; then
                SERVER_ADDRESS=$(prompt_input "Enter server IP address" "$LAN_IP" validate_ip)
            else
                SERVER_ADDRESS=$(prompt_input "Enter server IP address (e.g., 192.168.1.100)" "" validate_ip)
            fi
        else
            # Public server
            SERVER_ADDRESS=$(prompt_input "Enter server address (IP or domain)" "your-domain.com" "")
        fi
    fi

    # Port configuration
    REALM_PORT=$(prompt_input "Enter client connection port" "8215" validate_port)
    AUTH_EXTERNAL_PORT=$(prompt_input "Enter auth server port" "3784" validate_port)
    SOAP_EXTERNAL_PORT=$(prompt_input "Enter SOAP API port" "7778" validate_port)
    MYSQL_EXTERNAL_PORT=$(prompt_input "Enter MySQL external port" "64306" validate_port)

    # Database configuration
    print_status "HEADER" "DATABASE CONFIGURATION"
    MYSQL_ROOT_PASSWORD=$(prompt_input "Enter MySQL root password" "azerothcore123" "")

    # Storage configuration
    print_status "HEADER" "STORAGE CONFIGURATION"
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
        STORAGE_ROOT="./storage"
        print_status "INFO" "Storage path set to: $STORAGE_ROOT"
    else
        echo "Storage options:"
        echo "1) ./storage (local directory)"
        echo "2) /nfs/containers (NFS mount)"
        echo "3) Custom path"

        while true; do
            read -p "$(echo -e "${YELLOW}🔧 Select storage option [1-3]: ${NC}")" storage_option
            case $storage_option in
                1)
                    STORAGE_ROOT="./storage"
                    break
                    ;;
                2)
                    STORAGE_ROOT="/nfs/containers"
                    break
                    ;;
                3)
                    STORAGE_ROOT=$(prompt_input "Enter custom storage path" "/mnt/azerothcore-data" "")
                    break
                    ;;
                *)
                    print_status "ERROR" "Please select 1, 2, or 3"
                    ;;
            esac
        done
    fi

    # Backup configuration
    print_status "HEADER" "BACKUP CONFIGURATION"
    BACKUP_RETENTION_DAYS=$(prompt_input "Days to keep daily backups" "3" validate_number)
    BACKUP_RETENTION_HOURS=$(prompt_input "Hours to keep hourly backups" "6" validate_number)
    BACKUP_DAILY_TIME=$(prompt_input "Daily backup time (24h format, e.g., 09 for 9 AM)" "09" "")

    # Optional: Timezone
    TIMEZONE=$(prompt_input "Server timezone" "UTC" "")

    # Module Configuration
    print_status "HEADER" "MODULE CONFIGURATION"
    echo "AzerothCore supports 25+ enhancement modules. Choose your setup:"
    echo "1) Suggested Modules (recommended for beginners)"
    echo "2) Manual Selection (advanced users)"
    echo "3) No Modules (vanilla experience)"
    echo ""

    MODULE_SELECTION_MODE=""
    while true; do
        read -p "$(echo -e "${YELLOW}🔧 Select module configuration [1-3]: ${NC}")" module_choice
        case $module_choice in
            1)
                MODULE_SELECTION_MODE="suggested"
                print_status "INFO" "Suggested Modules Selected:"
                echo "  ✅ Solo LFG - Dungeon finder for solo players"
                echo "  ✅ Solocraft - Scale content for solo players"
                echo "  ✅ Autobalance - Dynamic dungeon difficulty"
                echo "  ✅ AH Bot - Auction house automation"
                echo "  ✅ Transmog - Equipment appearance customization"
                echo "  ✅ NPC Buffer - Convenience buffs"
                echo "  ✅ Learn Spells - Auto-learn class spells"
                echo "  ✅ Fireworks - Level-up celebrations"
                echo ""
                break
                ;;
            2)
                MODULE_SELECTION_MODE="manual"
                print_status "INFO" "Manual Module Selection:"
                echo "  You will be prompted for each of the 25+ available modules"
                echo "  This allows full customization of your server experience"
                echo ""
                break
                ;;
            3)
                MODULE_SELECTION_MODE="none"
                print_status "INFO" "No Modules Selected:"
                echo "  Pure AzerothCore experience without enhancements"
                echo "  You can add modules later if needed"
                echo ""
                break
                ;;
            *)
                print_status "ERROR" "Please select 1, 2, or 3"
                ;;
        esac
    done

    # Initialize all modules to disabled
    MODULE_PLAYERBOTS=0
    MODULE_AOE_LOOT=0
    MODULE_LEARN_SPELLS=0
    MODULE_FIREWORKS=0
    MODULE_INDIVIDUAL_PROGRESSION=0
    MODULE_AHBOT=0
    MODULE_AUTOBALANCE=0
    MODULE_TRANSMOG=0
    MODULE_NPC_BUFFER=0
    MODULE_DYNAMIC_XP=0
    MODULE_SOLO_LFG=0
    MODULE_1V1_ARENA=0
    MODULE_PHASED_DUELS=0
    MODULE_BREAKING_NEWS=0
    MODULE_BOSS_ANNOUNCER=0
    MODULE_ACCOUNT_ACHIEVEMENTS=0
    MODULE_AUTO_REVIVE=0
    MODULE_GAIN_HONOR_GUARD=0
    MODULE_ELUNA=0
    MODULE_TIME_IS_TIME=0
    MODULE_POCKET_PORTAL=0
    MODULE_RANDOM_ENCHANTS=0
    MODULE_SOLOCRAFT=0
    MODULE_PVP_TITLES=0
    MODULE_NPC_BEASTMASTER=0
    MODULE_NPC_ENCHANTER=0
    MODULE_INSTANCE_RESET=0
    MODULE_LEVEL_GRANT=0
    MODULE_ASSISTANT=0
    MODULE_REAGENT_BANK=0
    MODULE_BLACK_MARKET_AUCTION_HOUSE=0
    MODULE_ARAC=0

    # Configure modules based on selection
    if [ "$MODULE_SELECTION_MODE" = "suggested" ]; then
        # Enable suggested modules for beginners
        MODULE_SOLO_LFG=1
        MODULE_SOLOCRAFT=1
        MODULE_AUTOBALANCE=1
        MODULE_AHBOT=1
        MODULE_TRANSMOG=1
        MODULE_NPC_BUFFER=1
        MODULE_LEARN_SPELLS=1
        MODULE_FIREWORKS=1

    elif [ "$MODULE_SELECTION_MODE" = "manual" ]; then
        print_status "PROMPT" "Configure each module (y/n):"

        # Core Gameplay Modules
        echo -e "\n${BLUE}🎮 Core Gameplay Modules:${NC}"
        MODULE_SOLO_LFG=$(prompt_yes_no "Solo LFG - Dungeon finder for solo players" "n")
        MODULE_SOLOCRAFT=$(prompt_yes_no "Solocraft - Scale dungeons/raids for solo play" "n")
        MODULE_AUTOBALANCE=$(prompt_yes_no "Autobalance - Dynamic difficulty scaling" "n")
        MODULE_PLAYERBOTS=$(prompt_yes_no "Playerbots - AI companions (REQUIRES SPECIAL BUILD)" "n")

        # Quality of Life Modules
        echo -e "\n${BLUE}🛠️ Quality of Life Modules:${NC}"
        MODULE_TRANSMOG=$(prompt_yes_no "Transmog - Equipment appearance customization" "n")
        MODULE_NPC_BUFFER=$(prompt_yes_no "NPC Buffer - Convenience buff NPCs" "n")
        MODULE_LEARN_SPELLS=$(prompt_yes_no "Learn Spells - Auto-learn class spells on level" "n")
        MODULE_AOE_LOOT=$(prompt_yes_no "AOE Loot - Loot multiple corpses at once" "n")
        MODULE_FIREWORKS=$(prompt_yes_no "Fireworks - Celebrate level ups" "n")
        MODULE_ASSISTANT=$(prompt_yes_no "Assistant - Multi-service NPC" "n")

        # Economy & Auction House
        echo -e "\n${BLUE}💰 Economy Modules:${NC}"
        MODULE_AHBOT=$(prompt_yes_no "AH Bot - Auction house automation" "n")
        MODULE_REAGENT_BANK=$(prompt_yes_no "Reagent Bank - Material storage system" "n")
        MODULE_BLACK_MARKET_AUCTION_HOUSE=$(prompt_yes_no "Black Market - MoP-style black market" "n")

        # PvP & Arena
        echo -e "\n${BLUE}⚔️ PvP Modules:${NC}"
        MODULE_1V1_ARENA=$(prompt_yes_no "1v1 Arena - Solo arena battles" "n")
        MODULE_PHASED_DUELS=$(prompt_yes_no "Phased Duels - Instanced dueling" "n")
        MODULE_PVP_TITLES=$(prompt_yes_no "PvP Titles - Additional honor titles" "n")

        # Progression & Experience
        echo -e "\n${BLUE}📈 Progression Modules:${NC}"
        MODULE_INDIVIDUAL_PROGRESSION=$(prompt_yes_no "Individual Progression - Per-player vanilla→TBC→WotLK" "n")
        MODULE_DYNAMIC_XP=$(prompt_yes_no "Dynamic XP - Customizable experience rates" "n")
        MODULE_LEVEL_GRANT=$(prompt_yes_no "Level Grant - Quest-based leveling rewards" "n")
        MODULE_ACCOUNT_ACHIEVEMENTS=$(prompt_yes_no "Account Achievements - Account-wide achievements" "n")

        # Server Management & Features
        echo -e "\n${BLUE}🔧 Server Features:${NC}"
        MODULE_BREAKING_NEWS=$(prompt_yes_no "Breaking News - Login screen announcements" "n")
        MODULE_BOSS_ANNOUNCER=$(prompt_yes_no "Boss Announcer - Server-wide boss kill announcements" "n")
        MODULE_AUTO_REVIVE=$(prompt_yes_no "Auto Revive - Automatic resurrection" "n")
        MODULE_ELUNA=$(prompt_yes_no "Eluna - Lua scripting engine" "n")

        # Special & Utility
        echo -e "\n${BLUE}🎯 Utility Modules:${NC}"
        MODULE_NPC_BEASTMASTER=$(prompt_yes_no "NPC Beastmaster - Pet management NPC" "n")
        MODULE_NPC_ENCHANTER=$(prompt_yes_no "NPC Enchanter - Enchanting services" "n")
        MODULE_RANDOM_ENCHANTS=$(prompt_yes_no "Random Enchants - Diablo-style random item stats" "n")
        MODULE_POCKET_PORTAL=$(prompt_yes_no "Pocket Portal - Portable teleportation" "n")
        MODULE_INSTANCE_RESET=$(prompt_yes_no "Instance Reset - Manual instance resets" "n")
        MODULE_TIME_IS_TIME=$(prompt_yes_no "Time is Time - Real-time game world" "n")
        MODULE_GAIN_HONOR_GUARD=$(prompt_yes_no "Gain Honor Guard - Honor from guard kills" "n")
        MODULE_ARAC=$(prompt_yes_no "All Races All Classes - Remove class restrictions (REQUIRES CLIENT PATCH)" "n")
    fi

    # Summary
    print_status "HEADER" "CONFIGURATION SUMMARY"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Server Address: $SERVER_ADDRESS"
    echo "Client Port: $REALM_PORT"
    echo "Auth Port: $AUTH_EXTERNAL_PORT"
    echo "SOAP Port: $SOAP_EXTERNAL_PORT"
    echo "MySQL Port: $MYSQL_EXTERNAL_PORT"
    echo "Storage Path: $STORAGE_ROOT"
    echo "Daily Backup Time: ${BACKUP_DAILY_TIME}:00 UTC"
    echo "Backup Retention: ${BACKUP_RETENTION_DAYS} days, ${BACKUP_RETENTION_HOURS} hours"

    # Module summary
    if [ "$MODULE_SELECTION_MODE" = "suggested" ]; then
        echo "Modules: Suggested preset (8 modules)"
    elif [ "$MODULE_SELECTION_MODE" = "manual" ]; then
        ENABLED_COUNT=0
        [ "$MODULE_SOLO_LFG" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_SOLOCRAFT" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_AUTOBALANCE" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_PLAYERBOTS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_TRANSMOG" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_NPC_BUFFER" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_LEARN_SPELLS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_AOE_LOOT" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_FIREWORKS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_ASSISTANT" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_AHBOT" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_REAGENT_BANK" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_1V1_ARENA" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_PHASED_DUELS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_PVP_TITLES" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_INDIVIDUAL_PROGRESSION" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_DYNAMIC_XP" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_LEVEL_GRANT" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_ACCOUNT_ACHIEVEMENTS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_BREAKING_NEWS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_BOSS_ANNOUNCER" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_AUTO_REVIVE" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_ELUNA" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_NPC_BEASTMASTER" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_NPC_ENCHANTER" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_RANDOM_ENCHANTS" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_POCKET_PORTAL" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_INSTANCE_RESET" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_TIME_IS_TIME" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_GAIN_HONOR_GUARD" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        [ "$MODULE_ARAC" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
        echo "Modules: Custom selection ($ENABLED_COUNT modules)"
    else
        echo "Modules: None (vanilla experience)"
    fi
    echo ""

    # Confirmation
    while true; do
        read -p "$(echo -e "${YELLOW}🔧 Proceed with this configuration? [y/N]: ${NC}")" confirm
        case $confirm in
            [Yy]*)
                break
                ;;
            [Nn]*|"")
                print_status "INFO" "Configuration cancelled"
                exit 0
                ;;
            *)
                print_status "ERROR" "Please answer y or n"
                ;;
        esac
    done

    # Create custom environment files
    print_status "HEADER" "CREATING ENVIRONMENT FILES"

    # Create custom database environment file
    print_status "INFO" "Creating custom database environment file..."
    cp docker-compose-azerothcore-database.env docker-compose-azerothcore-database-custom.env

    # Substitute values in database env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#MYSQL_EXTERNAL_PORT=.*#MYSQL_EXTERNAL_PORT=${MYSQL_EXTERNAL_PORT}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_RETENTION_DAYS=.*#BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_RETENTION_HOURS=.*#BACKUP_RETENTION_HOURS=${BACKUP_RETENTION_HOURS}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_DAILY_TIME=.*#BACKUP_DAILY_TIME=${BACKUP_DAILY_TIME}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#TZ=.*#TZ=${TIMEZONE}#" docker-compose-azerothcore-database-custom.env

    # Create custom services environment file
    print_status "INFO" "Creating custom services environment file..."
    cp docker-compose-azerothcore-services.env docker-compose-azerothcore-services-custom.env

    # Substitute values in services env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#AUTH_EXTERNAL_PORT=.*#AUTH_EXTERNAL_PORT=${AUTH_EXTERNAL_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#WORLD_EXTERNAL_PORT=.*#WORLD_EXTERNAL_PORT=${REALM_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#SOAP_EXTERNAL_PORT=.*#SOAP_EXTERNAL_PORT=${SOAP_EXTERNAL_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#SERVER_ADDRESS=.*#SERVER_ADDRESS=${SERVER_ADDRESS}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#REALM_PORT=.*#REALM_PORT=${REALM_PORT}#" docker-compose-azerothcore-services-custom.env

    # Create custom tools environment file
    print_status "INFO" "Creating custom tools environment file..."
    cp docker-compose-azerothcore-tools.env docker-compose-azerothcore-tools-custom.env

    # Substitute values in tools env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-tools-custom.env

    # Create custom modules environment file (only if modules are enabled)
    if [ "$MODULE_SELECTION_MODE" != "none" ]; then
        print_status "INFO" "Creating custom modules environment file..."
        cp docker-compose-azerothcore-modules.env docker-compose-azerothcore-modules-custom.env

        # Substitute values in modules env file
        sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}#" docker-compose-azerothcore-modules-custom.env

        # Set all module variables
        sed -i "s#MODULE_PLAYERBOTS=.*#MODULE_PLAYERBOTS=${MODULE_PLAYERBOTS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_AOE_LOOT=.*#MODULE_AOE_LOOT=${MODULE_AOE_LOOT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_LEARN_SPELLS=.*#MODULE_LEARN_SPELLS=${MODULE_LEARN_SPELLS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_FIREWORKS=.*#MODULE_FIREWORKS=${MODULE_FIREWORKS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_INDIVIDUAL_PROGRESSION=.*#MODULE_INDIVIDUAL_PROGRESSION=${MODULE_INDIVIDUAL_PROGRESSION}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_AHBOT=.*#MODULE_AHBOT=${MODULE_AHBOT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_AUTOBALANCE=.*#MODULE_AUTOBALANCE=${MODULE_AUTOBALANCE}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_TRANSMOG=.*#MODULE_TRANSMOG=${MODULE_TRANSMOG}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_NPC_BUFFER=.*#MODULE_NPC_BUFFER=${MODULE_NPC_BUFFER}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_DYNAMIC_XP=.*#MODULE_DYNAMIC_XP=${MODULE_DYNAMIC_XP}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_SOLO_LFG=.*#MODULE_SOLO_LFG=${MODULE_SOLO_LFG}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_1V1_ARENA=.*#MODULE_1V1_ARENA=${MODULE_1V1_ARENA}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_PHASED_DUELS=.*#MODULE_PHASED_DUELS=${MODULE_PHASED_DUELS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_BREAKING_NEWS=.*#MODULE_BREAKING_NEWS=${MODULE_BREAKING_NEWS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_BOSS_ANNOUNCER=.*#MODULE_BOSS_ANNOUNCER=${MODULE_BOSS_ANNOUNCER}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_ACCOUNT_ACHIEVEMENTS=.*#MODULE_ACCOUNT_ACHIEVEMENTS=${MODULE_ACCOUNT_ACHIEVEMENTS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_AUTO_REVIVE=.*#MODULE_AUTO_REVIVE=${MODULE_AUTO_REVIVE}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_GAIN_HONOR_GUARD=.*#MODULE_GAIN_HONOR_GUARD=${MODULE_GAIN_HONOR_GUARD}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_ELUNA=.*#MODULE_ELUNA=${MODULE_ELUNA}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_TIME_IS_TIME=.*#MODULE_TIME_IS_TIME=${MODULE_TIME_IS_TIME}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_POCKET_PORTAL=.*#MODULE_POCKET_PORTAL=${MODULE_POCKET_PORTAL}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_RANDOM_ENCHANTS=.*#MODULE_RANDOM_ENCHANTS=${MODULE_RANDOM_ENCHANTS}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_SOLOCRAFT=.*#MODULE_SOLOCRAFT=${MODULE_SOLOCRAFT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_PVP_TITLES=.*#MODULE_PVP_TITLES=${MODULE_PVP_TITLES}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_NPC_BEASTMASTER=.*#MODULE_NPC_BEASTMASTER=${MODULE_NPC_BEASTMASTER}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_NPC_ENCHANTER=.*#MODULE_NPC_ENCHANTER=${MODULE_NPC_ENCHANTER}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_INSTANCE_RESET=.*#MODULE_INSTANCE_RESET=${MODULE_INSTANCE_RESET}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_LEVEL_GRANT=.*#MODULE_LEVEL_GRANT=${MODULE_LEVEL_GRANT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_ASSISTANT=.*#MODULE_ASSISTANT=${MODULE_ASSISTANT}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_REAGENT_BANK=.*#MODULE_REAGENT_BANK=${MODULE_REAGENT_BANK}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_BLACK_MARKET_AUCTION_HOUSE=.*#MODULE_BLACK_MARKET_AUCTION_HOUSE=${MODULE_BLACK_MARKET_AUCTION_HOUSE}#" docker-compose-azerothcore-modules-custom.env
        sed -i "s#MODULE_ARAC=.*#MODULE_ARAC=${MODULE_ARAC}#" docker-compose-azerothcore-modules-custom.env
    fi

    print_status "SUCCESS" "Custom environment files created:"
    echo "  - docker-compose-azerothcore-database-custom.env"
    echo "  - docker-compose-azerothcore-services-custom.env"
    echo "  - docker-compose-azerothcore-tools-custom.env"
    if [ "$MODULE_SELECTION_MODE" != "none" ]; then
        echo "  - docker-compose-azerothcore-modules-custom.env"
    fi
    echo ""

    # Deployment instructions
    print_status "HEADER" "DEPLOYMENT INSTRUCTIONS"
    echo "To deploy your server with the custom configuration:"
    echo ""
    echo "1. Deploy database layer:"
    echo "   docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml up -d"
    echo ""
    echo "2. Deploy services layer:"
    echo "   docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml up -d"
    echo ""
    if [ "$MODULE_SELECTION_MODE" != "none" ]; then
        echo "3. Deploy modules layer (installs and configures selected modules):"
        echo "   docker compose --env-file docker-compose-azerothcore-modules-custom.env -f docker-compose-azerothcore-modules.yml up -d"
        echo ""
        echo "4. Deploy tools layer (optional):"
        echo "   docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml up -d"
        echo ""
    else
        echo "3. Deploy tools layer (optional):"
        echo "   docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml up -d"
        echo ""
    fi

    if [ "$DEPLOYMENT_TYPE" != "local" ]; then
        print_status "WARNING" "Additional configuration required for ${DEPLOYMENT_TYPE} deployment:"
        echo "  - Ensure firewall allows traffic on configured ports"
        if [ "$DEPLOYMENT_TYPE" = "public" ]; then
            echo "  - Configure port forwarding on your router:"
            echo "    - ${REALM_PORT} (client connections)"
            echo "    - ${AUTH_EXTERNAL_PORT} (auth server)"
            echo "    - ${SOAP_EXTERNAL_PORT} (SOAP API)"
        fi
        echo ""
    fi

    # Client configuration
    print_status "HEADER" "CLIENT CONFIGURATION"
    echo "Configure your WoW 3.3.5a client by editing realmlist.wtf:"
    if [ "$REALM_PORT" = "8215" ]; then
        echo "  set realmlist ${SERVER_ADDRESS}"
    else
        echo "  set realmlist ${SERVER_ADDRESS} ${REALM_PORT}"
    fi
    echo ""

    print_status "SUCCESS" "🎉 Server setup complete!"
    print_status "INFO" "Your custom environment files are ready for deployment."
}

# Run main function
main "$@"
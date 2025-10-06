#!/bin/bash

# ==============================================
# AzerothCore Module Configuration Script
# ==============================================
# Handles post-installation configuration that requires manual setup beyond Docker automation

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
        "CRITICAL")
            echo -e "${RED}🚨 CRITICAL: ${message}${NC}"
            ;;
    esac
}

# Load environment variables
if [ -f "docker-compose-azerothcore-services.env" ]; then
    source docker-compose-azerothcore-services.env
else
    print_status "ERROR" "Environment file not found. Run from acore-compose directory."
    exit 1
fi

print_status "HEADER" "AZEROTHCORE MODULE CONFIGURATION ANALYSIS"
echo "This script analyzes your enabled modules and identifies manual configuration requirements."
echo ""

# Check which modules are enabled
ENABLED_MODULES=()
[ "$MODULE_PLAYERBOTS" = "1" ] && ENABLED_MODULES+=("PLAYERBOTS")
[ "$MODULE_AOE_LOOT" = "1" ] && ENABLED_MODULES+=("AOE_LOOT")
[ "$MODULE_LEARN_SPELLS" = "1" ] && ENABLED_MODULES+=("LEARN_SPELLS")
[ "$MODULE_FIREWORKS" = "1" ] && ENABLED_MODULES+=("FIREWORKS")
[ "$MODULE_INDIVIDUAL_PROGRESSION" = "1" ] && ENABLED_MODULES+=("INDIVIDUAL_PROGRESSION")
[ "$MODULE_TRANSMOG" = "1" ] && ENABLED_MODULES+=("TRANSMOG")
[ "$MODULE_SOLO_LFG" = "1" ] && ENABLED_MODULES+=("SOLO_LFG")
[ "$MODULE_ELUNA" = "1" ] && ENABLED_MODULES+=("ELUNA")
[ "$MODULE_ARAC" = "1" ] && ENABLED_MODULES+=("ARAC")
[ "$MODULE_NPC_ENCHANTER" = "1" ] && ENABLED_MODULES+=("NPC_ENCHANTER")
[ "$MODULE_ASSISTANT" = "1" ] && ENABLED_MODULES+=("ASSISTANT")
[ "$MODULE_REAGENT_BANK" = "1" ] && ENABLED_MODULES+=("REAGENT_BANK")
[ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" = "1" ] && ENABLED_MODULES+=("BLACK_MARKET")

print_status "INFO" "Found ${#ENABLED_MODULES[@]} enabled modules: ${ENABLED_MODULES[*]}"
echo ""

# Critical Compatibility Issues
print_status "HEADER" "CRITICAL COMPATIBILITY ISSUES"

if [[ " ${ENABLED_MODULES[*]} " =~ " PLAYERBOTS " ]]; then
    print_status "CRITICAL" "mod-playerbots REQUIRES CUSTOM AZEROTHCORE BRANCH"
    echo "   🔗 Required: liyunfan1223/azerothcore-wotlk/tree/Playerbot"
    echo "   ❌ Current: Standard AzerothCore (INCOMPATIBLE)"
    echo "   📋 Action: Switch to Playerbot branch OR disable MODULE_PLAYERBOTS"
    echo ""
fi

# Client-Side Requirements
print_status "HEADER" "CLIENT-SIDE PATCH REQUIREMENTS"

CLIENT_PATCHES_NEEDED=false

if [[ " ${ENABLED_MODULES[*]} " =~ " INDIVIDUAL_PROGRESSION " ]]; then
    print_status "WARNING" "mod-individual-progression requires CLIENT PATCHES"
    echo "   📁 Location: ${STORAGE_PATH}/modules/mod-individual-progression/optional/"
    echo "   📦 Required: patch-V.mpq (Vanilla crafting/recipes)"
    echo "   📦 Optional: patch-J.mpq (Vanilla login screen)"
    echo "   📦 Optional: patch-U.mpq (Vanilla loading screens)"
    echo "   🎯 Install: Copy to client WoW/Data/ directory"
    CLIENT_PATCHES_NEEDED=true
    echo ""
fi

if [[ " ${ENABLED_MODULES[*]} " =~ " ARAC " ]]; then
    print_status "WARNING" "mod-arac requires CLIENT PATCHES"
    echo "   📦 Required: Patch-A.MPQ"
    echo "   📁 Location: ${STORAGE_PATH}/modules/mod-arac/patch-contents/"
    echo "   🎯 Install: Copy Patch-A.MPQ to client WoW/Data/ directory"
    echo "   🔧 Server: DBC files automatically applied during module setup"
    CLIENT_PATCHES_NEEDED=true
    echo ""
fi

if [ "$CLIENT_PATCHES_NEEDED" = true ]; then
    print_status "INFO" "Client patches must be distributed manually to all players"
fi

# Critical Server Configuration Requirements
print_status "HEADER" "CRITICAL SERVER CONFIGURATION"

CONFIG_CHANGES_NEEDED=false

if [[ " ${ENABLED_MODULES[*]} " =~ " INDIVIDUAL_PROGRESSION " ]]; then
    print_status "CRITICAL" "mod-individual-progression requires worldserver.conf changes"
    echo "   ⚙️  Required: EnablePlayerSettings = 1"
    echo "   ⚙️  Required: DBC.EnforceItemAttributes = 0"
    echo "   📁 File: ${STORAGE_PATH}/config/worldserver.conf"
    CONFIG_CHANGES_NEEDED=true
    echo ""
fi

if [[ " ${ENABLED_MODULES[*]} " =~ " AOE_LOOT " ]]; then
    print_status "WARNING" "mod-aoe-loot requires worldserver.conf optimization"
    echo "   ⚙️  Required: Rate.Corpse.Decay.Looted = 0.01 (default: 0.5)"
    echo "   📁 File: ${STORAGE_PATH}/config/worldserver.conf"
    CONFIG_CHANGES_NEEDED=true
    echo ""
fi

# Manual NPC Spawning Requirements
print_status "HEADER" "MANUAL NPC SPAWNING REQUIRED"

NPC_SPAWNING_NEEDED=false

if [[ " ${ENABLED_MODULES[*]} " =~ " TRANSMOG " ]]; then
    print_status "INFO" "mod-transmog requires NPC spawning"
    echo "   🤖 Command: .npc add 190010"
    echo "   📍 Location: Spawn in major cities (Stormwind, Orgrimmar, etc.)"
    NPC_SPAWNING_NEEDED=true
    echo ""
fi

if [[ " ${ENABLED_MODULES[*]} " =~ " NPC_ENCHANTER " ]]; then
    print_status "INFO" "mod-npc-enchanter requires NPC spawning"
    echo "   🤖 Command: .npc add [enchanter_id]"
    echo "   📍 Location: Spawn in major cities"
    NPC_SPAWNING_NEEDED=true
    echo ""
fi

if [[ " ${ENABLED_MODULES[*]} " =~ " REAGENT_BANK " ]]; then
    print_status "INFO" "mod-reagent-bank requires NPC spawning"
    echo "   🤖 Command: .npc add 290011"
    echo "   📍 Location: Spawn in major cities"
    NPC_SPAWNING_NEEDED=true
    echo ""
fi

if [ "$NPC_SPAWNING_NEEDED" = true ]; then
    print_status "INFO" "Use GM account with level 3 permissions to spawn NPCs"
fi

# Configuration File Management
print_status "HEADER" "CONFIGURATION FILE SETUP"

echo "Module configuration files are automatically copied during container startup:"
echo ""

for module in "${ENABLED_MODULES[@]}"; do
    case $module in
        "PLAYERBOTS")
            echo "   📝 playerbots.conf - Bot behavior, RandomBot settings"
            ;;
        "AOE_LOOT")
            echo "   📝 mod_aoe_loot.conf - Loot range, group settings"
            ;;
        "LEARN_SPELLS")
            echo "   📝 mod_learnspells.conf - Auto-learn behavior"
            ;;
        "FIREWORKS")
            echo "   📝 mod_fireworks.conf - Level-up effects"
            ;;
        "INDIVIDUAL_PROGRESSION")
            echo "   📝 individual_progression.conf - Era progression settings"
            ;;
        "TRANSMOG")
            echo "   📝 transmog.conf - Transmogrification rules"
            ;;
        "SOLO_LFG")
            echo "   📝 SoloLfg.conf - Solo dungeon finder settings"
            ;;
        "ELUNA")
            echo "   📝 mod_LuaEngine.conf - Lua scripting engine"
            ;;
        *)
            ;;
    esac
done

# Database Backup Recommendation
print_status "HEADER" "DATABASE BACKUP RECOMMENDATION"

if [[ " ${ENABLED_MODULES[*]} " =~ " ARAC " ]] || [[ " ${ENABLED_MODULES[*]} " =~ " INDIVIDUAL_PROGRESSION " ]]; then
    print_status "CRITICAL" "Database backup STRONGLY RECOMMENDED"
    echo "   💾 Modules modify core database tables"
    echo "   🔄 Backup command: docker exec ac-mysql mysqldump -u root -p\${MYSQL_ROOT_PASSWORD} --all-databases > backup.sql"
    echo ""
fi

# Performance Considerations
print_status "HEADER" "PERFORMANCE CONSIDERATIONS"

if [[ " ${ENABLED_MODULES[*]} " =~ " PLAYERBOTS " ]]; then
    print_status "WARNING" "mod-playerbots can significantly impact server performance"
    echo "   🤖 Default: 500 RandomBots (MinRandomBots/MaxRandomBots)"
    echo "   💡 Recommendation: Start with lower numbers and scale up"
    echo "   📊 Monitor: CPU usage, memory consumption, database load"
    echo ""
fi

if [[ " ${ENABLED_MODULES[*]} " =~ " ELUNA " ]]; then
    print_status "INFO" "mod-eluna performance depends on Lua script complexity"
    echo "   📜 Complex scripts can impact server performance"
    echo "   🔍 Monitor script execution times"
    echo ""
fi

# Eluna Lua Scripting Setup
if [[ " ${ENABLED_MODULES[*]} " =~ " ELUNA " ]]; then
    print_status "HEADER" "ELUNA LUA SCRIPTING REQUIREMENTS"

    if [ -d "${STORAGE_PATH}/lua_scripts" ]; then
        print_status "SUCCESS" "Lua scripts directory exists: ${STORAGE_PATH}/lua_scripts"
        SCRIPT_COUNT=$(find "${STORAGE_PATH}/lua_scripts" -name "*.lua" 2>/dev/null | wc -l)
        print_status "INFO" "Found $SCRIPT_COUNT Lua script(s)"
    else
        print_status "WARNING" "Lua scripts directory missing: ${STORAGE_PATH}/lua_scripts"
        print_status "INFO" "Run ./scripts/setup-eluna.sh to create directory and example scripts"
    fi

    print_status "INFO" "Eluna Script Management:"
    echo "   🔄 Reload scripts: .reload eluna"
    echo "   📁 Script location: ${STORAGE_PATH}/lua_scripts"
    echo "   ⚠️  Compatibility: AzerothCore mod-eluna only (NOT standard Eluna)"
    echo "   📋 Requirements: English DBC files recommended"
    echo ""
fi

# Summary and Next Steps
print_status "HEADER" "SUMMARY AND NEXT STEPS"

echo "📋 REQUIRED MANUAL ACTIONS:"
echo ""

if [[ " ${ENABLED_MODULES[*]} " =~ " PLAYERBOTS " ]]; then
    echo "1. 🔧 CRITICAL: Switch to Playerbot AzerothCore branch OR disable MODULE_PLAYERBOTS"
fi

if [ "$CONFIG_CHANGES_NEEDED" = true ]; then
    echo "2. ⚙️  Edit worldserver.conf with required settings (see above)"
fi

if [ "$CLIENT_PATCHES_NEEDED" = true ]; then
    echo "3. 📦 Distribute client patches to all players"
fi

if [ "$NPC_SPAWNING_NEEDED" = true ]; then
    echo "4. 🤖 Spawn required NPCs using GM commands"
fi

echo ""
echo "📖 RECOMMENDED ORDER:"
echo "   1. Complete server configuration changes"
echo "   2. Rebuild containers with: ./scripts/rebuild-with-modules.sh"
echo "   3. Test in development environment first"
echo "   4. Create GM account and spawn NPCs"
echo "   5. Distribute client patches to players"
echo "   6. Monitor performance and adjust settings as needed"

echo ""
print_status "SUCCESS" "Module configuration analysis complete!"
print_status "INFO" "Review all CRITICAL and WARNING items before deploying to production"
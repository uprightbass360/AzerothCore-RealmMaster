#!/bin/bash

# ==============================================
# AzerothCore Eluna Lua Scripting Setup
# ==============================================
# Sets up Lua scripting environment for mod-eluna

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
    esac
}

# Load environment variables
if [ -f "docker-compose-azerothcore-services.env" ]; then
    source docker-compose-azerothcore-services.env
else
    print_status "ERROR" "Environment file not found. Run from acore-compose directory."
    exit 1
fi

print_status "HEADER" "AZEROTHCORE ELUNA LUA SCRIPTING SETUP"

# Check if Eluna is enabled
if [ "$MODULE_ELUNA" != "1" ]; then
    print_status "ERROR" "MODULE_ELUNA is not enabled. Set MODULE_ELUNA=1 in environment file."
    exit 1
fi

print_status "SUCCESS" "mod-eluna is enabled"

# Create lua_scripts directory
LUA_SCRIPTS_DIR="${STORAGE_PATH}/lua_scripts"
print_status "INFO" "Creating Lua scripts directory: $LUA_SCRIPTS_DIR"

if [ ! -d "$LUA_SCRIPTS_DIR" ]; then
    mkdir -p "$LUA_SCRIPTS_DIR"
    print_status "SUCCESS" "Created lua_scripts directory"
else
    print_status "INFO" "lua_scripts directory already exists"
fi

# Create example scripts
print_status "HEADER" "CREATING EXAMPLE LUA SCRIPTS"

# Welcome script
cat > "$LUA_SCRIPTS_DIR/welcome.lua" << 'EOF'
-- ==============================================
-- Welcome Script for AzerothCore mod-eluna
-- ==============================================
-- Sends welcome message to players on login

local PLAYER_EVENT_ON_LOGIN = 3

local function OnPlayerLogin(event, player)
    local playerName = player:GetName()
    local accountId = player:GetAccountId()

    -- Send welcome message
    player:SendBroadcastMessage("|cff00ff00Welcome to the AzerothCore server, " .. playerName .. "!|r")
    player:SendBroadcastMessage("|cffyellow🎮 This server features custom modules and Lua scripting!|r")

    -- Log the login
    print("Player " .. playerName .. " (Account: " .. accountId .. ") has logged in")
end

-- Register the event
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnPlayerLogin)

print("✅ Welcome script loaded successfully")
EOF

print_status "SUCCESS" "Created example welcome.lua script"

# Server info script
cat > "$LUA_SCRIPTS_DIR/server_info.lua" << 'EOF'
-- ==============================================
-- Server Info Commands for AzerothCore mod-eluna
-- ==============================================
-- Provides custom server information commands

local function ServerInfoCommand(player, command)
    if command == "info" or command == "serverinfo" then
        player:SendBroadcastMessage("|cff00ffffServer Information:|r")
        player:SendBroadcastMessage("• Core: AzerothCore with mod-eluna")
        player:SendBroadcastMessage("• Lua Scripting: Enabled")
        player:SendBroadcastMessage("• Active Modules: 13 gameplay enhancing modules")
        player:SendBroadcastMessage("• Features: Playerbots, Transmog, Solo LFG, and more!")
        return false -- Command handled
    end
    return true -- Command not handled, continue processing
end

-- Register the command handler
local PLAYER_EVENT_ON_COMMAND = 42
RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, ServerInfoCommand)

print("✅ Server info commands loaded successfully")
print("   Usage: .info or .serverinfo")
EOF

print_status "SUCCESS" "Created example server_info.lua script"

# Level reward script
cat > "$LUA_SCRIPTS_DIR/level_rewards.lua" << 'EOF'
-- ==============================================
-- Level Reward Script for AzerothCore mod-eluna
-- ==============================================
-- Gives rewards to players when they level up

local PLAYER_EVENT_ON_LEVEL_CHANGE = 13

local function OnPlayerLevelUp(event, player, oldLevel)
    local newLevel = player:GetLevel()
    local playerName = player:GetName()

    -- Skip if level decreased (rare edge case)
    if newLevel <= oldLevel then
        return
    end

    -- Congratulate the player
    player:SendBroadcastMessage("|cffff6600Congratulations on reaching level " .. newLevel .. "!|r")

    -- Give rewards for milestone levels
    local milestoneRewards = {
        [10] = {item = 6948, count = 1, message = "Hearthstone for your travels!"},
        [20] = {gold = 100, message = "1 gold to help with expenses!"},
        [30] = {gold = 500, message = "5 gold for your dedication!"},
        [40] = {gold = 1000, message = "10 gold for reaching level 40!"},
        [50] = {gold = 2000, message = "20 gold for reaching level 50!"},
        [60] = {gold = 5000, message = "50 gold for reaching the original level cap!"},
        [70] = {gold = 10000, message = "100 gold for reaching the Burning Crusade cap!"},
        [80] = {gold = 20000, message = "200 gold for reaching max level!"}
    }

    local reward = milestoneRewards[newLevel]
    if reward then
        if reward.item then
            player:AddItem(reward.item, reward.count or 1)
        end
        if reward.gold then
            player:ModifyMoney(reward.gold * 10000) -- Convert gold to copper
        end
        player:SendBroadcastMessage("|cffff0000Milestone Reward: " .. reward.message .. "|r")

        -- Announce to server for major milestones
        if newLevel >= 60 then
            SendWorldMessage("|cffff6600" .. playerName .. " has reached level " .. newLevel .. "! Congratulations!|r")
        end
    end

    print("Player " .. playerName .. " leveled from " .. oldLevel .. " to " .. newLevel)
end

-- Register the event
RegisterPlayerEvent(PLAYER_EVENT_ON_LEVEL_CHANGE, OnPlayerLevelUp)

print("✅ Level rewards script loaded successfully")
EOF

print_status "SUCCESS" "Created example level_rewards.lua script"

# Create a main loader script
cat > "$LUA_SCRIPTS_DIR/init.lua" << 'EOF'
-- ==============================================
-- Main Loader Script for AzerothCore mod-eluna
-- ==============================================
-- This script loads all other Lua scripts

print("🚀 Loading AzerothCore Lua Scripts...")

-- Load all scripts in this directory
-- Note: Individual scripts are loaded automatically by mod-eluna
-- This file serves as documentation for loaded scripts

local loadedScripts = {
    "welcome.lua - Player welcome messages on login",
    "server_info.lua - Custom server information commands",
    "level_rewards.lua - Milestone rewards for leveling"
}

print("📜 Available Lua Scripts:")
for i, script in ipairs(loadedScripts) do
    print("   " .. i .. ". " .. script)
end

print("✅ Lua script initialization complete")
print("🔧 To reload scripts: .reload eluna")
EOF

print_status "SUCCESS" "Created init.lua loader script"

# Create Eluna configuration documentation
cat > "$LUA_SCRIPTS_DIR/README.md" << 'EOF'
# AzerothCore Eluna Lua Scripts

This directory contains Lua scripts for the AzerothCore mod-eluna engine.

## Available Scripts

### welcome.lua
- Sends welcome messages to players on login
- Logs player login events
- Demonstrates basic player event handling

### server_info.lua
- Provides `.info` and `.serverinfo` commands
- Shows server configuration and features
- Demonstrates custom command registration

### level_rewards.lua
- Gives rewards to players at milestone levels (10, 20, 30, etc.)
- Announces major level achievements to the server
- Demonstrates player level change events and item/gold rewards

### init.lua
- Documentation script listing all available scripts
- Serves as a reference for loaded functionality

## Script Management

### Reloading Scripts
```
.reload eluna
```

### Adding New Scripts
1. Create `.lua` file in this directory
2. Use RegisterPlayerEvent, RegisterCreatureEvent, etc. to register events
3. Reload scripts with `.reload eluna` command

### Configuration
Eluna configuration is managed in `/azerothcore/config/mod_LuaEngine.conf`:
- Script path: `lua_scripts` (this directory)
- Auto-reload: Disabled by default (enable for development)
- Bytecode cache: Enabled for performance

## Event Types

Common event types for script development:
- `PLAYER_EVENT_ON_LOGIN = 3`
- `PLAYER_EVENT_ON_LOGOUT = 4`
- `PLAYER_EVENT_ON_LEVEL_CHANGE = 13`
- `PLAYER_EVENT_ON_COMMAND = 42`
- `CREATURE_EVENT_ON_SPAWN = 5`
- `SPELL_EVENT_ON_CAST = 1`

## API Reference

### Player Methods
- `player:GetName()` - Get player name
- `player:GetLevel()` - Get player level
- `player:SendBroadcastMessage(msg)` - Send message to player
- `player:AddItem(itemId, count)` - Add item to player
- `player:ModifyMoney(copper)` - Add/remove money (in copper)

### Global Functions
- `print(message)` - Log to server console
- `SendWorldMessage(message)` - Send message to all players
- `RegisterPlayerEvent(eventId, function)` - Register player event handler

## Development Tips

1. **Test in Development**: Enable auto-reload during development
2. **Error Handling**: Use pcall() for error-safe script execution
3. **Performance**: Avoid heavy operations in frequently called events
4. **Debugging**: Use print() statements for debugging output

## Compatibility Notes

- **AzerothCore Specific**: These scripts are for AzerothCore's mod-eluna
- **Not Compatible**: Standard Eluna scripts will NOT work
- **API Differences**: AzerothCore mod-eluna has different API than standard Eluna
EOF

print_status "SUCCESS" "Created comprehensive README.md documentation"

# Check if volume mount exists in docker-compose
print_status "HEADER" "CHECKING DOCKER COMPOSE CONFIGURATION"

if grep -q "lua_scripts" docker-compose-azerothcore-services.yml; then
    print_status "SUCCESS" "lua_scripts volume mount already configured"
else
    print_status "WARNING" "lua_scripts volume mount not found in docker-compose-azerothcore-services.yml"
    print_status "INFO" "You may need to add volume mount to worldserver service:"
    echo "      volumes:"
    echo "        - \${STORAGE_PATH}/lua_scripts:/azerothcore/lua_scripts"
fi

# Check if Eluna container is configured
if grep -q "ac-eluna:" docker-compose-azerothcore-services.yml; then
    print_status "SUCCESS" "Eluna container (ac-eluna) is configured"
else
    print_status "INFO" "No separate Eluna container found (using embedded mod-eluna)"
fi

# Summary
print_status "HEADER" "SETUP COMPLETE"

echo "📁 Lua Scripts Directory: $LUA_SCRIPTS_DIR"
echo "📜 Example Scripts Created:"
echo "   • welcome.lua - Player login messages"
echo "   • server_info.lua - Custom info commands"
echo "   • level_rewards.lua - Milestone rewards"
echo "   • init.lua - Script loader documentation"
echo "   • README.md - Complete documentation"
echo ""

print_status "INFO" "Next Steps:"
echo "1. Start/restart your worldserver container"
echo "2. Test scripts with GM commands:"
echo "   • .reload eluna"
echo "   • .info (test server_info.lua)"
echo "3. Login with a character to test welcome.lua"
echo "4. Level up a character to test level_rewards.lua"
echo ""

print_status "SUCCESS" "Eluna Lua scripting environment setup complete!"
print_status "WARNING" "Remember: AzerothCore mod-eluna is NOT compatible with standard Eluna scripts"
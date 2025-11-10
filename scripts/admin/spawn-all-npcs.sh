#!/bin/bash
# AzerothCore Custom NPC Spawn Script
# Spawns all custom NPCs to recommended locations
#
# Usage: ./spawn-all-npcs.sh [location]
# Locations: stormwind, orgrimmar, dalaran, shattrath, all
#
# Prerequisites:
# - GM access level 1 or higher
# - Server must be running
# - Execute in-game using .server script run or as GM commands

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# NPC Entry IDs and Names
declare -A NPCS=(
    ["199999"]="Kaylub|Professions NPC"
    ["290011"]="Ling|Reagent Banker"
    ["300000"]="Cromi|Instance Reset"
    ["500030"]="Talamortis|Guild House Seller"
    ["500031"]="Xrispins|Guild House Butler"
    ["500032"]="Monica|Guild House Innkeeper"
    ["601015"]="Beauregard Boneglitter|Enchanter"
    ["601016"]="Buffmaster Hasselhoof|Buffer"
    ["601026"]="White Fang|BeastMaster"
    ["601072"]="Cet Keres|Polymorphologist"
    ["190010"]="Warpweaver|Transmogrifier"
    ["190011"]="Ethereal Warpweaver|Transmogrifier"
    ["999991"]="Arena Battlemaster 1v1|Arena"
    ["9000000"]="Gabriella|The Assistant"
)

# Location coordinates (map x y z orientation)
declare -A STORMWIND=(
    ["199999"]="0 -8829.0 622.5 94.0 3.14"  # Kaylub - Trade District
    ["601015"]="0 -8831.0 618.5 94.0 0.0"   # Beauregard - Trade District
    ["601016"]="0 -8827.0 626.5 94.0 1.57"  # Buffmaster - Trade District
    ["190010"]="0 -8825.0 614.5 94.0 4.71"  # Warpweaver - Trade District
    ["9000000"]="0 -8833.0 630.0 94.0 2.35" # Gabriella - Trade District
)

declare -A ORGRIMMAR=(
    ["199999"]="1 1633.0 -4439.0 15.4 3.14"  # Kaylub - Valley of Strength
    ["601015"]="1 1629.0 -4443.0 15.4 0.0"   # Beauregard - Valley of Strength
    ["601016"]="1 1637.0 -4435.0 15.4 1.57"  # Buffmaster - Valley of Strength
    ["190011"]="1 1625.0 -4447.0 15.4 4.71"  # Ethereal Warpweaver - Valley of Strength
    ["9000000"]="1 1641.0 -4431.0 15.4 2.35" # Gabriella - Valley of Strength
)

declare -A DALARAN=(
    ["601072"]="571 5804.0 624.0 647.8 3.14"   # Cet Keres - Runeweaver Square
    ["190010"]="571 5800.0 628.0 647.8 0.0"    # Warpweaver - Runeweaver Square
    ["190011"]="571 5808.0 620.0 647.8 1.57"   # Ethereal Warpweaver - Runeweaver Square
    ["300000"]="571 5796.0 632.0 647.8 4.71"   # Cromi - Runeweaver Square
)

declare -A SHATTRATH=(
    ["999991"]="530 -1838.0 5301.0 -12.4 3.14" # Arena Battlemaster - Lower City
    ["290011"]="530 -1842.0 5297.0 -12.4 0.0"  # Ling - Lower City
)

usage() {
    echo -e "${BLUE}AzerothCore Custom NPC Spawn Script${NC}"
    echo -e "${YELLOW}Usage: $0 [location]${NC}"
    echo ""
    echo "Available locations:"
    echo "  stormwind  - Spawn Alliance-focused NPCs in Stormwind"
    echo "  orgrimmar  - Spawn Horde-focused NPCs in Orgrimmar"
    echo "  dalaran    - Spawn magical service NPCs in Dalaran"
    echo "  shattrath  - Spawn specialized NPCs in Shattrath"
    echo "  all        - Spawn all NPCs in their recommended locations"
    echo ""
    echo "Examples:"
    echo "  $0 stormwind"
    echo "  $0 all"
}

generate_commands() {
    local location=$1
    local commands_file="/tmp/npc_spawn_commands.txt"

    > "$commands_file"

    case $location in
        "stormwind")
            echo -e "${GREEN}Generating Stormwind NPC spawn commands...${NC}"
            for entry in "${!STORMWIND[@]}"; do
                coords="${STORMWIND[$entry]}"
                npc_info="${NPCS[$entry]}"
                name=$(echo "$npc_info" | cut -d'|' -f1)
                title=$(echo "$npc_info" | cut -d'|' -f2)
                echo ".go xyz $coords" >> "$commands_file"
                echo ".npc add $entry" >> "$commands_file"
                echo ".npc set face" >> "$commands_file"
                echo "# Spawned $name ($title) at Stormwind Trade District" >> "$commands_file"
                echo "" >> "$commands_file"
            done
            ;;
        "orgrimmar")
            echo -e "${GREEN}Generating Orgrimmar NPC spawn commands...${NC}"
            for entry in "${!ORGRIMMAR[@]}"; do
                coords="${ORGRIMMAR[$entry]}"
                npc_info="${NPCS[$entry]}"
                name=$(echo "$npc_info" | cut -d'|' -f1)
                title=$(echo "$npc_info" | cut -d'|' -f2)
                echo ".go xyz $coords" >> "$commands_file"
                echo ".npc add $entry" >> "$commands_file"
                echo ".npc set face" >> "$commands_file"
                echo "# Spawned $name ($title) at Orgrimmar Valley of Strength" >> "$commands_file"
                echo "" >> "$commands_file"
            done
            ;;
        "dalaran")
            echo -e "${GREEN}Generating Dalaran NPC spawn commands...${NC}"
            for entry in "${!DALARAN[@]}"; do
                coords="${DALARAN[$entry]}"
                npc_info="${NPCS[$entry]}"
                name=$(echo "$npc_info" | cut -d'|' -f1)
                title=$(echo "$npc_info" | cut -d'|' -f2)
                echo ".go xyz $coords" >> "$commands_file"
                echo ".npc add $entry" >> "$commands_file"
                echo ".npc set face" >> "$commands_file"
                echo "# Spawned $name ($title) at Dalaran Runeweaver Square" >> "$commands_file"
                echo "" >> "$commands_file"
            done
            ;;
        "shattrath")
            echo -e "${GREEN}Generating Shattrath NPC spawn commands...${NC}"
            for entry in "${!SHATTRATH[@]}"; do
                coords="${SHATTRATH[$entry]}"
                npc_info="${NPCS[$entry]}"
                name=$(echo "$npc_info" | cut -d'|' -f1)
                title=$(echo "$npc_info" | cut -d'|' -f2)
                echo ".go xyz $coords" >> "$commands_file"
                echo ".npc add $entry" >> "$commands_file"
                echo ".npc set face" >> "$commands_file"
                echo "# Spawned $name ($title) at Shattrath Lower City" >> "$commands_file"
                echo "" >> "$commands_file"
            done
            ;;
        "all")
            echo -e "${GREEN}Generating ALL NPC spawn commands...${NC}"
            generate_commands "stormwind"
            generate_commands "orgrimmar"
            generate_commands "dalaran"
            generate_commands "shattrath"
            return
            ;;
        *)
            echo -e "${RED}Invalid location: $location${NC}"
            usage
            exit 1
            ;;
    esac

    echo -e "${YELLOW}Commands generated in: $commands_file${NC}"
    echo ""
    echo -e "${BLUE}To execute these commands:${NC}"
    echo "1. Copy the commands from $commands_file"
    echo "2. Paste them into your GM console in-game"
    echo "3. Or use .server script run if available"
    echo ""
    echo -e "${BLUE}Generated commands for $location:${NC}"
    cat "$commands_file"
}

generate_quick_reference() {
    echo -e "${BLUE}AzerothCore Custom NPCs Quick Reference${NC}"
    echo ""
    printf "%-10s %-25s %-20s %-15s\n" "Entry ID" "NPC Name" "Function" "Spawn Command"
    echo "--------------------------------------------------------------------------------"

    for entry in $(echo "${!NPCS[@]}" | tr ' ' '\n' | sort -n); do
        npc_info="${NPCS[$entry]}"
        name=$(echo "$npc_info" | cut -d'|' -f1)
        title=$(echo "$npc_info" | cut -d'|' -f2)
        printf "%-10s %-25s %-20s %-15s\n" "$entry" "$name" "$title" ".npc add $entry"
    done

    echo ""
    echo -e "${YELLOW}Special NPCs requiring specific locations:${NC}"
    echo "- Guild House NPCs (500030, 500031, 500032): Only spawn within guild houses"
    echo "- White Fang (601026): Recommended in hunter areas like Un'Goro or Winterspring"
    echo "- Arena Battlemaster (999991): Best in neutral cities or PvP areas"
    echo ""
    echo -e "${GREEN}All NPCs are level 80, neutral faction, and deletion-protected${NC}"
}

# Main execution
if [[ $# -eq 0 ]]; then
    echo -e "${YELLOW}No location specified. Showing quick reference...${NC}"
    echo ""
    generate_quick_reference
    echo ""
    usage
    exit 0
fi

case $1 in
    "-h"|"--help"|"help")
        usage
        exit 0
        ;;
    "reference"|"ref"|"list")
        generate_quick_reference
        exit 0
        ;;
    *)
        generate_commands "$1"
        ;;
esac

echo ""
echo -e "${GREEN}Script completed successfully!${NC}"
echo -e "${BLUE}Remember to save spawned NPCs to database using appropriate GM commands${NC}"
#!/bin/bash

# ==============================================
# Playerbots Toggle Script
# ==============================================
# Simple script to enable/disable playerbots without rebuilding

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    esac
}

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

ENV_FILE="docker-compose-azerothcore-services.env"

if [ ! -f "$ENV_FILE" ]; then
    print_status "ERROR" "Environment file not found: $ENV_FILE"
    exit 1
fi

# Check current state
current_state=$(grep "^MODULE_PLAYERBOTS=" "$ENV_FILE" | cut -d'=' -f2)
current_authserver=$(grep "^AC_AUTHSERVER_IMAGE=" "$ENV_FILE" | cut -d'=' -f2)

if [[ "$current_authserver" == *"playerbots"* ]]; then
    is_playerbots_active=true
else
    is_playerbots_active=false
fi

print_status "INFO" "CURRENT PLAYERBOTS STATUS"
echo "Module Setting: MODULE_PLAYERBOTS=$current_state"
echo "Active Images: $(if $is_playerbots_active; then echo "Playerbots"; else echo "Standard AzerothCore"; fi)"
echo ""

if [ "$1" = "status" ]; then
    exit 0
fi

# Toggle logic
if $is_playerbots_active; then
    print_status "WARNING" "Disabling playerbots (switching to standard AzerothCore images)"

    # Switch to standard images
    sed -i.bak \
        -e 's/^AC_AUTHSERVER_IMAGE=uprightbass360.*/AC_AUTHSERVER_IMAGE=acore\/ac-wotlk-authserver:14.0.0-dev/' \
        -e 's/^AC_WORLDSERVER_IMAGE=uprightbass360.*/AC_WORLDSERVER_IMAGE=acore\/ac-wotlk-worldserver:14.0.0-dev/' \
        -e 's/^MODULE_PLAYERBOTS=1/MODULE_PLAYERBOTS=0/' \
        "$ENV_FILE"

    print_status "SUCCESS" "Playerbots disabled"
else
    print_status "INFO" "Enabling playerbots (switching to pre-built playerbots images)"

    # Switch to playerbots images
    sed -i.bak \
        -e 's/^AC_AUTHSERVER_IMAGE=acore.*/AC_AUTHSERVER_IMAGE=uprightbass360\/azerothcore-wotlk-playerbots:authserver-Playerbot/' \
        -e 's/^AC_WORLDSERVER_IMAGE=acore.*/AC_WORLDSERVER_IMAGE=uprightbass360\/azerothcore-wotlk-playerbots:worldserver-Playerbot/' \
        -e 's/^MODULE_PLAYERBOTS=0/MODULE_PLAYERBOTS=1/' \
        "$ENV_FILE"

    print_status "SUCCESS" "Playerbots enabled"
fi

print_status "INFO" "To apply changes, redeploy the services:"
echo "  docker compose --env-file $ENV_FILE -f docker-compose-azerothcore-services.yml up -d"
echo ""
print_status "INFO" "No rebuild required - using pre-built images!"
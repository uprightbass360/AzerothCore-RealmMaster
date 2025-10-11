#!/bin/bash

# ==============================================
# Wait for Client Data and Start World Server
# ==============================================
# This script monitors the client data download and automatically starts
# the world server once the data is ready
# Usage: ./wait-and-start-worldserver.sh

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
        "HEADER")
            echo -e "\n${BLUE}=== ${message} ===${NC}"
            ;;
    esac
}

print_status "HEADER" "WAITING FOR CLIENT DATA AND STARTING WORLD SERVER"

# Check if distrobox-host-exec is available
if ! command -v distrobox-host-exec &> /dev/null; then
    print_status "ERROR" "distrobox-host-exec is not available"
    exit 1
fi

# Check if client-data container exists
if ! distrobox-host-exec podman ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^ac-client-data$"; then
    print_status "ERROR" "ac-client-data container not found"
    print_status "INFO" "Run the deployment script first: ./scripts/deploy-and-check-distrobox.sh"
    exit 1
fi

# Check if client data is already complete
print_status "INFO" "Checking client data status..."
if distrobox-host-exec podman logs ac-client-data 2>&1 | grep -q "Game data setup complete"; then
    print_status "SUCCESS" "Client data already complete!"
else
    # Monitor the download progress
    print_status "INFO" "Client data download in progress..."
    print_status "INFO" "Monitoring progress (Ctrl+C to stop monitoring, script will continue)..."

    LAST_LINE=""
    CHECK_COUNT=0

    while true; do
        # Check if container is still running or has completed
        CONTAINER_STATUS=$(distrobox-host-exec podman ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep "^ac-client-data" | awk '{print $2}')

        if [[ "$CONTAINER_STATUS" == "Exited" ]]; then
            # Container finished, check if successful
            EXIT_CODE=$(distrobox-host-exec podman inspect ac-client-data --format='{{.State.ExitCode}}' 2>/dev/null)

            if [ "$EXIT_CODE" = "0" ]; then
                print_status "SUCCESS" "Client data download and extraction completed!"
                break
            else
                print_status "ERROR" "Client data container failed with exit code $EXIT_CODE"
                print_status "INFO" "Check logs: distrobox-host-exec podman logs ac-client-data"
                exit 1
            fi
        fi

        # Show progress every 30 seconds
        if [ $((CHECK_COUNT % 6)) -eq 0 ]; then
            # Get latest progress line
            CURRENT_LINE=$(distrobox-host-exec podman logs --tail 5 ac-client-data 2>&1 | grep -E "(📊|📂|📁|✅|🎉)" | tail -1)

            if [ "$CURRENT_LINE" != "$LAST_LINE" ] && [ -n "$CURRENT_LINE" ]; then
                echo "$CURRENT_LINE"
                LAST_LINE="$CURRENT_LINE"
            fi
        fi

        ((CHECK_COUNT++))
        sleep 5
    done
fi

# Verify data directories exist
print_status "INFO" "Verifying client data directories..."
DATA_DIRS=("maps" "vmaps" "mmaps" "dbc")
MISSING_DIRS=()

for dir in "${DATA_DIRS[@]}"; do
    if [ -d "storage/azerothcore/data/$dir" ] && [ -n "$(ls -A storage/azerothcore/data/$dir 2>/dev/null)" ]; then
        DIR_SIZE=$(du -sh storage/azerothcore/data/$dir 2>/dev/null | cut -f1)
        print_status "SUCCESS" "$dir directory exists ($DIR_SIZE)"
    else
        print_status "ERROR" "$dir directory missing or empty"
        MISSING_DIRS+=("$dir")
    fi
done

if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
    print_status "ERROR" "Cannot start world server - missing data directories"
    exit 1
fi

# Check if world server is already running
if distrobox-host-exec podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^ac-worldserver$"; then
    print_status "WARNING" "World server is already running"
    print_status "INFO" "To restart: distrobox-host-exec podman restart ac-worldserver"
    exit 0
fi

# Remove any stopped world server container
distrobox-host-exec podman rm -f ac-worldserver 2>/dev/null || true

# Start the world server
print_status "INFO" "Starting World Server..."
distrobox-host-exec bash -c "podman run -d --name ac-worldserver --network azerothcore --privileged -t \
    -p 8215:8085 -p 7778:7878 \
    -e AC_LOGIN_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_auth' \
    -e AC_WORLD_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_world' \
    -e AC_CHARACTER_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_characters' \
    -e AC_UPDATES_ENABLE_DATABASES=0 \
    -e AC_BIND_IP='0.0.0.0' \
    -e AC_DATA_DIR='/azerothcore/data' \
    -e AC_SOAP_PORT=7878 \
    -e AC_PROCESS_PRIORITY=0 \
    -e PLAYERBOT_ENABLED=1 \
    -e PLAYERBOT_MAX_BOTS=40 \
    -e AC_LOG_LEVEL=2 \
    -v ./storage/azerothcore/data:/azerothcore/data \
    -v ./storage/azerothcore/config:/azerothcore/env/dist/etc \
    -v ./storage/azerothcore/logs:/azerothcore/logs \
    -v ./storage/azerothcore/modules:/azerothcore/modules \
    -v ./storage/azerothcore/lua_scripts:/azerothcore/lua_scripts \
    --cap-add SYS_NICE \
    --restart unless-stopped \
    docker.io/acore/ac-wotlk-worldserver:14.0.0-dev" 2>&1 | grep -v "level=error.*graph driver"

print_status "INFO" "Waiting for world server to start..."
sleep 10

# Check if world server is running
if distrobox-host-exec podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^ac-worldserver$"; then
    print_status "SUCCESS" "World server started successfully!"

    # Show initial logs
    print_status "INFO" "Initial world server logs:"
    distrobox-host-exec podman logs --tail 15 ac-worldserver 2>&1 | grep -v "level=error.*graph driver" || true

    print_status "HEADER" "WORLD SERVER STATUS"
    print_status "SUCCESS" "🎮 World Server: Running on port 8215"
    print_status "SUCCESS" "🔧 SOAP API: Available on port 7778"
    print_status "INFO" "Monitor logs: distrobox-host-exec podman logs -f ac-worldserver"
    print_status "INFO" "Connect with WoW client: Set realmlist to 127.0.0.1:8215"
else
    print_status "ERROR" "World server failed to start"
    print_status "INFO" "Check logs: distrobox-host-exec podman logs ac-worldserver"
    exit 1
fi

print_status "SUCCESS" "🎉 AzerothCore is now fully operational!"

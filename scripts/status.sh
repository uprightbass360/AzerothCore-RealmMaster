#!/bin/bash

# ==============================================
# AzerothCore Service Status Script
# ==============================================
# This script displays the current status of all AzerothCore services
# Usage: ./status.sh [--watch] [--logs]

set -e

# Change to the project root directory (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Options
WATCH_MODE=false
SHOW_LOGS=false
LOG_LINES=5

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch|-w)
            WATCH_MODE=true
            shift
            ;;
        --logs|-l)
            SHOW_LOGS=true
            shift
            ;;
        --lines)
            LOG_LINES="$2"
            shift 2
            ;;
        -h|--help)
            echo "AzerothCore Service Status Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --watch, -w    Watch mode - continuously update status"
            echo "  --logs, -l     Show recent log entries for each service"
            echo "  --lines N      Number of log lines to show (default: 5)"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0              Show current status"
            echo "  $0 --watch      Continuously monitor status"
            echo "  $0 --logs       Show status with recent logs"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print status with color
print_status() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%H:%M:%S')

    case $level in
        "SUCCESS"|"HEALTHY")
            printf "${GREEN}✅ [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
        "WARNING"|"UNHEALTHY")
            printf "${YELLOW}⚠️  [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
        "ERROR"|"FAILED")
            printf "${RED}❌ [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
        "INFO")
            printf "${BLUE}ℹ️  [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
        "HEADER")
            printf "${MAGENTA}🚀 [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
        *)
            printf "${CYAN}📋 [%s] %s${NC}\n" "$timestamp" "$message"
            ;;
    esac
}

# Function to get container status with health
get_container_status() {
    local container_name=$1
    local status=""
    local health=""
    local uptime=""

    if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-health-check")
        uptime=$(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null | xargs -I {} date -d {} '+%H:%M:%S' 2>/dev/null || echo "unknown")

        # Format status with color
        case "$status" in
            "running")
                if [ "$health" = "healthy" ]; then
                    printf "${GREEN}●${NC} Running (healthy) - Started: %s\n" "$uptime"
                elif [ "$health" = "unhealthy" ]; then
                    printf "${RED}●${NC} Running (unhealthy) - Started: %s\n" "$uptime"
                elif [ "$health" = "starting" ]; then
                    printf "${YELLOW}●${NC} Running (starting) - Started: %s\n" "$uptime"
                else
                    printf "${GREEN}●${NC} Running - Started: %s\n" "$uptime"
                fi
                ;;
            "exited")
                local exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container_name" 2>/dev/null || echo "unknown")
                if [ "$exit_code" = "0" ]; then
                    printf "${YELLOW}●${NC} Exited (0) - Completed successfully\n"
                else
                    printf "${RED}●${NC} Exited (%s) - Failed\n" "$exit_code"
                fi
                ;;
            "restarting")
                printf "${YELLOW}●${NC} Restarting - Started: %s\n" "$uptime"
                ;;
            "paused")
                printf "${YELLOW}●${NC} Paused - Started: %s\n" "$uptime"
                ;;
            "created")
                printf "${CYAN}●${NC} Created (not started)\n"
                ;;
            *)
                printf "${RED}●${NC} %s\n" "$status"
                ;;
        esac
    else
        printf "${RED}●${NC} Not found\n"
    fi
}

# Function to show service logs
show_service_logs() {
    local container_name=$1
    local service_display_name=$2

    if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        printf "    ${CYAN}📄 Recent logs:${NC}\n"
        docker logs "$container_name" --tail "$LOG_LINES" 2>/dev/null | sed 's/^/      /' || printf "      ${YELLOW}(no logs available)${NC}\n"
        echo ""
    fi
}

# Function to display service status
display_service_status() {
    local container_name=$1
    local service_display_name=$2
    local description=$3

    printf "${CYAN}%-20s${NC} " "$service_display_name"
    get_container_status "$container_name"

    if [ "$SHOW_LOGS" = true ]; then
        show_service_logs "$container_name" "$service_display_name"
    fi
}

# Function to get database info
get_database_info() {
    if docker ps --format "table {{.Names}}" | grep -q "^ac-mysql$"; then
        local db_count=$(docker exec ac-mysql mysql -u root -pazerothcore123 -e "SHOW DATABASES;" 2>/dev/null | grep -E "^(acore_|mysql|information_schema|performance_schema)" | wc -l || echo "0")
        local user_count=$(docker exec ac-mysql mysql -u root -pazerothcore123 -D acore_auth -e "SELECT COUNT(*) FROM account;" 2>/dev/null | tail -1 || echo "0")
        printf "    ${CYAN}📊 Databases: $db_count | User accounts: $user_count${NC}\n"
    fi
}

# Function to get client data progress
get_client_data_progress() {
    if docker ps --format "table {{.Names}}" | grep -q "^ac-client-data$"; then
        local last_progress=$(docker logs ac-client-data --tail 1 2>/dev/null | grep "Progress" || echo "")
        if [ -n "$last_progress" ]; then
            printf "    ${CYAN}📊 $last_progress${NC}\n"
        fi
    fi
}

# Main status display function
show_status() {
    clear 2>/dev/null || true
    print_status "HEADER" "AZEROTHCORE SERVICE STATUS"
    echo ""

    # Database Layer
    printf "${MAGENTA}=== DATABASE LAYER ===${NC}\n"
    display_service_status "ac-mysql" "MySQL Database" "Core database server"
    if docker ps --format "table {{.Names}}" | grep -q "^ac-mysql$"; then
        get_database_info
    fi
    display_service_status "ac-backup" "Backup Service" "Database backup automation"
    display_service_status "ac-db-init" "DB Initializer" "Database initialization (one-time)"
    display_service_status "ac-db-import" "DB Import" "Database import (one-time)"
    echo ""

    # Services Layer
    printf "${MAGENTA}=== SERVICES LAYER ===${NC}\n"
    display_service_status "ac-authserver" "Auth Server" "Player authentication"
    display_service_status "ac-worldserver" "World Server" "Game world simulation"
    display_service_status "ac-client-data" "Client Data" "Game data download/extraction"
    if docker ps --format "table {{.Names}}" | grep -q "^ac-client-data$"; then
        get_client_data_progress
    fi
    echo ""

    # Support Services
    printf "${MAGENTA}=== SUPPORT SERVICES ===${NC}\n"
    display_service_status "ac-modules" "Module Manager" "Server module management"
    display_service_status "ac-eluna" "Eluna Engine" "Lua scripting engine"
    display_service_status "ac-post-install" "Post-Install" "Configuration automation"
    echo ""

    # Network and ports
    printf "${MAGENTA}=== NETWORK STATUS ===${NC}\n"
    if docker network ls | grep -q azerothcore; then
        printf "${CYAN}%-20s${NC} ${GREEN}●${NC} Network 'azerothcore' exists\n" "Docker Network"
    else
        printf "${CYAN}%-20s${NC} ${RED}●${NC} Network 'azerothcore' missing\n" "Docker Network"
    fi

    # Check if auth server port is accessible
    if docker ps --format "table {{.Names}}\t{{.Ports}}" | grep ac-authserver | grep -q "3784"; then
        printf "${CYAN}%-20s${NC} ${GREEN}●${NC} Port 3784 (Auth) exposed\n" "Auth Port"
    else
        printf "${CYAN}%-20s${NC} ${RED}●${NC} Port 3784 (Auth) not exposed\n" "Auth Port"
    fi

    # Check if world server port is accessible
    if docker ps --format "table {{.Names}}\t{{.Ports}}" | grep ac-worldserver | grep -q "8215"; then
        printf "${CYAN}%-20s${NC} ${GREEN}●${NC} Port 8215 (World) exposed\n" "World Port"
    else
        printf "${CYAN}%-20s${NC} ${RED}●${NC} Port 8215 (World) not exposed\n" "World Port"
    fi

    echo ""
    printf "${CYAN}Last updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"

    if [ "$WATCH_MODE" = true ]; then
        echo ""
        print_status "INFO" "Press Ctrl+C to exit watch mode"
    fi
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
    while true; do
        show_status
        sleep 3
    done
else
    show_status
fi
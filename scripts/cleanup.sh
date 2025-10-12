#!/bin/bash

# ==============================================
# AzerothCore Docker Cleanup Script
# ==============================================
# This script provides various levels of cleanup for AzerothCore Docker resources
# Usage: ./cleanup.sh [--soft] [--hard] [--nuclear] [--dry-run]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script options
CLEANUP_LEVEL=""
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --soft)
            CLEANUP_LEVEL="soft"
            shift
            ;;
        --hard)
            CLEANUP_LEVEL="hard"
            shift
            ;;
        --nuclear)
            CLEANUP_LEVEL="nuclear"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "AzerothCore Docker Cleanup Script"
            echo ""
            echo "Usage: $0 [CLEANUP_LEVEL] [OPTIONS]"
            echo ""
            echo "CLEANUP LEVELS:"
            echo "  --soft      Stop containers only (preserves data)"
            echo "  --hard      Stop containers + remove containers + networks (preserves volumes/data)"
            echo "  --nuclear   Complete removal: containers + networks + volumes + images (DESTROYS ALL DATA)"
            echo ""
            echo "OPTIONS:"
            echo "  --dry-run   Show what would be done without actually doing it"
            echo "  --force     Skip confirmation prompts"
            echo "  --help      Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0 --soft                    # Stop all containers"
            echo "  $0 --hard --dry-run          # Show what hard cleanup would do"
            echo "  $0 --nuclear --force         # Complete removal without prompts"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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
        "DANGER")
            echo -e "${RED}💀 ${message}${NC}"
            ;;
        "HEADER")
            echo -e "\n${MAGENTA}=== ${message} ===${NC}"
            ;;
    esac
}

# Function to execute command with dry-run support
execute_command() {
    local description=$1
    local command=$2

    if [ "$DRY_RUN" = true ]; then
        print_status "INFO" "[DRY RUN] Would execute: $description"
        echo "  Command: $command"
    else
        print_status "INFO" "Executing: $description"
        if eval "$command"; then
            print_status "SUCCESS" "Completed: $description"
        else
            print_status "WARNING" "Failed or no action needed: $description"
        fi
    fi
}

# Function to get confirmation
get_confirmation() {
    local message=$1

    if [ "$FORCE" = true ]; then
        print_status "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi

    echo -e "${YELLOW}⚠️  ${message}${NC}"
    read -p "Are you sure? (yes/no): " response
    case $response in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            print_status "INFO" "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Function to show current resources
show_current_resources() {
    print_status "HEADER" "CURRENT AZEROTHCORE RESOURCES"

    echo -e "${BLUE}Containers:${NC}"
    if docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "ac-|acore" | head -20; then
        echo ""
    else
        echo "  No AzerothCore containers found"
    fi

    echo -e "${BLUE}Networks:${NC}"
    if docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep -E "azerothcore|acore"; then
        echo ""
    else
        echo "  No AzerothCore networks found"
    fi

    echo -e "${BLUE}Volumes:${NC}"
    if docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep -E "ac_|acore|azerothcore"; then
        echo ""
    else
        echo "  No AzerothCore volumes found"
    fi

    echo -e "${BLUE}Images:${NC}"
    if docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "acore|azerothcore|phpmyadmin|keira3|uprightbass360.*playerbots" | head -10; then
        echo ""
    else
        echo "  No AzerothCore-related images found"
    fi
}

# Function to perform soft cleanup
soft_cleanup() {
    print_status "HEADER" "SOFT CLEANUP - STOPPING CONTAINERS"

    get_confirmation "This will stop all AzerothCore containers but preserve all data."

    # Stop modules layer (if exists)
    execute_command "Stop modules layer" \
        "docker compose --env-file docker-compose-azerothcore-modules-custom.env -f docker-compose-azerothcore-modules.yml down 2>/dev/null || docker compose --env-file docker-compose-azerothcore-modules.env -f docker-compose-azerothcore-modules.yml down 2>/dev/null || true"

    # Stop tools layer (if exists)
    execute_command "Stop tools layer" \
        "docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml down 2>/dev/null || docker compose --env-file docker-compose-azerothcore-tools.env -f docker-compose-azerothcore-tools.yml down 2>/dev/null || true"

    # Stop services layer
    execute_command "Stop services layer" \
        "docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml down 2>/dev/null || docker compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml down"

    # Stop database layer
    execute_command "Stop database layer" \
        "docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml down 2>/dev/null || docker compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml down"

    print_status "SUCCESS" "Soft cleanup completed - all containers stopped"
    print_status "INFO" "Data volumes and images are preserved"
    print_status "INFO" "Use deployment script to restart services"
}

# Function to perform hard cleanup
hard_cleanup() {
    print_status "HEADER" "HARD CLEANUP - REMOVING CONTAINERS AND NETWORKS"

    get_confirmation "This will remove all containers and networks but preserve data volumes and images."

    # Remove containers and networks
    execute_command "Remove modules layer (containers + networks)" \
        "docker compose --env-file docker-compose-azerothcore-modules-custom.env -f docker-compose-azerothcore-modules.yml down --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-modules.env -f docker-compose-azerothcore-modules.yml down --remove-orphans 2>/dev/null || true"

    execute_command "Remove tools layer (containers + networks)" \
        "docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml down --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-tools.env -f docker-compose-azerothcore-tools.yml down --remove-orphans 2>/dev/null || true"

    execute_command "Remove services layer (containers + networks)" \
        "docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml down --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml down --remove-orphans"

    execute_command "Remove database layer (containers + networks)" \
        "docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml down --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml down --remove-orphans"

    # Clean up any remaining AzerothCore containers
    execute_command "Remove any remaining AzerothCore containers" \
        "docker ps -a --format '{{.Names}}' | grep -E '^ac-' | xargs -r docker rm -f"

    # Clean up AzerothCore networks
    execute_command "Remove AzerothCore networks" \
        "docker network ls --format '{{.Name}}' | grep -E 'azerothcore|acore' | xargs -r docker network rm"

    print_status "SUCCESS" "Hard cleanup completed - containers and networks removed"
    print_status "INFO" "Data volumes and images are preserved"
    print_status "INFO" "Run full deployment script to recreate the stack"
}

# Function to perform nuclear cleanup
nuclear_cleanup() {
    print_status "HEADER" "NUCLEAR CLEANUP - COMPLETE REMOVAL"
    print_status "DANGER" "THIS WILL DESTROY ALL DATA AND REMOVE EVERYTHING!"

    get_confirmation "This will permanently delete ALL AzerothCore data, containers, networks, volumes, and images. This action CANNOT be undone!"

    # Stop and remove everything
    execute_command "Stop and remove modules layer (with volumes)" \
        "docker compose --env-file docker-compose-azerothcore-modules-custom.env -f docker-compose-azerothcore-modules.yml down --volumes --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-modules.env -f docker-compose-azerothcore-modules.yml down --volumes --remove-orphans 2>/dev/null || true"

    execute_command "Stop and remove tools layer (with volumes)" \
        "docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml down --volumes --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-tools.env -f docker-compose-azerothcore-tools.yml down --volumes --remove-orphans 2>/dev/null || true"

    execute_command "Stop and remove services layer (with volumes)" \
        "docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml down --volumes --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml down --volumes --remove-orphans"

    execute_command "Stop and remove database layer (with volumes)" \
        "docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml down --volumes --remove-orphans 2>/dev/null || docker compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml down --volumes --remove-orphans"

    # Remove any remaining containers
    execute_command "Remove any remaining AzerothCore containers" \
        "docker ps -a --format '{{.Names}}' | grep -E '^ac-|acore' | xargs -r docker rm -f"

    # Remove networks
    execute_command "Remove AzerothCore networks" \
        "docker network ls --format '{{.Name}}' | grep -E 'azerothcore|acore' | xargs -r docker network rm"

    # Remove volumes
    execute_command "Remove AzerothCore volumes" \
        "docker volume ls --format '{{.Name}}' | grep -E '^ac_|acore|azerothcore' | xargs -r docker volume rm"

    # Remove images
    execute_command "Remove AzerothCore server images" \
        "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^acore/' | xargs -r docker rmi"

    execute_command "Remove mod-playerbots images" \
        "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^uprightbass360/azerothcore-wotlk-playerbots' | xargs -r docker rmi"

    execute_command "Remove related tool images" \
        "docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'phpmyadmin|uprightbass360/keira3' | xargs -r docker rmi"

    # Clean up local data directories
    execute_command "Remove local storage directories" \
        "sudo rm -rf ./storage ./backups 2>/dev/null || rm -rf ./storage ./backups 2>/dev/null || true"

    # System cleanup
    execute_command "Clean up unused Docker resources" \
        "docker system prune -af --volumes"

    print_status "SUCCESS" "Nuclear cleanup completed - everything removed"
    print_status "DANGER" "ALL AZEROTHCORE DATA HAS BEEN PERMANENTLY DELETED"
    print_status "INFO" "Run full deployment script to start fresh"
}

# Function to show cleanup summary
show_cleanup_summary() {
    local level=$1

    print_status "HEADER" "CLEANUP SUMMARY"

    case $level in
        "soft")
            echo -e "${GREEN}✅ Containers: Stopped${NC}"
            echo -e "${BLUE}ℹ️  Networks: Preserved${NC}"
            echo -e "${BLUE}ℹ️  Volumes: Preserved (data safe)${NC}"
            echo -e "${BLUE}ℹ️  Images: Preserved${NC}"
            echo ""
            echo -e "${GREEN}Next steps:${NC}"
            echo "  • To restart: cd scripts && ./deploy-and-check.sh --skip-deploy"
            echo "  • To deploy fresh: cd scripts && ./deploy-and-check.sh"
            ;;
        "hard")
            echo -e "${GREEN}✅ Containers: Removed${NC}"
            echo -e "${GREEN}✅ Networks: Removed${NC}"
            echo -e "${BLUE}ℹ️  Volumes: Preserved (data safe)${NC}"
            echo -e "${BLUE}ℹ️  Images: Preserved${NC}"
            echo ""
            echo -e "${GREEN}Next steps:${NC}"
            echo "  • To deploy: cd scripts && ./deploy-and-check.sh"
            ;;
        "nuclear")
            echo -e "${RED}💀 Containers: DESTROYED${NC}"
            echo -e "${RED}💀 Networks: DESTROYED${NC}"
            echo -e "${RED}💀 Volumes: DESTROYED${NC}"
            echo -e "${RED}💀 Images: DESTROYED${NC}"
            echo -e "${RED}💀 Data: PERMANENTLY DELETED${NC}"
            echo ""
            echo -e "${YELLOW}Next steps:${NC}"
            echo "  • To start fresh: cd scripts && ./deploy-and-check.sh"
            echo "  • This will re-download ~15GB of client data"
            ;;
    esac
}

# Main execution
main() {
    print_status "HEADER" "AZEROTHCORE CLEANUP SCRIPT"

    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        print_status "ERROR" "Docker is not installed or not in PATH"
        exit 1
    fi

    # Show help if no cleanup level specified
    if [ -z "$CLEANUP_LEVEL" ]; then
        echo "Please specify a cleanup level:"
        echo "  --soft      Stop containers only (safe)"
        echo "  --hard      Remove containers + networks (preserves data)"
        echo "  --nuclear   Complete removal (DESTROYS ALL DATA)"
        echo ""
        echo "Use --help for more information"
        exit 1
    fi

    # Show current resources
    show_current_resources

    # Execute cleanup based on level
    case $CLEANUP_LEVEL in
        "soft")
            soft_cleanup
            ;;
        "hard")
            hard_cleanup
            ;;
        "nuclear")
            nuclear_cleanup
            ;;
    esac

    # Show final summary
    show_cleanup_summary "$CLEANUP_LEVEL"

    print_status "SUCCESS" "🧹 Cleanup completed successfully!"
}

# Run main function
main "$@"
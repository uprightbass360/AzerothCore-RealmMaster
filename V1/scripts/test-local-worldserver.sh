#!/bin/bash

# ==============================================
# TEST LOCAL WORLDSERVER DEPLOYMENT SCRIPT
# ==============================================
# This script tests worldserver performance with local game files
# vs. external volume mount

set -e  # Exit on any error

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
        "TEST")
            echo -e "${YELLOW}🧪 ${message}${NC}"
            ;;
    esac
}

# Parse command line arguments
CLEANUP=false
LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --logs)
            LOGS=true
            shift
            ;;
        -h|--help)
            echo "Test Local Worldserver Deployment Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --cleanup   Stop and remove test worldserver"
            echo "  --logs      Follow test worldserver logs"
            echo "  --help      Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                    # Deploy test worldserver"
            echo "  $0 --logs             # Follow logs of running test"
            echo "  $0 --cleanup          # Clean up test deployment"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Change to parent directory for compose commands
cd "$(dirname "$0")/.."

if [ "$CLEANUP" = true ]; then
    print_status "HEADER" "CLEANING UP TEST WORLDSERVER"

    print_status "INFO" "Stopping test worldserver..."
    docker-compose --env-file docker-compose-test-worldserver.env -f docker-compose-test-worldserver.yml down

    print_status "INFO" "Removing test container if exists..."
    docker rm -f ac-worldserver-test 2>/dev/null || true

    print_status "SUCCESS" "Test cleanup completed"
    exit 0
fi

if [ "$LOGS" = true ]; then
    print_status "HEADER" "FOLLOWING TEST WORLDSERVER LOGS"
    docker logs ac-worldserver-test -f
    exit 0
fi

# Main deployment
print_status "HEADER" "DEPLOYING TEST WORLDSERVER WITH LOCAL GAME FILES"

# Check if docker is available
if ! command -v docker &> /dev/null; then
    print_status "ERROR" "Docker is not installed or not in PATH"
    exit 1
fi

# Check if main database is running
if ! docker ps | grep ac-mysql > /dev/null; then
    print_status "ERROR" "Main database (ac-mysql) is not running"
    print_status "INFO" "Please start the database layer first:"
    print_status "INFO" "  docker-compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml up -d"
    exit 1
fi

# Check if authserver is running
if ! docker ps | grep ac-authserver > /dev/null; then
    print_status "ERROR" "Auth server (ac-authserver) is not running"
    print_status "INFO" "Please start the services layer first (or at least authserver):"
    print_status "INFO" "  docker-compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml up -d ac-authserver"
    exit 1
fi

# Check if regular worldserver is running (warn about port conflicts)
if docker ps | grep ac-worldserver | grep -v test > /dev/null; then
    print_status "WARNING" "Regular worldserver is running - test uses different ports"
    print_status "INFO" "Test worldserver ports: 8216 (world), 7779 (SOAP)"
    print_status "INFO" "Regular worldserver ports: 8215 (world), 7778 (SOAP)"
fi

print_status "INFO" "Prerequisites check passed"

# Check for cached files
if [ -f "storage/azerothcore/cache-test/client-data-version.txt" ]; then
    CACHED_VERSION=$(cat storage/azerothcore/cache-test/client-data-version.txt 2>/dev/null)
    print_status "INFO" "Found cached game files (version: $CACHED_VERSION)"
    print_status "SUCCESS" "No internet download needed - using cached files!"
    print_status "INFO" "Expected startup time: 5-10 minutes (extraction only)"
else
    print_status "WARNING" "No cached files found - will download ~15GB from internet"
    print_status "INFO" "Expected startup time: 20-30 minutes (download + extraction)"
fi

# Start test worldserver
print_status "TEST" "Starting test worldserver with cached local game files..."
print_status "INFO" "Cache location: storage/azerothcore/cache-test/"
print_status "INFO" "Game files will be copied to local container storage for performance testing"
print_status "INFO" "Test worldserver will be available on port 8216"

# Record start time
START_TIME=$(date +%s)
print_status "INFO" "Deployment started at: $(date)"

# Start the test container
docker-compose --env-file docker-compose-test-worldserver.env -f docker-compose-test-worldserver.yml up -d

print_status "SUCCESS" "Test worldserver container started"
print_status "INFO" "Container name: ac-worldserver-test"

print_status "HEADER" "MONITORING TEST DEPLOYMENT"

print_status "INFO" "Following logs for the first few minutes..."
print_status "INFO" "Press Ctrl+C to stop following logs (container will continue running)"
print_status "INFO" ""
print_status "TEST" "=== LIVE LOG OUTPUT ==="

# Follow logs for a bit
timeout 300 docker logs ac-worldserver-test -f 2>/dev/null || true

print_status "INFO" ""
print_status "HEADER" "TEST DEPLOYMENT STATUS"

# Check if container is still running
if docker ps | grep ac-worldserver-test > /dev/null; then
    print_status "SUCCESS" "Test container is running"

    # Calculate elapsed time
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))

    print_status "INFO" "Elapsed time: ${ELAPSED_MIN} minutes"
    print_status "INFO" "Container status: $(docker ps --format '{{.Status}}' --filter name=ac-worldserver-test)"

    print_status "HEADER" "USEFUL COMMANDS"
    echo -e "${BLUE}Monitor logs:${NC}"
    echo "  $0 --logs"
    echo "  docker logs ac-worldserver-test -f"
    echo ""
    echo -e "${BLUE}Check container status:${NC}"
    echo "  docker ps | grep test"
    echo "  docker exec ac-worldserver-test ps aux | grep worldserver"
    echo ""
    echo -e "${BLUE}Check game data (local in container):${NC}"
    echo "  docker exec ac-worldserver-test ls -la /azerothcore/data/"
    echo "  docker exec ac-worldserver-test du -sh /azerothcore/data/*"
    echo ""
    echo -e "${BLUE}Check cached files (persistent):${NC}"
    echo "  ls -la storage/azerothcore/cache-test/"
    echo "  du -sh storage/azerothcore/cache-test/*"
    echo "  cat storage/azerothcore/cache-test/client-data-version.txt"
    echo ""
    echo -e "${BLUE}Connect to test server:${NC}"
    echo "  Game Port: localhost:8216"
    echo "  SOAP Port: localhost:7779"
    echo ""
    echo -e "${BLUE}Performance comparison:${NC}"
    echo "  docker stats ac-worldserver ac-worldserver-test --no-stream"
    echo ""
    echo -e "${BLUE}Cleanup test:${NC}"
    echo "  $0 --cleanup"
    echo "  rm -rf storage/azerothcore/cache-test/  # Remove cache"

else
    print_status "ERROR" "Test container has stopped or failed"
    print_status "INFO" "Check logs for details:"
    print_status "INFO" "  docker logs ac-worldserver-test"
    exit 1
fi
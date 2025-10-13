#!/bin/bash

# ==============================================
# AzerothCore Docker Deployment & Health Check Script
# ==============================================
# This script deploys the complete AzerothCore stack and performs comprehensive health checks
# Usage: ./deploy-and-check.sh [--skip-deploy] [--quick-check] [--setup]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script options
SKIP_DEPLOY=false
QUICK_CHECK=false
RUN_SETUP=false
MODULES_ENABLED=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --quick-check)
            QUICK_CHECK=true
            shift
            ;;
        --setup)
            RUN_SETUP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-deploy] [--quick-check] [--setup]"
            echo "  --skip-deploy    Skip deployment, only run health checks"
            echo "  --quick-check    Run basic health checks only"
            echo "  --setup          Run interactive server setup before deployment"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
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
        "HEADER")
            echo -e "\n${BLUE}=== ${message} ===${NC}"
            ;;
    esac
}

# Function to check if a port is accessible
check_port() {
    local port=$1
    local service_name=$2
    local timeout=${3:-5}

    if timeout $timeout bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
        print_status "SUCCESS" "$service_name (port $port): CONNECTED"
        return 0
    else
        print_status "ERROR" "$service_name (port $port): FAILED"
        return 1
    fi
}

# Function to wait for a service to be ready
wait_for_service() {
    local service_name=$1
    local max_attempts=$2
    local check_command=$3

    print_status "INFO" "Waiting for $service_name to be ready..."

    for i in $(seq 1 $max_attempts); do
        if eval "$check_command" &>/dev/null; then
            print_status "SUCCESS" "$service_name is ready!"
            return 0
        fi

        if [ $i -eq $max_attempts ]; then
            print_status "ERROR" "$service_name failed to start after $max_attempts attempts"
            return 1
        fi

        echo -n "."
        sleep 5
    done
}

# Function to check container health
check_container_health() {
    local container_name=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' $container_name 2>/dev/null || echo "no-health-check")

    if [ "$status" = "healthy" ]; then
        print_status "SUCCESS" "$container_name: healthy"
        return 0
    elif [ "$status" = "no-health-check" ] || [ "$status" = "<no value>" ]; then
        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            print_status "SUCCESS" "$container_name: running (no health check)"
            return 0
        else
            print_status "ERROR" "$container_name: not running"
            return 1
        fi
    else
        print_status "WARNING" "$container_name: $status"
        return 1
    fi
}

# Function to check web service health
check_web_service() {
    local url=$1
    local service_name=$2
    local expected_pattern=$3

    response=$(curl -s --max-time 10 "$url" 2>/dev/null || echo "")

    if [ -n "$expected_pattern" ]; then
        if echo "$response" | grep -q "$expected_pattern"; then
            print_status "SUCCESS" "$service_name: HTTP OK (content verified)"
            return 0
        else
            print_status "ERROR" "$service_name: HTTP OK but content verification failed"
            return 1
        fi
    else
        if [ -n "$response" ]; then
            print_status "SUCCESS" "$service_name: HTTP OK"
            return 0
        else
            print_status "ERROR" "$service_name: HTTP failed"
            return 1
        fi
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_status "HEADER" "DEPLOYING AZEROTHCORE STACK"

    # Check if custom environment files exist first, then fallback to base files
    DB_ENV_FILE="./docker-compose-azerothcore-database-custom.env"
    SERVICES_ENV_FILE="./docker-compose-azerothcore-services-custom.env"
    MODULES_ENV_FILE="./docker-compose-azerothcore-modules-custom.env"
    TOOLS_ENV_FILE="./docker-compose-azerothcore-tools-custom.env"

    # Fallback to base files if custom files don't exist
    if [ ! -f "$DB_ENV_FILE" ]; then
        DB_ENV_FILE="./docker-compose-azerothcore-database.env"
    fi
    if [ ! -f "$SERVICES_ENV_FILE" ]; then
        SERVICES_ENV_FILE="./docker-compose-azerothcore-services.env"
    fi
    if [ ! -f "$MODULES_ENV_FILE" ]; then
        MODULES_ENV_FILE="./docker-compose-azerothcore-modules.env"
    fi
    if [ ! -f "$TOOLS_ENV_FILE" ]; then
        TOOLS_ENV_FILE="./docker-compose-azerothcore-tools.env"
    fi

    # Check if required environment files exist
    for env_file in "$DB_ENV_FILE" "$SERVICES_ENV_FILE" "$TOOLS_ENV_FILE"; do
        if [ ! -f "$env_file" ]; then
            print_status "ERROR" "Environment file $env_file not found"
            print_status "INFO" "Run ./scripts/setup-server.sh first to create environment files"
            exit 1
        fi
    done

    # Check if modules are enabled (set global variable)
    if [ -f "$MODULES_ENV_FILE" ]; then
        MODULES_ENABLED=true
    else
        MODULES_ENABLED=false
    fi

    print_status "INFO" "Step 1: Deploying database layer..."
    docker compose --env-file "$DB_ENV_FILE" -f ./docker-compose-azerothcore-database.yml up -d --remove-orphans

    # Wait for database initialization
    wait_for_service "MySQL" 24 "docker exec ac-mysql mysql -uroot -pazerothcore123 -e 'SELECT 1' >/dev/null 2>&1"

    # Wait for database import
    wait_for_service "Database Import" 36 "docker inspect ac-db-import --format='{{.State.ExitCode}}' 2>/dev/null | grep -q '^0$' || docker logs ac-db-import 2>/dev/null | grep -q 'Database import complete'"

    print_status "INFO" "Step 2: Deploying services layer..."
    docker compose --env-file "$SERVICES_ENV_FILE" -f ./docker-compose-azerothcore-services.yml up -d

    # Wait for client data extraction
    print_status "INFO" "Waiting for client data download and extraction (this may take 10-20 minutes)..."
    wait_for_service "Client Data" 120 "docker logs ac-client-data 2>/dev/null | grep -q 'Game data setup complete'"

    # Wait for worldserver to be healthy
    wait_for_service "World Server" 24 "check_container_health ac-worldserver"

    # Deploy modules if enabled
    if [ "$MODULES_ENABLED" = true ]; then
        print_status "INFO" "Step 3: Deploying modules layer..."
        docker compose --env-file "$MODULES_ENV_FILE" -f ./docker-compose-azerothcore-modules.yml up -d

        # Wait for modules to be ready
        sleep 5

        STEP_NUMBER=4
    else
        print_status "INFO" "Modules layer skipped (no custom modules configuration found)"
        STEP_NUMBER=3
    fi

    print_status "INFO" "Step $STEP_NUMBER: Deploying tools layer..."
    docker compose --env-file "$TOOLS_ENV_FILE" -f ./docker-compose-azerothcore-tools.yml up -d

    # Wait for tools to be ready
    sleep 10

    print_status "SUCCESS" "Deployment completed!"
}

# Function to perform health checks
perform_health_checks() {
    print_status "HEADER" "CONTAINER HEALTH STATUS"

    # Check all containers
    local containers=("ac-mysql" "ac-backup" "ac-authserver" "ac-worldserver" "ac-phpmyadmin" "ac-keira3")

    # Add modules container if modules are enabled
    if [ "$MODULES_ENABLED" = true ]; then
        containers+=("ac-modules")
    fi

    local container_failures=0

    for container in "${containers[@]}"; do
        # Only check containers that actually exist
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            if ! check_container_health "$container"; then
                # Only count as failure if container is not running, not just missing health check
                if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
                    ((container_failures++))
                fi
            fi
        fi
    done

    print_status "HEADER" "PORT CONNECTIVITY TESTS"

    # Database Layer
    print_status "INFO" "Database Layer:"
    local port_failures=0
    if ! check_port 64306 "MySQL"; then ((port_failures++)); fi

    # Services Layer
    print_status "INFO" "Services Layer:"
    if ! check_port 3784 "Auth Server"; then ((port_failures++)); fi
    if ! check_port 8215 "World Server"; then ((port_failures++)); fi
    if ! check_port 7778 "SOAP API"; then ((port_failures++)); fi

    # Tools Layer
    print_status "INFO" "Tools Layer:"
    if ! check_port 8081 "PHPMyAdmin"; then ((port_failures++)); fi
    if ! check_port 4201 "Keira3"; then ((port_failures++)); fi

    if [ "$QUICK_CHECK" = false ]; then
        print_status "HEADER" "WEB SERVICE HEALTH CHECKS"

        local web_failures=0
        if ! check_web_service "http://localhost:8081/" "PHPMyAdmin" "phpMyAdmin"; then ((web_failures++)); fi
        if ! check_web_service "http://localhost:4201/health" "Keira3" "healthy"; then ((web_failures++)); fi

        print_status "HEADER" "DATABASE CONNECTIVITY TEST"

        # Test database connectivity and verify schemas
        if docker exec ac-mysql mysql -uroot -pazerothcore123 -e "SHOW DATABASES;" 2>/dev/null | grep -q "acore_auth"; then
            print_status "SUCCESS" "Database schemas: verified"
        else
            print_status "ERROR" "Database schemas: verification failed"
            ((web_failures++))
        fi

        # Test realm configuration
        realm_count=$(docker exec ac-mysql mysql -uroot -pazerothcore123 -e "USE acore_auth; SELECT COUNT(*) FROM realmlist;" 2>/dev/null | tail -1)
        if [ "$realm_count" -gt 0 ] 2>/dev/null; then
            print_status "SUCCESS" "Realm configuration: $realm_count realm(s) configured"
        else
            print_status "ERROR" "Realm configuration: no realms found"
            ((web_failures++))
        fi
    fi

    print_status "HEADER" "DEPLOYMENT SUMMARY"

    # Summary
    local total_failures=$((container_failures + port_failures + ${web_failures:-0}))

    if [ $total_failures -eq 0 ]; then
        print_status "SUCCESS" "All services are healthy and operational!"
        print_status "INFO" "Available services:"
        echo "  🌐 PHPMyAdmin:      http://localhost:8081"
        echo "  🛠️  Keira3:         http://localhost:4201"
        echo "  🎮 Game Server:     localhost:8215"
        echo "  🔐 Auth Server:     localhost:3784"
        echo "  🔧 SOAP API:        localhost:7778"
        echo "  🗄️  MySQL:          localhost:64306"
        echo ""
        print_status "INFO" "Default credentials:"
        echo "  🗄️  MySQL:          root / azerothcore123"
        return 0
    else
        print_status "ERROR" "Health check failed with $total_failures issue(s)"
        print_status "INFO" "Check container logs for details: docker logs <container-name>"
        return 1
    fi
}

# Function to show container status
show_container_status() {
    print_status "HEADER" "CONTAINER STATUS OVERVIEW"

    echo -e "${BLUE}Container Name\t\tStatus\t\t\tPorts${NC}"
    echo "=================================================================="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep ac- | while read line; do
        echo "$line"
    done
}

# Main execution
main() {
    print_status "HEADER" "AZEROTHCORE DEPLOYMENT & HEALTH CHECK"

    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        print_status "ERROR" "Docker is not installed or not in PATH"
        exit 1
    fi

    # Check if docker compose is available
    if ! docker compose version &> /dev/null; then
        print_status "ERROR" "Docker Compose is not available"
        exit 1
    fi

    # Run setup if requested
    if [ "$RUN_SETUP" = true ]; then
        print_status "HEADER" "RUNNING SERVER SETUP"
        print_status "INFO" "Starting interactive server configuration..."

        # Change to parent directory to run setup script
        cd "$(dirname "$(pwd)")"

        if [ -f "scripts/setup-server.sh" ]; then
            bash scripts/setup-server.sh
            if [ $? -ne 0 ]; then
                print_status "ERROR" "Server setup failed or was cancelled"
                exit 1
            fi
        else
            print_status "ERROR" "Setup script not found at scripts/setup-server.sh"
            exit 1
        fi

        # Return to scripts directory
        cd scripts
        print_status "SUCCESS" "Server setup completed!"
        echo ""
    fi

    # Deploy the stack unless skipped
    if [ "$SKIP_DEPLOY" = false ]; then
        deploy_stack
    else
        print_status "INFO" "Skipping deployment, running health checks only..."
    fi

    # Show container status
    show_container_status

    # Perform health checks
    if perform_health_checks; then
        print_status "SUCCESS" "🎉 AzerothCore stack is fully operational!"
        exit 0
    else
        print_status "ERROR" "❌ Health check failed - see issues above"
        exit 1
    fi
}

# Run main function
main "$@"
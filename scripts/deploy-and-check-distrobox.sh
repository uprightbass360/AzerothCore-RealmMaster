#!/bin/bash

# ==============================================
# AzerothCore Podman Deployment & Health Check Script (Distrobox Compatible)
# ==============================================
# This script deploys the complete AzerothCore stack using Podman via distrobox-host-exec
# Usage: ./deploy-and-check-distrobox.sh [--skip-deploy] [--quick-check]

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
        -h|--help)
            echo "Usage: $0 [--skip-deploy] [--quick-check]"
            echo "  --skip-deploy    Skip deployment, only run health checks"
            echo "  --quick-check    Run basic health checks only"
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

    # Check if container is running
    if distrobox-host-exec podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        print_status "SUCCESS" "$container_name: running"
        return 0
    else
        print_status "ERROR" "$container_name: not running"
        return 1
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_status "HEADER" "DEPLOYING AZEROTHCORE STACK"

    # Check if environment files exist
    for env_file in "docker-compose-azerothcore-database.env" "docker-compose-azerothcore-services.env"; do
        if [ ! -f "$env_file" ]; then
            print_status "ERROR" "Environment file $env_file not found"
            exit 1
        fi
    done

    print_status "INFO" "Step 1: Cleaning up existing containers..."
    distrobox-host-exec bash -c "podman rm -f ac-mysql ac-backup ac-db-init ac-db-import ac-authserver ac-worldserver ac-client-data 2>/dev/null || true"

    print_status "INFO" "Step 2: Creating required directories..."
    mkdir -p storage/azerothcore/{mysql-data,backups,config,data,logs,modules,lua_scripts,cache}

    print_status "INFO" "Step 3: Creating network..."
    distrobox-host-exec bash -c "podman network create azerothcore --subnet 172.20.0.0/16 --gateway 172.20.0.1 2>/dev/null || true"

    print_status "INFO" "Step 4: Starting MySQL..."
    distrobox-host-exec bash -c "podman run -d --name ac-mysql --network azerothcore --network-alias ac-mysql -p 64306:3306 \
        -e MYSQL_ROOT_PASSWORD=azerothcore123 -e MYSQL_ROOT_HOST='%' -e MYSQL_ALLOW_EMPTY_PASSWORD=no \
        -v ./storage/azerothcore/mysql-data:/var/lib/mysql-persistent \
        -v ./storage/azerothcore/backups:/backups \
        --tmpfs /var/lib/mysql-runtime:size=2G \
        --restart unless-stopped \
        docker.io/library/mysql:8.0 \
        mysqld --datadir=/var/lib/mysql-runtime --default-authentication-plugin=mysql_native_password \
        --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --max_connections=1000 \
        --innodb-buffer-pool-size=256M --innodb-log-file-size=64M"

    # Wait for MySQL
    wait_for_service "MySQL" 24 "distrobox-host-exec podman exec ac-mysql mysql -uroot -pazerothcore123 -e 'SELECT 1' 2>/dev/null"

    print_status "INFO" "Step 5: Starting backup service..."
    distrobox-host-exec bash -c "podman run -d --name ac-backup --network azerothcore \
        -e MYSQL_HOST=ac-mysql -e MYSQL_PORT=3306 -e MYSQL_USER=root -e MYSQL_PASSWORD=azerothcore123 \
        -e BACKUP_RETENTION_DAYS=3 -e BACKUP_RETENTION_HOURS=6 -e BACKUP_DAILY_TIME=09 \
        -e DB_AUTH_NAME=acore_auth -e DB_WORLD_NAME=acore_world -e DB_CHARACTERS_NAME=acore_characters -e TZ=UTC \
        -v ./storage/azerothcore/backups:/backups -w /tmp --restart unless-stopped \
        docker.io/library/mysql:8.0 /bin/bash -c \
        'microdnf install -y curl || yum install -y curl; \
        curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/backup-scheduler.sh -o /tmp/backup-scheduler.sh; \
        chmod +x /tmp/backup-scheduler.sh; /tmp/backup-scheduler.sh'"

    print_status "INFO" "Step 6: Initializing databases..."
    distrobox-host-exec bash -c "podman run -d --name ac-db-init --network azerothcore \
        -e MYSQL_PWD=azerothcore123 -e MYSQL_HOST=ac-mysql -e MYSQL_USER=root -e MYSQL_ROOT_PASSWORD=azerothcore123 \
        -e DB_WAIT_RETRIES=60 -e DB_WAIT_SLEEP=10 \
        -e DB_AUTH_NAME=acore_auth -e DB_WORLD_NAME=acore_world -e DB_CHARACTERS_NAME=acore_characters \
        -e MYSQL_CHARACTER_SET=utf8mb4 -e MYSQL_COLLATION=utf8mb4_unicode_ci \
        -v ./storage/azerothcore/mysql-data:/var/lib/mysql-persistent --restart no \
        docker.io/library/mysql:8.0 sh -c \
        'microdnf install -y curl || yum install -y curl; \
        curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/db-init.sh -o /tmp/db-init.sh; \
        chmod +x /tmp/db-init.sh; /tmp/db-init.sh'"

    # Wait for db-init to complete
    wait_for_service "Database Init" 36 "distrobox-host-exec podman ps -a --format '{{.Names}} {{.Status}}' | grep 'ac-db-init' | grep -q 'Exited (0)'"

    print_status "INFO" "Step 7: Importing database..."
    sudo chmod -R 777 storage/azerothcore/config 2>/dev/null || true
    distrobox-host-exec bash -c "podman run -d --name ac-db-import --network azerothcore --privileged \
        -e AC_DATA_DIR=/azerothcore/data -e AC_LOGS_DIR=/azerothcore/logs \
        -e AC_LOGIN_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_auth' \
        -e AC_WORLD_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_world' \
        -e AC_CHARACTER_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_characters' \
        -e AC_CLOSE_IDLE_CONNECTIONS=false -e AC_UPDATES_ENABLE_DATABASES=7 -e AC_UPDATES_AUTO_SETUP=1 \
        -e AC_LOG_LEVEL=1 -e AC_LOGGER_ROOT_CONFIG='1,Console' -e AC_LOGGER_SERVER_CONFIG='1,Console' -e AC_APPENDER_CONSOLE_CONFIG='1,2,0' \
        -v ./storage/azerothcore/config:/azerothcore/env/dist/etc -u 0:0 --restart no \
        docker.io/acore/ac-wotlk-db-import:14.0.0-dev"

    # Wait for db-import to complete
    wait_for_service "Database Import" 60 "distrobox-host-exec podman ps -a --format '{{.Names}} {{.Status}}' | grep 'ac-db-import' | grep -q 'Exited (0)'"

    print_status "INFO" "Step 8: Starting client data download..."
    distrobox-host-exec bash -c "podman run -d --name ac-client-data --network azerothcore --privileged \
        -v ./storage/azerothcore/data:/azerothcore/data -v ./storage/azerothcore/cache:/cache -w /tmp --restart no \
        docker.io/library/alpine:latest sh -c \
        'apk add --no-cache curl unzip wget ca-certificates p7zip jq; \
        chown -R 1001:1001 /azerothcore/data /cache 2>/dev/null || true; mkdir -p /cache; \
        curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/download-client-data.sh -o /tmp/download-client-data.sh; \
        chmod +x /tmp/download-client-data.sh; /tmp/download-client-data.sh'" &

    print_status "INFO" "Step 9: Starting Auth Server..."
    distrobox-host-exec bash -c "podman run -d --name ac-authserver --network azerothcore --privileged -p 3784:3724 \
        -e AC_LOGIN_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_auth' \
        -e AC_UPDATES_ENABLE_DATABASES=0 -e AC_BIND_IP='0.0.0.0' -e AC_LOG_LEVEL=1 \
        -e AC_LOGGER_ROOT_CONFIG='1,Console' -e AC_LOGGER_SERVER_CONFIG='1,Console' -e AC_APPENDER_CONSOLE_CONFIG='1,2,0' \
        -v ./storage/azerothcore/config:/azerothcore/env/dist/etc --cap-add SYS_NICE --restart unless-stopped \
        docker.io/acore/ac-wotlk-authserver:14.0.0-dev"

    # Wait for authserver
    wait_for_service "Auth Server" 12 "check_container_health ac-authserver"

    print_status "INFO" "Step 10: Waiting for client data (this may take 10-20 minutes)..."
    print_status "INFO" "World Server will start once data download completes..."

    print_status "SUCCESS" "Deployment in progress! Client data downloading in background."
    print_status "INFO" "World Server will be started manually once client data is ready."
}

# Function to start worldserver
start_worldserver() {
    print_status "INFO" "Starting World Server..."
    distrobox-host-exec bash -c "podman run -d --name ac-worldserver --network azerothcore --privileged -t -p 8215:8085 -p 7778:7878 \
        -e AC_LOGIN_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_auth' \
        -e AC_WORLD_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_world' \
        -e AC_CHARACTER_DATABASE_INFO='ac-mysql;3306;root;azerothcore123;acore_characters' \
        -e AC_UPDATES_ENABLE_DATABASES=0 -e AC_BIND_IP='0.0.0.0' -e AC_DATA_DIR='/azerothcore/data' \
        -e AC_SOAP_PORT=7878 -e AC_PROCESS_PRIORITY=0 -e PLAYERBOT_ENABLED=1 -e PLAYERBOT_MAX_BOTS=40 -e AC_LOG_LEVEL=2 \
        -v ./storage/azerothcore/data:/azerothcore/data \
        -v ./storage/azerothcore/config:/azerothcore/env/dist/etc \
        -v ./storage/azerothcore/logs:/azerothcore/logs \
        -v ./storage/azerothcore/modules:/azerothcore/modules \
        -v ./storage/azerothcore/lua_scripts:/azerothcore/lua_scripts \
        --cap-add SYS_NICE --restart unless-stopped \
        docker.io/acore/ac-wotlk-worldserver:14.0.0-dev"

    wait_for_service "World Server" 12 "check_container_health ac-worldserver"
}

# Function to perform health checks
perform_health_checks() {
    print_status "HEADER" "CONTAINER HEALTH STATUS"

    # Check all containers
    local containers=("ac-mysql" "ac-backup" "ac-authserver" "ac-worldserver")
    local container_failures=0

    for container in "${containers[@]}"; do
        if distrobox-host-exec podman ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            if ! check_container_health "$container"; then
                ((container_failures++))
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
    if distrobox-host-exec podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^ac-worldserver$"; then
        if ! check_port 8215 "World Server"; then ((port_failures++)); fi
        if ! check_port 7778 "SOAP API"; then ((port_failures++)); fi
    else
        print_status "INFO" "World Server: not started yet (waiting for client data)"
    fi

    if [ "$QUICK_CHECK" = false ]; then
        print_status "HEADER" "DATABASE CONNECTIVITY TEST"

        # Test database connectivity and verify schemas
        if distrobox-host-exec podman exec ac-mysql mysql -uroot -pazerothcore123 -e "SHOW DATABASES;" 2>/dev/null | grep -q "acore_auth"; then
            print_status "SUCCESS" "Database schemas: verified"
        else
            print_status "ERROR" "Database schemas: verification failed"
            ((container_failures++))
        fi

        # Test realm configuration
        realm_count=$(distrobox-host-exec podman exec ac-mysql mysql -uroot -pazerothcore123 -e "USE acore_auth; SELECT COUNT(*) FROM realmlist;" 2>/dev/null | tail -1)
        if [ "$realm_count" -gt 0 ] 2>/dev/null; then
            print_status "SUCCESS" "Realm configuration: $realm_count realm(s) configured"
        else
            print_status "WARNING" "Realm configuration: no realms configured yet (post-install needed)"
        fi

        # Check for playerbots database
        if distrobox-host-exec podman exec ac-mysql mysql -uroot -pazerothcore123 -e "SHOW DATABASES;" 2>/dev/null | grep -q "acore_playerbots"; then
            print_status "SUCCESS" "Playerbots database: detected"
        else
            print_status "INFO" "Playerbots database: not present (standard installation)"
        fi
    fi

    print_status "HEADER" "DEPLOYMENT SUMMARY"

    # Summary
    local total_failures=$((container_failures + port_failures))

    if [ $total_failures -eq 0 ]; then
        print_status "SUCCESS" "All services are healthy and operational!"
        print_status "INFO" "Available services:"
        echo "  🎮 Game Server:    localhost:8215"
        echo "  🔐 Auth Server:    localhost:3784"
        echo "  🔧 SOAP API:       localhost:7778"
        echo "  🗄️  MySQL:          localhost:64306"
        echo ""
        print_status "INFO" "Default credentials:"
        echo "  🗄️  MySQL:          root / azerothcore123"
        return 0
    else
        print_status "WARNING" "Health check completed with $total_failures issue(s)"
        print_status "INFO" "Check container logs for details: distrobox-host-exec podman logs <container-name>"
        return 1
    fi
}

# Function to show container status
show_container_status() {
    print_status "HEADER" "CONTAINER STATUS OVERVIEW"

    echo -e "${BLUE}Container Name\t\tStatus${NC}"
    echo "=============================================="
    distrobox-host-exec podman ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep ac- || echo "No containers found"
}

# Main execution
main() {
    print_status "HEADER" "AZEROTHCORE DEPLOYMENT & HEALTH CHECK (DISTROBOX/PODMAN)"

    # Check if distrobox-host-exec is available
    if ! command -v distrobox-host-exec &> /dev/null; then
        print_status "ERROR" "distrobox-host-exec is not available - are you running in a distrobox?"
        exit 1
    fi

    # Check if podman is available on host
    if ! distrobox-host-exec podman version &> /dev/null; then
        print_status "ERROR" "Podman is not available on the host system"
        exit 1
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
        print_status "SUCCESS" "🎉 AzerothCore stack deployment successful!"
        exit 0
    else
        print_status "INFO" "⚠️  Some services may still be starting - check status with: distrobox-host-exec podman ps -a"
        exit 0
    fi
}

# Run main function
main "$@"

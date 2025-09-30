#!/bin/bash
# ==============================================
# AzerothCore Complete Stack Deployment Script
# ==============================================
# Deploys AzerothCore services in proper order with monitoring
# Designed for Debian systems with Docker/Docker Compose

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_DIR="$SCRIPT_DIR/deployment-logs"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d_%H%M%S).log"
PID_FILE="/var/run/azerothcore-deploy.pid"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Deployment layers in order
COMPOSE_LAYERS=(
    "database"
    "services"
    "optional"
    "tools"
)

# Service monitoring timeouts (seconds)
declare -A SERVICE_TIMEOUTS=(
    ["ac-mysql"]=120
    ["ac-db-init"]=60
    ["ac-db-import"]=1800
    ["ac-client-data"]=2400
    ["ac-authserver"]=180
    ["ac-worldserver"]=300
    ["ac-backup"]=60
    ["ac-mysql-persist"]=60
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${CYAN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "DEBUG") echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
cleanup() {
    log "INFO" "Cleaning up..."
    rm -f "$PID_FILE"
    if [[ ${#BACKGROUND_PIDS[@]} -gt 0 ]]; then
        log "INFO" "Stopping background monitoring processes..."
        for pid in "${BACKGROUND_PIDS[@]}"; do
            kill "$pid" 2>/dev/null || true
        done
    fi
}

trap cleanup EXIT

error_exit() {
    log "ERROR" "$1"
    cleanup
    exit 1
}

# Array to track background processes
BACKGROUND_PIDS=()

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Check if running as root for system service setup
    if [[ "$DEPLOY_MODE" == "system" ]] && [[ $EUID -ne 0 ]]; then
        error_exit "System deployment mode requires root privileges"
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed"
    fi

    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running"
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error_exit "Docker Compose is not installed"
    fi

    # Check compose files exist
    for layer in "${COMPOSE_LAYERS[@]}"; do
        local compose_file="docker-compose-azerothcore-${layer}.yml"
        if [[ ! -f "$SCRIPT_DIR/$compose_file" ]]; then
            error_exit "Missing compose file: $compose_file"
        fi
    done

    log "SUCCESS" "Prerequisites check passed"
}

# Setup environment
setup_environment() {
    log "INFO" "Setting up deployment environment..."

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Create data directories
    mkdir -p "$SCRIPT_DIR/local-data/mysql-data"
    mkdir -p "$SCRIPT_DIR/local-data/config"
    mkdir -p "$SCRIPT_DIR/backups"

    # Set up environment file
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        if [[ -f "$SCRIPT_DIR/.env-database-local" ]]; then
            log "INFO" "Using local database environment configuration"
            cp "$SCRIPT_DIR/.env-database-local" "$SCRIPT_DIR/.env"
        else
            error_exit "No environment configuration found"
        fi
    fi

    # Store PID for system service management
    echo $$ > "$PID_FILE"

    log "SUCCESS" "Environment setup complete"
}

# Monitor container health
monitor_container() {
    local container_name="$1"
    local timeout="${2:-300}"
    local start_time=$(date +%s)

    log "INFO" "Monitoring $container_name (timeout: ${timeout}s)..."

    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            local status=$(docker ps --filter "name=$container_name" --format "{{.Status}}")

            # Check if container is healthy
            if echo "$status" | grep -q "healthy"; then
                log "SUCCESS" "$container_name is healthy"
                return 0
            fi

            # Check if container exited
            if echo "$status" | grep -q "Exited"; then
                local exit_code=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}" | grep -o "Exited ([0-9]*)" | grep -o "[0-9]*")
                if [[ "$exit_code" == "0" ]]; then
                    log "SUCCESS" "$container_name completed successfully"
                    return 0
                else
                    log "ERROR" "$container_name failed (exit code: $exit_code)"
                    log "DEBUG" "Container logs:"
                    docker logs "$container_name" 2>&1 | tail -20 | while read line; do
                        log "DEBUG" "  $line"
                    done
                    return 1
                fi
            fi

            # Show periodic status updates
            if [[ $(( ($(date +%s) - start_time) % 30 )) -eq 0 ]]; then
                log "INFO" "$container_name status: $status"
                # Show last few log lines
                docker logs "$container_name" --tail 3 2>&1 | while read line; do
                    log "DEBUG" "  [$container_name] $line"
                done
            fi
        else
            log "WARN" "Waiting for $container_name to start..."
        fi

        sleep 5
    done

    log "ERROR" "Timeout waiting for $container_name after ${timeout}s"
    return 1
}

# Deploy a specific layer
deploy_layer() {
    local layer="$1"
    local compose_file="docker-compose-azerothcore-${layer}.yml"

    log "INFO" "Deploying layer: $layer"

    # Start the layer
    if ! docker-compose -f "$compose_file" up -d; then
        error_exit "Failed to start $layer layer"
    fi

    # Get services in this layer
    local services=$(docker-compose -f "$compose_file" config --services)

    # Monitor each service
    for service in $services; do
        local container_name="$service"
        local timeout="${SERVICE_TIMEOUTS[$container_name]:-300}"

        if ! monitor_container "$container_name" "$timeout"; then
            error_exit "Service $container_name failed to start properly"
        fi
    done

    log "SUCCESS" "Layer $layer deployed successfully"
}

# Monitor running services
monitor_services() {
    log "INFO" "Starting continuous service monitoring..."

    while true; do
        local unhealthy_services=()

        # Check all running containers
        for container in $(docker ps --format "{{.Names}}" | grep "^ac-"); do
            local status=$(docker ps --filter "name=$container" --format "{{.Status}}")

            if echo "$status" | grep -q "unhealthy\|Restarting\|Exited"; then
                unhealthy_services+=("$container")
                log "WARN" "Unhealthy service detected: $container ($status)"
            fi
        done

        # Report status
        if [[ ${#unhealthy_services[@]} -eq 0 ]]; then
            log "INFO" "All services healthy ($(docker ps --filter "name=ac-" --format "{{.Names}}" | wc -l) running)"
        else
            log "WARN" "Unhealthy services: ${unhealthy_services[*]}"
        fi

        sleep 60
    done
}

# Get deployment status
get_status() {
    log "INFO" "Current deployment status:"

    for layer in "${COMPOSE_LAYERS[@]}"; do
        local compose_file="docker-compose-azerothcore-${layer}.yml"
        if [[ -f "$compose_file" ]]; then
            echo -e "\n${BLUE}=== $layer Layer ===${NC}"
            docker-compose -f "$compose_file" ps 2>/dev/null || echo "Layer not deployed"
        fi
    done

    echo -e "\n${BLUE}=== Resource Usage ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $(docker ps --filter "name=ac-" --format "{{.Names}}" 2>/dev/null || echo "none") 2>/dev/null || echo "No containers running"
}

# Stop all services
stop_all() {
    log "INFO" "Stopping all AzerothCore services..."

    # Stop in reverse order
    for ((i=${#COMPOSE_LAYERS[@]}-1; i>=0; i--)); do
        local layer="${COMPOSE_LAYERS[i]}"
        local compose_file="docker-compose-azerothcore-${layer}.yml"

        if [[ -f "$compose_file" ]]; then
            log "INFO" "Stopping $layer layer..."
            docker-compose -f "$compose_file" down 2>/dev/null || true
        fi
    done

    log "SUCCESS" "All services stopped"
}

# Install system service
install_system_service() {
    log "INFO" "Installing AzerothCore as system service..."

    cat > /etc/systemd/system/azerothcore.service << EOF
[Unit]
Description=AzerothCore WoW Server
After=docker.service
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=forking
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/azerothcore-deploy.sh start
ExecStop=$SCRIPT_DIR/azerothcore-deploy.sh stop
ExecReload=$SCRIPT_DIR/azerothcore-deploy.sh restart
PIDFile=$PID_FILE
Restart=always
RestartSec=30
TimeoutStartSec=1800
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable azerothcore

    log "SUCCESS" "AzerothCore system service installed"
    log "INFO" "Use 'systemctl start azerothcore' to start the service"
    log "INFO" "Use 'systemctl status azerothcore' to check status"
}

# Main deployment function
main_deploy() {
    log "INFO" "Starting AzerothCore deployment..."

    check_prerequisites
    setup_environment

    # Deploy each layer in sequence
    for layer in "${COMPOSE_LAYERS[@]}"; do
        deploy_layer "$layer"

        # Brief pause between layers
        sleep 10
    done

    log "SUCCESS" "AzerothCore deployment completed successfully!"

    # Show final status
    get_status

    # Start background monitoring if not in daemon mode
    if [[ "$MONITOR_MODE" == "continuous" ]]; then
        monitor_services &
        BACKGROUND_PIDS+=($!)
        log "INFO" "Background monitoring started (PID: $!)"

        # Keep script running
        wait
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    start           Deploy AzerothCore stack
    stop            Stop all AzerothCore services
    restart         Restart AzerothCore stack
    status          Show current deployment status
    logs [service]  Show logs for service (or all services)
    install-service Install as system service (requires root)

OPTIONS:
    --monitor       Enable continuous monitoring
    --system        System deployment mode (requires root)
    --help          Show this help message

Examples:
    $0 start --monitor              # Deploy with continuous monitoring
    $0 status                       # Show current status
    $0 logs ac-worldserver         # Show worldserver logs
    $0 install-service             # Install as system service

Environment Variables:
    DEPLOY_MODE=system              # Enable system mode
    MONITOR_MODE=continuous         # Enable monitoring

EOF
}

# Parse command line arguments
COMMAND="${1:-start}"
DEPLOY_MODE="${DEPLOY_MODE:-local}"
MONITOR_MODE="${MONITOR_MODE:-single}"

shift || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --monitor)
            MONITOR_MODE="continuous"
            shift
            ;;
        --system)
            DEPLOY_MODE="system"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    "start")
        main_deploy
        ;;
    "stop")
        stop_all
        ;;
    "restart")
        stop_all
        sleep 5
        main_deploy
        ;;
    "status")
        get_status
        ;;
    "logs")
        service_name="${1:-}"
        if [[ -n "$service_name" ]]; then
            docker logs "$service_name" --follow
        else
            log "INFO" "Available services:"
            docker ps --filter "name=ac-" --format "{{.Names}}" || echo "No services running"
        fi
        ;;
    "install-service")
        install_system_service
        ;;
    "help"|"--help")
        usage
        exit 0
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
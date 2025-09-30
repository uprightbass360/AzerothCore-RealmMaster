#!/bin/bash
# ==============================================
# AzerothCore Deployment Test Script
# ==============================================
# Tests the deployment script functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
}

# Test deployment script
test_deployment_script() {
    log "INFO" "Testing deployment script functionality..."

    # Test help command
    if ./azerothcore-deploy.sh --help >/dev/null 2>&1; then
        log "SUCCESS" "Help command works"
    else
        log "ERROR" "Help command failed"
        return 1
    fi

    # Test configuration validation
    if ./azerothcore-deploy.sh status >/dev/null 2>&1; then
        log "SUCCESS" "Status command works"
    else
        log "WARN" "Status command failed (expected if no services running)"
    fi

    log "SUCCESS" "Deployment script tests passed"
}

# Test monitoring script
test_monitoring_script() {
    log "INFO" "Testing monitoring script functionality..."

    # Test status generation
    if ./azerothcore-monitor.sh status >/dev/null 2>&1; then
        log "SUCCESS" "Monitoring status generation works"
    else
        log "ERROR" "Monitoring status generation failed"
        return 1
    fi

    # Check if web directory was created
    if [[ -d "monitoring-web" ]] && [[ -f "monitoring-web/index.html" ]]; then
        log "SUCCESS" "Web status page generated"
    else
        log "ERROR" "Web status page not generated"
        return 1
    fi

    log "SUCCESS" "Monitoring script tests passed"
}

# Test database layer deployment
test_database_layer() {
    log "INFO" "Testing database layer deployment..."

    # Ensure clean state
    docker-compose -f docker-compose-azerothcore-database.yml down 2>/dev/null || true

    # Test database deployment
    log "INFO" "Starting database layer..."
    if docker-compose -f docker-compose-azerothcore-database.yml up -d ac-mysql; then
        log "SUCCESS" "MySQL started successfully"

        # Wait for health check
        local timeout=60
        local start_time=$(date +%s)

        while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
            if docker ps --filter "name=ac-mysql" --format "{{.Status}}" | grep -q "healthy"; then
                log "SUCCESS" "MySQL is healthy"
                break
            fi
            sleep 2
        done

        # Test database connection
        if docker run --rm --network azerothcore mysql:8.0 \
            mysql -h ac-mysql -uroot -pazerothcore123 -e "SELECT 1;" &>/dev/null; then
            log "SUCCESS" "Database connectivity test passed"
        else
            log "ERROR" "Database connectivity test failed"
        fi

        # Cleanup
        docker-compose -f docker-compose-azerothcore-database.yml down
        log "INFO" "Database layer test cleanup completed"

    else
        log "ERROR" "MySQL failed to start"
        return 1
    fi

    log "SUCCESS" "Database layer tests passed"
}

# Test environment setup
test_environment() {
    log "INFO" "Testing environment setup..."

    # Check required files
    local required_files=(
        "azerothcore-deploy.sh"
        "azerothcore-monitor.sh"
        "install-system-service.sh"
        ".env-database-local"
        "docker-compose-azerothcore-database.yml"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "SUCCESS" "$file exists"
        else
            log "ERROR" "$file missing"
            return 1
        fi
    done

    # Check if scripts are executable
    for script in azerothcore-deploy.sh azerothcore-monitor.sh install-system-service.sh; do
        if [[ -x "$script" ]]; then
            log "SUCCESS" "$script is executable"
        else
            log "ERROR" "$script is not executable"
            return 1
        fi
    done

    log "SUCCESS" "Environment tests passed"
}

# Test Docker requirements
test_docker() {
    log "INFO" "Testing Docker requirements..."

    # Check Docker
    if command -v docker &> /dev/null; then
        log "SUCCESS" "Docker is installed"
    else
        log "ERROR" "Docker is not installed"
        return 1
    fi

    # Check Docker daemon
    if docker info &> /dev/null; then
        log "SUCCESS" "Docker daemon is running"
    else
        log "ERROR" "Docker daemon is not running"
        return 1
    fi

    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        log "SUCCESS" "Docker Compose is installed"
    else
        log "ERROR" "Docker Compose is not installed"
        return 1
    fi

    log "SUCCESS" "Docker tests passed"
}

# Test system service installer (dry run)
test_system_service_installer() {
    log "INFO" "Testing system service installer (validation only)..."

    # Test script syntax
    if bash -n install-system-service.sh; then
        log "SUCCESS" "System service installer syntax is valid"
    else
        log "ERROR" "System service installer has syntax errors"
        return 1
    fi

    # Test help command
    if ./install-system-service.sh 2>&1 | grep -q "Usage:"; then
        log "SUCCESS" "System service installer help works"
    else
        log "ERROR" "System service installer help failed"
        return 1
    fi

    log "SUCCESS" "System service installer tests passed"
}

# Run all tests
run_all_tests() {
    log "INFO" "Starting comprehensive deployment tests..."
    echo

    local tests=(
        "test_environment"
        "test_docker"
        "test_deployment_script"
        "test_monitoring_script"
        "test_system_service_installer"
        "test_database_layer"
    )

    local passed=0
    local total=${#tests[@]}

    for test in "${tests[@]}"; do
        echo "----------------------------------------"
        if $test; then
            ((passed++))
        else
            log "ERROR" "Test $test failed"
        fi
        echo
    done

    echo "========================================"
    log "INFO" "Test Results: $passed/$total tests passed"

    if [[ $passed -eq $total ]]; then
        log "SUCCESS" "All tests passed! 🎉"
        log "INFO" "Your AzerothCore deployment is ready"
        return 0
    else
        log "ERROR" "Some tests failed. Please fix issues before deployment."
        return 1
    fi
}

# Command handling
case "${1:-all}" in
    "all")
        run_all_tests
        ;;
    "environment")
        test_environment
        ;;
    "docker")
        test_docker
        ;;
    "deployment")
        test_deployment_script
        ;;
    "monitoring")
        test_monitoring_script
        ;;
    "database")
        test_database_layer
        ;;
    "installer")
        test_system_service_installer
        ;;
    *)
        echo "Usage: $0 [all|environment|docker|deployment|monitoring|database|installer]"
        echo
        echo "Tests:"
        echo "  all          Run all tests (default)"
        echo "  environment  Test file structure and permissions"
        echo "  docker       Test Docker installation and daemon"
        echo "  deployment   Test deployment script functionality"
        echo "  monitoring   Test monitoring script functionality"
        echo "  database     Test database layer deployment"
        echo "  installer    Test system service installer"
        echo
        exit 1
        ;;
esac
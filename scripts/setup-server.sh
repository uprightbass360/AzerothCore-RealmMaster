#!/bin/bash

# ==============================================
# AzerothCore Server Setup Script
# ==============================================
# Interactive script to configure common server settings and generate deployment-ready environment files

set -e

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
        "PROMPT")
            echo -e "${YELLOW}🔧 ${message}${NC}"
            ;;
    esac
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port number
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to validate number
validate_number() {
    local num=$1
    if [[ $num =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to prompt for input with validation
prompt_input() {
    local prompt=$1
    local default=$2
    local validator=$3
    local value=""

    while true; do
        if [ -n "$default" ]; then
            read -p "$(echo -e "${YELLOW}🔧 ${prompt} [${default}]: ${NC}")" value
            value=${value:-$default}
        else
            read -p "$(echo -e "${YELLOW}🔧 ${prompt}: ${NC}")" value
        fi

        if [ -z "$validator" ] || $validator "$value"; then
            echo "$value"
            return 0
        else
            print_status "ERROR" "Invalid input. Please try again."
        fi
    done
}

# Function to show deployment type info
show_deployment_info() {
    local type=$1
    case $type in
        "local")
            print_status "INFO" "Local Development Setup:"
            echo "  - Server accessible only on this machine"
            echo "  - Server address: 127.0.0.1"
            echo "  - Storage: ./storage (local directory)"
            echo "  - Perfect for development and testing"
            ;;
        "lan")
            print_status "INFO" "LAN Server Setup:"
            echo "  - Server accessible on local network"
            echo "  - Requires your machine's LAN IP address"
            echo "  - Storage: configurable"
            echo "  - Good for home networks or office environments"
            ;;
        "public")
            print_status "INFO" "Public Server Setup:"
            echo "  - Server accessible from the internet"
            echo "  - Requires public IP or domain name"
            echo "  - Requires port forwarding configuration"
            echo "  - Storage: recommended to use persistent storage"
            ;;
    esac
    echo ""
}

# Main configuration function
main() {
    print_status "HEADER" "AZEROTHCORE SERVER SETUP"
    echo "This script will help you configure your AzerothCore server for deployment."
    echo "It will create customized environment files based on your configuration."
    echo ""

    # Check if we're in the right directory
    if [ ! -f "docker-compose-azerothcore-database.env" ] || [ ! -f "docker-compose-azerothcore-services.env" ]; then
        print_status "ERROR" "Environment files not found. Please run this script from the acore-compose directory."
        exit 1
    fi

    # Deployment type selection
    print_status "HEADER" "DEPLOYMENT TYPE"
    echo "Select your deployment type:"
    echo "1) Local Development (single machine)"
    echo "2) LAN Server (local network)"
    echo "3) Public Server (internet accessible)"
    echo ""

    while true; do
        read -p "$(echo -e "${YELLOW}🔧 Select deployment type [1-3]: ${NC}")" deploy_type
        case $deploy_type in
            1)
                DEPLOYMENT_TYPE="local"
                show_deployment_info "local"
                break
                ;;
            2)
                DEPLOYMENT_TYPE="lan"
                show_deployment_info "lan"
                break
                ;;
            3)
                DEPLOYMENT_TYPE="public"
                show_deployment_info "public"
                break
                ;;
            *)
                print_status "ERROR" "Please select 1, 2, or 3"
                ;;
        esac
    done

    # Server configuration
    print_status "HEADER" "SERVER CONFIGURATION"

    # Server address configuration
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
        SERVER_ADDRESS="127.0.0.1"
        print_status "INFO" "Server address set to: $SERVER_ADDRESS"
    else
        if [ "$DEPLOYMENT_TYPE" = "lan" ]; then
            # Try to detect LAN IP
            LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | head -1 | awk '{print $7}' || echo "")
            if [ -n "$LAN_IP" ]; then
                SERVER_ADDRESS=$(prompt_input "Enter server IP address" "$LAN_IP" validate_ip)
            else
                SERVER_ADDRESS=$(prompt_input "Enter server IP address (e.g., 192.168.1.100)" "" validate_ip)
            fi
        else
            # Public server
            SERVER_ADDRESS=$(prompt_input "Enter server address (IP or domain)" "your-domain.com" "")
        fi
    fi

    # Port configuration
    REALM_PORT=$(prompt_input "Enter client connection port" "8215" validate_port)
    AUTH_EXTERNAL_PORT=$(prompt_input "Enter auth server port" "3784" validate_port)
    SOAP_EXTERNAL_PORT=$(prompt_input "Enter SOAP API port" "7778" validate_port)
    MYSQL_EXTERNAL_PORT=$(prompt_input "Enter MySQL external port" "64306" validate_port)

    # Database configuration
    print_status "HEADER" "DATABASE CONFIGURATION"
    MYSQL_ROOT_PASSWORD=$(prompt_input "Enter MySQL root password" "azerothcore123" "")

    # Storage configuration
    print_status "HEADER" "STORAGE CONFIGURATION"
    if [ "$DEPLOYMENT_TYPE" = "local" ]; then
        STORAGE_ROOT="./storage"
        print_status "INFO" "Storage path set to: $STORAGE_ROOT"
    else
        echo "Storage options:"
        echo "1) ./storage (local directory)"
        echo "2) /nfs/containers (NFS mount)"
        echo "3) Custom path"

        while true; do
            read -p "$(echo -e "${YELLOW}🔧 Select storage option [1-3]: ${NC}")" storage_option
            case $storage_option in
                1)
                    STORAGE_ROOT="./storage"
                    break
                    ;;
                2)
                    STORAGE_ROOT="/nfs/containers"
                    break
                    ;;
                3)
                    STORAGE_ROOT=$(prompt_input "Enter custom storage path" "/mnt/azerothcore-data" "")
                    break
                    ;;
                *)
                    print_status "ERROR" "Please select 1, 2, or 3"
                    ;;
            esac
        done
    fi

    # Backup configuration
    print_status "HEADER" "BACKUP CONFIGURATION"
    BACKUP_RETENTION_DAYS=$(prompt_input "Days to keep daily backups" "3" validate_number)
    BACKUP_RETENTION_HOURS=$(prompt_input "Hours to keep hourly backups" "6" validate_number)
    BACKUP_DAILY_TIME=$(prompt_input "Daily backup time (24h format, e.g., 09 for 9 AM)" "09" "")

    # Optional: Timezone
    TIMEZONE=$(prompt_input "Server timezone" "UTC" "")

    # Summary
    print_status "HEADER" "CONFIGURATION SUMMARY"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Server Address: $SERVER_ADDRESS"
    echo "Client Port: $REALM_PORT"
    echo "Auth Port: $AUTH_EXTERNAL_PORT"
    echo "SOAP Port: $SOAP_EXTERNAL_PORT"
    echo "MySQL Port: $MYSQL_EXTERNAL_PORT"
    echo "Storage Path: $STORAGE_ROOT"
    echo "Daily Backup Time: ${BACKUP_DAILY_TIME}:00 UTC"
    echo "Backup Retention: ${BACKUP_RETENTION_DAYS} days, ${BACKUP_RETENTION_HOURS} hours"
    echo ""

    # Confirmation
    while true; do
        read -p "$(echo -e "${YELLOW}🔧 Proceed with this configuration? [y/N]: ${NC}")" confirm
        case $confirm in
            [Yy]*)
                break
                ;;
            [Nn]*|"")
                print_status "INFO" "Configuration cancelled"
                exit 0
                ;;
            *)
                print_status "ERROR" "Please answer y or n"
                ;;
        esac
    done

    # Create custom environment files
    print_status "HEADER" "CREATING ENVIRONMENT FILES"

    # Create custom database environment file
    print_status "INFO" "Creating custom database environment file..."
    cp docker-compose-azerothcore-database.env docker-compose-azerothcore-database-custom.env

    # Substitute values in database env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#MYSQL_EXTERNAL_PORT=.*#MYSQL_EXTERNAL_PORT=${MYSQL_EXTERNAL_PORT}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_RETENTION_DAYS=.*#BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_RETENTION_HOURS=.*#BACKUP_RETENTION_HOURS=${BACKUP_RETENTION_HOURS}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#BACKUP_DAILY_TIME=.*#BACKUP_DAILY_TIME=${BACKUP_DAILY_TIME}#" docker-compose-azerothcore-database-custom.env
    sed -i "s#TZ=.*#TZ=${TIMEZONE}#" docker-compose-azerothcore-database-custom.env

    # Create custom services environment file
    print_status "INFO" "Creating custom services environment file..."
    cp docker-compose-azerothcore-services.env docker-compose-azerothcore-services-custom.env

    # Substitute values in services env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#AUTH_EXTERNAL_PORT=.*#AUTH_EXTERNAL_PORT=${AUTH_EXTERNAL_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#WORLD_EXTERNAL_PORT=.*#WORLD_EXTERNAL_PORT=${REALM_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#SOAP_EXTERNAL_PORT=.*#SOAP_EXTERNAL_PORT=${SOAP_EXTERNAL_PORT}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#SERVER_ADDRESS=.*#SERVER_ADDRESS=${SERVER_ADDRESS}#" docker-compose-azerothcore-services-custom.env
    sed -i "s#REALM_PORT=.*#REALM_PORT=${REALM_PORT}#" docker-compose-azerothcore-services-custom.env

    # Create custom tools environment file
    print_status "INFO" "Creating custom tools environment file..."
    cp docker-compose-azerothcore-tools.env docker-compose-azerothcore-tools-custom.env

    # Substitute values in tools env file using a different delimiter
    sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=${STORAGE_ROOT}#" docker-compose-azerothcore-tools-custom.env

    print_status "SUCCESS" "Custom environment files created:"
    echo "  - docker-compose-azerothcore-database-custom.env"
    echo "  - docker-compose-azerothcore-services-custom.env"
    echo "  - docker-compose-azerothcore-tools-custom.env"
    echo ""

    # Deployment instructions
    print_status "HEADER" "DEPLOYMENT INSTRUCTIONS"
    echo "To deploy your server with the custom configuration:"
    echo ""
    echo "1. Deploy database layer:"
    echo "   docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml up -d"
    echo ""
    echo "2. Deploy services layer:"
    echo "   docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml up -d"
    echo ""
    echo "3. Deploy tools layer (optional):"
    echo "   docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml up -d"
    echo ""

    if [ "$DEPLOYMENT_TYPE" != "local" ]; then
        print_status "WARNING" "Additional configuration required for ${DEPLOYMENT_TYPE} deployment:"
        echo "  - Ensure firewall allows traffic on configured ports"
        if [ "$DEPLOYMENT_TYPE" = "public" ]; then
            echo "  - Configure port forwarding on your router:"
            echo "    - ${REALM_PORT} (client connections)"
            echo "    - ${AUTH_EXTERNAL_PORT} (auth server)"
            echo "    - ${SOAP_EXTERNAL_PORT} (SOAP API)"
        fi
        echo ""
    fi

    # Client configuration
    print_status "HEADER" "CLIENT CONFIGURATION"
    echo "Configure your WoW 3.3.5a client by editing realmlist.wtf:"
    if [ "$REALM_PORT" = "8215" ]; then
        echo "  set realmlist ${SERVER_ADDRESS}"
    else
        echo "  set realmlist ${SERVER_ADDRESS} ${REALM_PORT}"
    fi
    echo ""

    print_status "SUCCESS" "🎉 Server setup complete!"
    print_status "INFO" "Your custom environment files are ready for deployment."
}

# Run main function
main "$@"
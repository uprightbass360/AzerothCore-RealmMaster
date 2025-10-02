#!/bin/bash

# AzerothCore Configuration Update Script
# Updates .conf files with production database settings

set -e

echo "🔧 AzerothCore Configuration Update Script"
echo "=========================================="

# Load environment variables from env file if it exists
if [ -f "docker-compose-azerothcore-services.env" ]; then
    echo "📂 Loading environment from docker-compose-azerothcore-services.env"
    set -a  # automatically export all variables
    source docker-compose-azerothcore-services.env
    set +a  # turn off automatic export
    echo ""
fi

# Configuration variables from environment
MYSQL_HOST="${MYSQL_HOST:-ac-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-azerothcore123}"
DB_AUTH_NAME="${DB_AUTH_NAME:-acore_auth}"
DB_WORLD_NAME="${DB_WORLD_NAME:-acore_world}"
DB_CHARACTERS_NAME="${DB_CHARACTERS_NAME:-acore_characters}"

# Configuration file paths
CONFIG_DIR="${STORAGE_PATH}/config"
AUTHSERVER_CONF="${CONFIG_DIR}/authserver.conf"
WORLDSERVER_CONF="${CONFIG_DIR}/worldserver.conf"

echo "📍 Configuration directory: ${CONFIG_DIR}"

# Check if configuration files exist
if [ ! -f "${AUTHSERVER_CONF}" ]; then
    echo "❌ Error: ${AUTHSERVER_CONF} not found"
    exit 1
fi

if [ ! -f "${WORLDSERVER_CONF}" ]; then
    echo "❌ Error: ${WORLDSERVER_CONF} not found"
    exit 1
fi

echo "✅ Configuration files found"

# Backup original files
echo "💾 Creating backups..."
cp "${AUTHSERVER_CONF}" "${AUTHSERVER_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
cp "${WORLDSERVER_CONF}" "${WORLDSERVER_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

# Update AuthServer configuration
echo "🔧 Updating AuthServer configuration..."
sed -i "s/^LoginDatabaseInfo = .*/LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"/" "${AUTHSERVER_CONF}"

# Verify AuthServer update
AUTH_UPDATED=$(grep "LoginDatabaseInfo" "${AUTHSERVER_CONF}" | grep "${MYSQL_HOST}")
if [ -n "${AUTH_UPDATED}" ]; then
    echo "✅ AuthServer configuration updated successfully"
    echo "   ${AUTH_UPDATED}"
else
    echo "❌ Failed to update AuthServer configuration"
    exit 1
fi

# Update WorldServer configuration
echo "🔧 Updating WorldServer configuration..."
sed -i "s/^LoginDatabaseInfo     = .*/LoginDatabaseInfo     = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"/" "${WORLDSERVER_CONF}"
sed -i "s/^WorldDatabaseInfo     = .*/WorldDatabaseInfo     = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}\"/" "${WORLDSERVER_CONF}"
sed -i "s/^CharacterDatabaseInfo = .*/CharacterDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}\"/" "${WORLDSERVER_CONF}"

# Verify WorldServer updates
LOGIN_UPDATED=$(grep "^LoginDatabaseInfo" "${WORLDSERVER_CONF}" | grep "${MYSQL_HOST}")
WORLD_UPDATED=$(grep "^WorldDatabaseInfo" "${WORLDSERVER_CONF}" | grep "${MYSQL_HOST}")
CHARACTER_UPDATED=$(grep "^CharacterDatabaseInfo" "${WORLDSERVER_CONF}" | grep "${MYSQL_HOST}")

if [ -n "${LOGIN_UPDATED}" ] && [ -n "${WORLD_UPDATED}" ] && [ -n "${CHARACTER_UPDATED}" ]; then
    echo "✅ WorldServer configuration updated successfully"
    echo "   Login:     ${LOGIN_UPDATED}"
    echo "   World:     ${WORLD_UPDATED}"
    echo "   Character: ${CHARACTER_UPDATED}"
else
    echo "❌ Failed to update WorldServer configuration"
    exit 1
fi

echo ""
echo "🎉 Configuration update completed successfully!"
echo "📋 Updated files:"
echo "   - ${AUTHSERVER_CONF}"
echo "   - ${WORLDSERVER_CONF}"
echo ""
echo "💡 Restart authserver and worldserver services to apply changes:"
echo "   docker compose -f docker-compose-azerothcore-services.yml restart ac-authserver ac-worldserver"
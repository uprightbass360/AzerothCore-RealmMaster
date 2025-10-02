#!/bin/bash

# AzerothCore Post-Installation Setup Script
# Configures fresh authserver and worldserver installations for production

set -e

echo "🚀 AzerothCore Post-Installation Setup"
echo "====================================="
echo ""

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
STORAGE_PATH="${STORAGE_PATH:-./storage/azerothcore}"
SERVER_ADDRESS="${SERVER_ADDRESS:-127.0.0.1}"
SERVER_PORT="${REALM_PORT:-8085}"

echo "📋 Configuration Summary:"
echo "   Database: ${MYSQL_HOST}:${MYSQL_PORT}"
echo "   Auth DB: ${DB_AUTH_NAME}"
echo "   World DB: ${DB_WORLD_NAME}"
echo "   Characters DB: ${DB_CHARACTERS_NAME}"
echo "   Storage: ${STORAGE_PATH}"
echo "   Server: ${SERVER_ADDRESS}:${SERVER_PORT}"
echo ""

# Step 1: Update configuration files
echo "🔧 Step 1: Updating configuration files..."
if [ ! -x "./scripts/update-config.sh" ]; then
    echo "❌ Error: update-config.sh script not found or not executable"
    exit 1
fi

echo "password" | sudo -S STORAGE_PATH="${STORAGE_PATH}" ./scripts/update-config.sh
if [ $? -eq 0 ]; then
    echo "✅ Configuration files updated successfully"
else
    echo "❌ Failed to update configuration files"
    exit 1
fi

echo ""

# Step 2: Update realmlist table
echo "🌐 Step 2: Updating realmlist table..."
if [ ! -x "./scripts/update-realmlist.sh" ]; then
    echo "❌ Error: update-realmlist.sh script not found or not executable"
    exit 1
fi

./scripts/update-realmlist.sh
if [ $? -eq 0 ]; then
    echo "✅ Realmlist table updated successfully"
else
    echo "❌ Failed to update realmlist table"
    exit 1
fi

echo ""

# Step 3: Restart services to apply changes
echo "🔄 Step 3: Restarting services to apply changes..."
docker compose -f docker-compose-azerothcore-services.yml restart ac-authserver ac-worldserver

if [ $? -eq 0 ]; then
    echo "✅ Services restarted successfully"
else
    echo "❌ Failed to restart services"
    exit 1
fi

echo ""
echo "🎉 Post-installation setup completed successfully!"
echo ""
echo "📋 Summary of changes:"
echo "   ✅ AuthServer configured with production database settings"
echo "   ✅ WorldServer configured with production database settings"
echo "   ✅ Realmlist updated with server address: ${SERVER_ADDRESS}:${SERVER_PORT}"
echo "   ✅ Services restarted to apply changes"
echo ""
echo "🎮 Your AzerothCore server is now ready for production!"
echo "   Players can connect to: ${SERVER_ADDRESS}:${SERVER_PORT}"
echo ""
echo "💡 Next steps:"
echo "   1. Create admin accounts using the worldserver console"
echo "   2. Test client connectivity"
echo "   3. Configure any additional modules as needed"
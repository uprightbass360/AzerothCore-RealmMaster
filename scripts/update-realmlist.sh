#!/bin/bash

# AzerothCore Realmlist Update Script
# Updates the realmlist table with production server address and port

set -e

echo "🌐 AzerothCore Realmlist Update Script"
echo "======================================"

# Store any pre-existing environment variables
SAVED_SERVER_ADDRESS="$SERVER_ADDRESS"
SAVED_REALM_PORT="$REALM_PORT"

# Load environment variables from env file if it exists
if [ -f "docker-compose-azerothcore-services.env" ]; then
    echo "📂 Loading environment from docker-compose-azerothcore-services.env"
    set -a  # automatically export all variables
    source docker-compose-azerothcore-services.env
    set +a  # turn off automatic export
fi

# Restore command line variables if they were set
if [ -n "$SAVED_SERVER_ADDRESS" ]; then
    SERVER_ADDRESS="$SAVED_SERVER_ADDRESS"
    echo "🔧 Using command line SERVER_ADDRESS: $SERVER_ADDRESS"
fi
if [ -n "$SAVED_REALM_PORT" ]; then
    REALM_PORT="$SAVED_REALM_PORT"
    echo "🔧 Using command line REALM_PORT: $REALM_PORT"
fi

# Configuration variables from environment
MYSQL_HOST="${MYSQL_HOST:-ac-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-azerothcore123}"
DB_AUTH_NAME="${DB_AUTH_NAME:-acore_auth}"

# Server configuration - Loaded from environment file or command line
SERVER_ADDRESS="${SERVER_ADDRESS:-127.0.0.1}"
SERVER_PORT="${REALM_PORT:-8085}"
REALM_ID="${REALM_ID:-1}"

echo "📍 Database: ${MYSQL_HOST}:${MYSQL_PORT}/${DB_AUTH_NAME}"
echo "🌐 Server Address: ${SERVER_ADDRESS}:${SERVER_PORT}"
echo "🏰 Realm ID: ${REALM_ID}"

# Test database connection
echo "🔌 Testing database connection..."
docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -e "SELECT 1;" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Database connection successful"
else
    echo "❌ Database connection failed"
    exit 1
fi

# Check current realmlist entries
echo "📋 Current realmlist entries:"
docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -e "SELECT id, name, address, localAddress, localSubnetMask, port, icon, flag, timezone, allowedSecurityLevel, population, gamebuild FROM realmlist;"

# Check if realm ID exists before updating
echo "🔍 Checking if realm ID ${REALM_ID} exists..."
REALM_EXISTS=$(docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -se "SELECT COUNT(*) FROM realmlist WHERE id = ${REALM_ID};")
if [ "${REALM_EXISTS}" -eq 0 ]; then
    echo "❌ Error: Realm ID ${REALM_ID} does not exist in realmlist table"
    echo "💡 Available realm IDs:"
    docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -e "SELECT id, name FROM realmlist;"
    exit 1
fi

echo "✅ Realm ID ${REALM_ID} found"

# Check if update is needed (compare current values)
CURRENT_VALUES=$(docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -se "SELECT CONCAT(address, ':', port) FROM realmlist WHERE id = ${REALM_ID};")
TARGET_VALUES="${SERVER_ADDRESS}:${SERVER_PORT}"

if [ "${CURRENT_VALUES}" = "${TARGET_VALUES}" ]; then
    echo "ℹ️  Values already match target (${TARGET_VALUES}) - no update needed"
    echo "✅ Realmlist is already configured correctly"
else
    echo "🔧 Updating existing realm ID ${REALM_ID} from ${CURRENT_VALUES} to ${TARGET_VALUES}..."
    docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -e "UPDATE realmlist SET address = '${SERVER_ADDRESS}', port = ${SERVER_PORT} WHERE id = ${REALM_ID};"

    if [ $? -eq 0 ]; then
        # Verify the change was applied
        NEW_VALUES=$(docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -se "SELECT CONCAT(address, ':', port) FROM realmlist WHERE id = ${REALM_ID};")
        if [ "${NEW_VALUES}" = "${TARGET_VALUES}" ]; then
            echo "✅ Realmlist update successful (${CURRENT_VALUES} → ${NEW_VALUES})"
        else
            echo "❌ Update failed - values did not change (${NEW_VALUES})"
            exit 1
        fi
    else
        echo "❌ Failed to execute UPDATE statement"
        exit 1
    fi
fi

# Verify the update
echo "📋 Updated realmlist entries:"
docker exec ac-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_AUTH_NAME}" -e "SELECT id, name, address, localAddress, localSubnetMask, port, icon, flag, timezone, allowedSecurityLevel, population, gamebuild FROM realmlist WHERE id = ${REALM_ID};"

echo ""
echo "🎉 Realmlist update completed successfully!"
echo "📋 Summary:"
echo "   - Realm ID: ${REALM_ID}"
echo "   - Address: ${SERVER_ADDRESS}"
echo "   - Port: ${SERVER_PORT}"
echo ""
echo "💡 Players should now connect to: ${SERVER_ADDRESS}:${SERVER_PORT}"
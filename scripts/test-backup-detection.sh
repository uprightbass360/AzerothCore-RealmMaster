#!/bin/bash

# Test script to verify acore_playerbots database detection
# This script simulates the database detection logic without running an actual backup

set -e

# Configuration from environment variables
MYSQL_HOST=${MYSQL_HOST:-ac-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-password}

echo "=== Testing AzerothCore Database Detection ==="
echo ""

# Core databases
DATABASES=("acore_auth" "acore_world" "acore_characters")
echo "Core databases: ${DATABASES[@]}"

# Test if acore_playerbots database exists
echo ""
echo "Testing for acore_playerbots database..."

if mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD -e "USE acore_playerbots;" 2>/dev/null; then
    DATABASES+=("acore_playerbots")
    echo "✅ acore_playerbots database found - would be included in backup"
else
    echo "ℹ️  acore_playerbots database not found - would be skipped (this is normal for some installations)"
fi

echo ""
echo "Final database list that would be backed up: ${DATABASES[@]}"
echo ""

# Test connection to each database that would be backed up
echo "Testing connection to each database:"
for db in "${DATABASES[@]}"; do
    if mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD -e "USE $db; SELECT 'OK' as status;" 2>/dev/null | grep -q OK; then
        echo "✅ $db: Connection successful"
    else
        echo "❌ $db: Connection failed"
    fi
done

echo ""
echo "=== Database Detection Test Complete ==="
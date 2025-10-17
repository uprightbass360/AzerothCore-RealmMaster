#!/bin/bash
# ac-compose
set -e

echo "🚀 AzerothCore Auto Post-Install Configuration"
echo "=============================================="

# Install required packages
apk add --no-cache curl mysql-client bash docker-cli-compose jq || apk add --no-cache curl mysql-client bash jq

# Create install markers directory
mkdir -p /install-markers

# Check if this is a new installation
if [ -f "/install-markers/post-install-completed" ]; then
  echo "✅ Post-install configuration already completed"
  echo "ℹ️  Marker file found: /install-markers/post-install-completed"
  echo "🔄 To re-run post-install configuration, delete the marker file and restart this container"
  echo ""
  echo "🏃 Keeping container alive for manual operations..."
  tail -f /dev/null
else
  echo "🆕 New installation detected - running post-install configuration..."
  echo ""

  # Wait for services to be ready
  echo "⏳ Waiting for required services to be ready..."

  # Wait for MySQL to be responsive
  echo "🔌 Waiting for MySQL to be ready..."
  for i in $(seq 1 120); do
    if mysql -h "${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" --skip-ssl-verify -e "SELECT 1;" >/dev/null 2>&1; then
      echo "✅ MySQL is ready"
      break
    fi
    echo "   ⏳ Attempt $i/120..."
    sleep 5
  done

  # Wait for authserver and worldserver config files to exist
  echo "📁 Waiting for configuration files..."
  for i in $(seq 1 60); do
    if [ -f "/azerothcore/config/authserver.conf" ] && [ -f "/azerothcore/config/worldserver.conf" ]; then
      echo "✅ Configuration files found"
      break
    fi
    echo "   ⏳ Waiting for config files... attempt $i/60"
    sleep 5
  done

  if [ ! -f "/azerothcore/config/authserver.conf" ] || [ ! -f "/azerothcore/config/worldserver.conf" ]; then
    echo "❌ Configuration files not found after waiting"
    exit 1
  fi

  # Step 1: Update configuration files
  echo ""
  echo "🔧 Step 1: Updating configuration files..."

  # Update DB connection lines and any necessary settings directly with sed
  sed -i "s|^LoginDatabaseInfo *=.*|LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"|" /azerothcore/config/authserver.conf || true
  sed -i "s|^LoginDatabaseInfo *=.*|LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"|" /azerothcore/config/worldserver.conf || true
  sed -i "s|^WorldDatabaseInfo *=.*|WorldDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}\"|" /azerothcore/config/worldserver.conf || true
  sed -i "s|^CharacterDatabaseInfo *=.*|CharacterDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}\"|" /azerothcore/config/worldserver.conf || true

  echo "✅ Configuration files updated"

  # Step 2: Update realmlist table
  echo ""
  echo "🌐 Step 2: Updating realmlist table..."
  mysql -h "${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" --skip-ssl-verify "${DB_AUTH_NAME}" -e "
    UPDATE realmlist SET address='${SERVER_ADDRESS}', port=${REALM_PORT} WHERE id=1;
  " || echo "⚠️  Could not update realmlist table"

  echo "✅ Realmlist updated"

  echo ""
  echo "ℹ️  Step 3: (Optional) Restart services to apply changes — handled externally"

  # Create completion marker
  echo "$(date)" > /install-markers/post-install-completed
  echo "NEW_INSTALL_DATE=$(date)" >> /install-markers/post-install-completed
  echo "CONFIG_FILES_UPDATED=true" >> /install-markers/post-install-completed
  echo "REALMLIST_UPDATED=true" >> /install-markers/post-install-completed

  echo ""
  echo "🎉 Auto post-install configuration completed successfully!"
  echo ""
  tail -f /dev/null
fi

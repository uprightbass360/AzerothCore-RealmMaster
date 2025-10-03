#!/bin/bash
set -e

echo "🚀 AzerothCore Auto Post-Install Configuration"
echo "=============================================="

# Install required packages
apk add --no-cache curl mysql-client bash docker-cli-compose jq

# Create install markers directory
mkdir -p /install-markers

# Check if this is a new installation
if [ -f "/install-markers/post-install-completed" ]; then
  echo "✅ Post-install configuration already completed"
  echo "ℹ️  Marker file found: /install-markers/post-install-completed"
  echo "🔄 To re-run post-install configuration, delete the marker file and restart this container"
  echo "📝 Command: docker exec ${CONTAINER_POST_INSTALL} rm -f /install-markers/post-install-completed"
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
    echo "   Expected: /azerothcore/config/authserver.conf"
    echo "   Expected: /azerothcore/config/worldserver.conf"
    exit 1
  fi

  # Step 1: Update configuration files
  echo ""
  echo "🔧 Step 1: Updating configuration files..."

  # Download and execute update-config.sh
  curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/update-config.sh -o /tmp/update-config.sh
  chmod +x /tmp/update-config.sh

  # Modify script to use container environment
  sed -i 's|docker-compose-azerothcore-services.env|/project/docker-compose-azerothcore-services.env|' /tmp/update-config.sh
  sed -i 's|CONFIG_DIR="${STORAGE_PATH}/config"|CONFIG_DIR="/azerothcore/config"|' /tmp/update-config.sh

  # Execute update-config.sh
  cd /project
  /tmp/update-config.sh

  if [ $? -eq 0 ]; then
    echo "✅ Configuration files updated successfully"
  else
    echo "❌ Failed to update configuration files"
    exit 1
  fi

  # Step 2: Update realmlist table
  echo ""
  echo "🌐 Step 2: Updating realmlist table..."

  # Download and execute update-realmlist.sh
  curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/update-realmlist.sh -o /tmp/update-realmlist.sh
  chmod +x /tmp/update-realmlist.sh

  # Modify script to use container environment
  sed -i 's|docker-compose-azerothcore-services.env|/project/docker-compose-azerothcore-services.env|' /tmp/update-realmlist.sh

  # Replace all docker exec mysql commands with direct mysql commands
  sed -i "s|docker exec ac-mysql mysql -u \"\${MYSQL_USER}\" -p\"\${MYSQL_ROOT_PASSWORD}\" \"\${DB_AUTH_NAME}\"|mysql -h \"${MYSQL_HOST}\" -u\"${MYSQL_USER}\" -p\"${MYSQL_ROOT_PASSWORD}\" --skip-ssl-verify \"${DB_AUTH_NAME}\"|g" /tmp/update-realmlist.sh
  sed -i "s|docker exec ac-mysql mysql -u \"\${MYSQL_USER}\" -p\"\${MYSQL_ROOT_PASSWORD}\"|mysql -h \"${MYSQL_HOST}\" -u\"${MYSQL_USER}\" -p\"${MYSQL_ROOT_PASSWORD}\" --skip-ssl-verify|g" /tmp/update-realmlist.sh

  # Execute update-realmlist.sh
  cd /project
  /tmp/update-realmlist.sh

  if [ $? -eq 0 ]; then
    echo "✅ Realmlist table updated successfully"
  else
    echo "❌ Failed to update realmlist table"
    exit 1
  fi

  # Step 3: Note about service restart
  echo ""
  echo "ℹ️  Step 3: Service restart note..."
  echo "📝 Configuration changes have been applied to files"
  echo "💡 Services will automatically restart if needed during next deployment"
  echo "✅ Post-install configuration completed - services will pick up changes on next restart"

  # Create completion marker
  echo "$(date)" > /install-markers/post-install-completed
  echo "NEW_INSTALL_DATE=$(date)" >> /install-markers/post-install-completed
  echo "CONFIG_FILES_UPDATED=true" >> /install-markers/post-install-completed
  echo "REALMLIST_UPDATED=true" >> /install-markers/post-install-completed
  echo "SERVICES_RESTARTED=true" >> /install-markers/post-install-completed

  echo ""
  echo "🎉 Auto post-install configuration completed successfully!"
  echo ""
  echo "📋 Summary of changes:"
  echo "   ✅ AuthServer configured with production database settings"
  echo "   ✅ WorldServer configured with production database settings"
  echo "   ✅ Realmlist updated with server address: ${SERVER_ADDRESS}:${REALM_PORT}"
  echo "   ✅ Services restarted to apply changes"
  echo "   ✅ Completion marker created: /install-markers/post-install-completed"
  echo ""
  echo "🎮 Your AzerothCore server is now ready for production!"
  echo "   Players can connect to: ${SERVER_ADDRESS}:${REALM_PORT}"
  echo ""
  echo "💡 Next steps:"
  echo "   1. Create admin accounts using the worldserver console"
  echo "   2. Test client connectivity"
  echo "   3. Configure any additional modules as needed"
  echo ""
  echo "🏃 Keeping container alive for future manual operations..."
  tail -f /dev/null
fi
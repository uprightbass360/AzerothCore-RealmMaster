#!/bin/bash
# azerothcore-rm
set -e

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

show_post_install_header(){
  echo -e "\n${BLUE}    ⚔️  REALM POST-INSTALL CONFIGURATION  ⚔️${NC}"
  echo -e "${BLUE}    ══════════════════════════════════════════${NC}"
  echo -e "${BLUE}         🏯 Blessing Your Realm with Final Touches 🏯${NC}\n"
}

show_post_install_header

# Install required packages
apk add --no-cache curl mysql-client bash docker-cli-compose jq || apk add --no-cache curl mysql-client bash jq

ensure_playerbots_db(){
  local db_name="${DB_PLAYERBOTS_NAME:-acore_playerbots}"
  local charset="${MYSQL_CHARACTER_SET:-utf8mb4}"
  local collation="${MYSQL_COLLATION:-utf8mb4_unicode_ci}"
  echo "🔐 Ensuring playerbots database '${db_name}' exists..."
  if mysql -h "${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" --skip-ssl-verify -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET ${charset} COLLATE ${collation};" >/dev/null 2>&1; then
    echo "✅ Playerbots database ready"
  else
    echo "⚠️  Failed to guarantee playerbots database"
  fi
}

update_playerbots_conf(){
  local target="$1"
  if [ ! -f "$target" ]; then
    return 0
  fi
  if sed -i "s|^PlayerbotsDatabaseInfo *=.*|PlayerbotsDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}\"|" "$target"; then
    echo "   🔁 Updated $(basename "$target")"
  else
    echo "   ⚠️  Could not update $(basename "$target")"
  fi
  return 0
}

# Create install markers directory
mkdir -p /install-markers

# Check if this is a new installation
if [ -f "/install-markers/post-install-completed" ]; then
  echo "✅ Post-install configuration already completed"
  echo "ℹ️  Marker file found: /install-markers/post-install-completed"
  echo "🔄 To re-run post-install configuration, delete the marker file and restart this container"
  echo "🏁 Nothing else to do; exiting."
  exit 0
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
      ensure_playerbots_db
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

  # Step 1: Create module configuration files
  echo ""
  echo "🔧 Step 1: Creating module configuration files..."

  # Create .conf files from .dist.conf templates for all modules
  CONFIG_DIR="/azerothcore/config"
  created_count=0

  for file in "$CONFIG_DIR"/*.dist; do
    if [ -f "$file" ]; then
      conffile=$(echo "$file" | sed 's/.dist$//')
      filename=$(basename "$conffile")

      # Skip core config files (already handled)
      case "$filename" in
        authserver.conf|worldserver.conf)
          continue
          ;;
        dbimport.conf)
          if [ ! -f "$conffile" ] || grep -q "Updates.ExceptionShutdownDelay" "$conffile"; then
            echo "   📝 Creating/refreshing $filename from $(basename "$file")"
            cp "$file" "$conffile"
          fi
          continue
          ;;
      esac

      # Create .conf file if it doesn't exist
      if [ ! -f "$conffile" ]; then
        echo "   📝 Creating $filename from $(basename "$file")"
        cp "$file" "$conffile"
        created_count=$((created_count + 1))
      fi
    fi
  done

  echo "   ✅ Created $created_count module configuration files"

  # Ensure module configuration files exist under modules directory
  MODULES_DIR="$CONFIG_DIR/modules"
  if [ -d "$MODULES_DIR" ]; then
    echo ""
    echo "   🔧 Creating module configs in modules/..."
    for file in "$MODULES_DIR"/*.conf.dist; do
      [ -f "$file" ] || continue
      target="${file%.dist}"
      if [ ! -f "$target" ]; then
        echo "      📝 Creating $(basename "$target") from $(basename "$file")"
        cp "$file" "$target"
      fi
    done
  fi

  # Step 2: Update configuration files
  echo ""
  echo "🔧 Step 2: Updating configuration files..."

  # Update DB connection lines and any necessary settings directly with sed
  sed -i "s|^LoginDatabaseInfo *=.*|LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"|" /azerothcore/config/authserver.conf || true
  sed -i "s|^LoginDatabaseInfo *=.*|LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"|" /azerothcore/config/worldserver.conf || true
  sed -i "s|^WorldDatabaseInfo *=.*|WorldDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}\"|" /azerothcore/config/worldserver.conf || true
  sed -i "s|^CharacterDatabaseInfo *=.*|CharacterDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}\"|" /azerothcore/config/worldserver.conf || true
  if [ -f "/azerothcore/config/dbimport.conf" ]; then
    sed -i "s|^LoginDatabaseInfo *=.*|LoginDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^WorldDatabaseInfo *=.*|WorldDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^CharacterDatabaseInfo *=.*|CharacterDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^PlayerbotsDatabaseInfo *=.*|PlayerbotsDatabaseInfo = \"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^MySQLExecutable *=.*|MySQLExecutable = \"/usr/bin/mysql\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^TempDir *=.*|TempDir = \"/azerothcore/env/dist/temp\"|" /azerothcore/config/dbimport.conf || true
    # Database reconnection settings
    sed -i "s|^Database\.Reconnect\.Seconds *=.*|Database.Reconnect.Seconds = ${DB_RECONNECT_SECONDS:-5}|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^Database\.Reconnect\.Attempts *=.*|Database.Reconnect.Attempts = ${DB_RECONNECT_ATTEMPTS:-5}|" /azerothcore/config/dbimport.conf || true
    # Update settings
    sed -i "s|^Updates\.AllowedModules *=.*|Updates.AllowedModules = \"${DB_UPDATES_ALLOWED_MODULES:-all}\"|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^Updates\.Redundancy *=.*|Updates.Redundancy = ${DB_UPDATES_REDUNDANCY:-1}|" /azerothcore/config/dbimport.conf || true
    # Worker thread settings
    sed -i "s|^LoginDatabase\.WorkerThreads *=.*|LoginDatabase.WorkerThreads = ${DB_LOGIN_WORKER_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^WorldDatabase\.WorkerThreads *=.*|WorldDatabase.WorkerThreads = ${DB_WORLD_WORKER_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^CharacterDatabase\.WorkerThreads *=.*|CharacterDatabase.WorkerThreads = ${DB_CHARACTER_WORKER_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
    # Synch thread settings
    sed -i "s|^LoginDatabase\.SynchThreads *=.*|LoginDatabase.SynchThreads = ${DB_LOGIN_SYNCH_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^WorldDatabase\.SynchThreads *=.*|WorldDatabase.SynchThreads = ${DB_WORLD_SYNCH_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
    sed -i "s|^CharacterDatabase\.SynchThreads *=.*|CharacterDatabase.SynchThreads = ${DB_CHARACTER_SYNCH_THREADS:-1}|" /azerothcore/config/dbimport.conf || true
  fi
  update_playerbots_conf /azerothcore/config/modules/playerbots.conf
  update_playerbots_conf /azerothcore/config/modules/playerbots.conf.dist

  ensure_config_key(){
    local file="$1"
    local key="$2"
    local value="$3"
    if [ ! -f "$file" ]; then
      return
    fi
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
      return
    fi
    echo "   ➕ Adding ${key} to $(basename "$file")"
    printf '\n%s = %s\n' "$key" "$value" >> "$file"
  }

  ensure_config_key /azerothcore/config/worldserver.conf "Account.Achievements.Excluded" "\"\""
  ensure_config_key /azerothcore/config/worldserver.conf "Playerbots.Updates.EnableDatabases" "1"
  ensure_config_key /azerothcore/config/worldserver.conf "PlayerbotsDatabaseInfo" "\"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}\""

  echo "✅ Configuration files updated"

  # Step 3: Update realmlist table
  echo ""
  echo "🌐 Step 3: Updating realmlist table..."
  mysql -h "${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_ROOT_PASSWORD}" --skip-ssl-verify "${DB_AUTH_NAME}" -e "
    UPDATE realmlist SET address='${SERVER_ADDRESS}', port=${REALM_PORT} WHERE id=1;
  " || echo "⚠️  Could not update realmlist table"

  echo "✅ Realmlist updated"

  echo ""
  echo "ℹ️  Step 4: (Optional) Restart services to apply changes — handled externally"

  # Create completion marker
  echo "$(date)" > /install-markers/post-install-completed
  echo "NEW_INSTALL_DATE=$(date)" >> /install-markers/post-install-completed
  echo "CONFIG_FILES_UPDATED=true" >> /install-markers/post-install-completed
  echo "REALMLIST_UPDATED=true" >> /install-markers/post-install-completed

  echo ""
  echo -e "${GREEN}⚔️ Your realm has been blessed and configured! ⚔️${NC}"
  echo -e "${GREEN}🏰 All post-installation rituals completed${NC}"
  echo -e "${GREEN}🗡️ Your realm awaits brave adventurers!${NC}"
  echo "🏁 Post-install tasks finished; exiting."
  exit 0
fi

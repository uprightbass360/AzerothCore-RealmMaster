#!/bin/bash
set -e

echo "🔧 Starting MySQL with NFS-compatible setup and auto-restore..."
mkdir -p /var/lib/mysql-runtime
chown -R mysql:mysql /var/lib/mysql-runtime
chmod 755 /var/lib/mysql-runtime

# Check if MySQL data directory is empty (fresh start)
if [ ! -d "/var/lib/mysql-runtime/mysql" ]; then
  echo "🆕 Fresh MySQL installation detected..."

  # Check for available backups (prefer daily, fallback to hourly, then legacy)
  if [ -d "/backups" ] && [ "$(ls -A /backups)" ]; then
    # Try daily backups first
    if [ -d "/backups/daily" ] && [ "$(ls -A /backups/daily)" ]; then
      LATEST_BACKUP=$(ls -1t /backups/daily | head -n 1)
      if [ -n "$LATEST_BACKUP" ] && [ -d "/backups/daily/$LATEST_BACKUP" ]; then
        echo "📦 Latest daily backup found: $LATEST_BACKUP"
        echo "🔄 Will restore after MySQL initializes..."
        export RESTORE_BACKUP="/backups/daily/$LATEST_BACKUP"
      fi
    # Try hourly backups second
    elif [ -d "/backups/hourly" ] && [ "$(ls -A /backups/hourly)" ]; then
      LATEST_BACKUP=$(ls -1t /backups/hourly | head -n 1)
      if [ -n "$LATEST_BACKUP" ] && [ -d "/backups/hourly/$LATEST_BACKUP" ]; then
        echo "📦 Latest hourly backup found: $LATEST_BACKUP"
        echo "🔄 Will restore after MySQL initializes..."
        export RESTORE_BACKUP="/backups/hourly/$LATEST_BACKUP"
      fi
    # Try legacy backup structure last
    else
      LATEST_BACKUP=$(ls -1t /backups | head -n 1)
      if [ -n "$LATEST_BACKUP" ] && [ -d "/backups/$LATEST_BACKUP" ]; then
        echo "📦 Latest legacy backup found: $LATEST_BACKUP"
        echo "🔄 Will restore after MySQL initializes..."
        export RESTORE_BACKUP="/backups/$LATEST_BACKUP"
      else
        echo "🆕 No valid backups found, will initialize fresh..."
      fi
    fi
  else
    echo "🆕 No backup directory found, will initialize fresh..."
  fi
else
  echo "📁 Existing MySQL data found, skipping restore..."
fi

echo "🚀 Starting MySQL server with custom datadir..."

# Start MySQL in background for potential restore
if [ -n "$RESTORE_BACKUP" ]; then
  echo "⚡ Starting MySQL in background for restore operation..."
  docker-entrypoint.sh mysqld \
    --datadir=/var/lib/mysql-runtime \
    --default-authentication-plugin=mysql_native_password \
    --character-set-server=${MYSQL_CHARACTER_SET} \
    --collation-server=${MYSQL_COLLATION} \
    --max_connections=${MYSQL_MAX_CONNECTIONS} \
    --innodb-buffer-pool-size=${MYSQL_INNODB_BUFFER_POOL_SIZE} \
    --innodb-log-file-size=${MYSQL_INNODB_LOG_FILE_SIZE} &

  MYSQL_PID=$!

  # Wait for MySQL to be ready
  echo "⏳ Waiting for MySQL to become ready for restore..."
  while ! mysqladmin ping -h localhost -u root --silent; do
    sleep 2
  done

  echo "🔄 MySQL ready, starting restore from $RESTORE_BACKUP..."

  # Install curl for downloading restore script
  apt-get update && apt-get install -y curl

  # Download restore script from GitHub
  curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/restore.sh -o /tmp/restore.sh
  chmod +x /tmp/restore.sh

  # Modify restore script to skip confirmation and use correct backup path
  sed -i 's/sleep 10/echo "Auto-restore mode, skipping confirmation..."/' /tmp/restore.sh
  sed -i 's/BACKUP_DIR=\${BACKUP_DIR:-\/backups}/BACKUP_DIR=\/backups/' /tmp/restore.sh
  sed -i 's/MYSQL_PASSWORD=\${MYSQL_PASSWORD:-password}/MYSQL_PASSWORD=${MYSQL_ROOT_PASSWORD}/' /tmp/restore.sh

  # Extract timestamp from backup path and run restore
  BACKUP_TIMESTAMP=$(basename "$RESTORE_BACKUP")
  echo "🗄️  Restoring databases from backup: $BACKUP_TIMESTAMP"
  /tmp/restore.sh "$BACKUP_TIMESTAMP"

  echo "✅ Database restore completed successfully!"

  # Keep MySQL running in foreground
  wait $MYSQL_PID
else
  # Normal startup without restore
  exec docker-entrypoint.sh mysqld \
    --datadir=/var/lib/mysql-runtime \
    --default-authentication-plugin=mysql_native_password \
    --character-set-server=${MYSQL_CHARACTER_SET} \
    --collation-server=${MYSQL_COLLATION} \
    --max_connections=${MYSQL_MAX_CONNECTIONS} \
    --innodb-buffer-pool-size=${MYSQL_INNODB_BUFFER_POOL_SIZE} \
    --innodb-log-file-size=${MYSQL_INNODB_LOG_FILE_SIZE}
fi
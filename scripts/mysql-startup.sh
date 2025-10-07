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

# Set defaults for any missing environment variables
MYSQL_CHARACTER_SET=${MYSQL_CHARACTER_SET:-utf8mb4}
MYSQL_COLLATION=${MYSQL_COLLATION:-utf8mb4_unicode_ci}
MYSQL_MAX_CONNECTIONS=${MYSQL_MAX_CONNECTIONS:-1000}
MYSQL_INNODB_BUFFER_POOL_SIZE=${MYSQL_INNODB_BUFFER_POOL_SIZE:-256M}
MYSQL_INNODB_LOG_FILE_SIZE=${MYSQL_INNODB_LOG_FILE_SIZE:-64M}

echo "📊 MySQL Configuration:"
echo "   Character Set: $MYSQL_CHARACTER_SET"
echo "   Collation: $MYSQL_COLLATION"
echo "   Max Connections: $MYSQL_MAX_CONNECTIONS"
echo "   Buffer Pool Size: $MYSQL_INNODB_BUFFER_POOL_SIZE"
echo "   Log File Size: $MYSQL_INNODB_LOG_FILE_SIZE"

# For now, skip restore and just start MySQL normally
# The restore functionality can be added back later once the basic stack is working
echo "🚀 Starting MySQL without restore for initial deployment..."

# Normal startup without restore
exec docker-entrypoint.sh mysqld \
  --datadir=/var/lib/mysql-runtime \
  --default-authentication-plugin=mysql_native_password \
  --character-set-server=$MYSQL_CHARACTER_SET \
  --collation-server=$MYSQL_COLLATION \
  --max_connections=$MYSQL_MAX_CONNECTIONS \
  --innodb-buffer-pool-size=$MYSQL_INNODB_BUFFER_POOL_SIZE \
  --innodb-log-file-size=$MYSQL_INNODB_LOG_FILE_SIZE
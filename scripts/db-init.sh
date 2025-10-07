#!/bin/bash
set -e

echo "🔧 Waiting for MySQL to be ready..."

# Wait for MySQL to be responsive with longer timeout
for i in $(seq 1 ${DB_WAIT_RETRIES}); do
  if mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ MySQL is responsive"
    break
  fi
  echo "⏳ Waiting for MySQL... attempt $i/${DB_WAIT_RETRIES}"
  sleep ${DB_WAIT_SLEEP}
done

# Check if we should restore from backup
if [ -f "/var/lib/mysql-persistent/backup.sql" ]; then
  echo "🔄 Restoring databases from backup..."
  mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} < /var/lib/mysql-persistent/backup.sql || {
    echo "⚠️ Backup restore failed, will create fresh databases"
  }
fi

echo "🗄️ Creating/verifying AzerothCore databases..."
mysql -h ${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "
CREATE DATABASE IF NOT EXISTS ${DB_AUTH_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
CREATE DATABASE IF NOT EXISTS ${DB_WORLD_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
CREATE DATABASE IF NOT EXISTS ${DB_CHARACTERS_NAME} DEFAULT CHARACTER SET ${MYSQL_CHARACTER_SET} COLLATE ${MYSQL_COLLATION};
SHOW DATABASES;
" || {
  echo "❌ Failed to create databases"
  exit 1
}
echo "✅ Databases ready!"
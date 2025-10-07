#!/bin/bash
set -e

echo 'Waiting for databases to be ready...'

# Wait for databases to exist with longer timeout
for i in $(seq 1 120); do
  if mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -e "USE ${DB_AUTH_NAME}; USE ${DB_WORLD_NAME}; USE ${DB_CHARACTERS_NAME};" >/dev/null 2>&1; then
    echo "✅ All databases accessible"
    break
  fi
  echo "⏳ Waiting for databases... attempt $i/120"
  sleep 5
done

echo 'Creating config file for dbimport...'
mkdir -p /azerothcore/env/dist/etc
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
Updates.EnableDatabases = 7
Updates.AutoSetup = 1
EOF

echo 'Running database import...'
cd /azerothcore/env/dist/bin
./dbimport

echo 'Database import complete!'
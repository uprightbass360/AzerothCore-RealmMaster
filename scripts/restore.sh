#!/bin/bash
set -e

MYSQL_HOST=${MYSQL_HOST:-ac-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-password}
BACKUP_DIR=${BACKUP_DIR:-/backups}

if [ -z "$1" ]; then
    echo "Usage: restore.sh <backup_timestamp>"
    echo "Available backups:"
    ls -la $BACKUP_DIR/ | grep "^d" | grep "[0-9]"
    exit 1
fi

TIMESTAMP=$1
BACKUP_SUBDIR="$BACKUP_DIR/$TIMESTAMP"

if [ ! -d "$BACKUP_SUBDIR" ]; then
    echo "❌ Backup not found: $BACKUP_SUBDIR"
    exit 1
fi

echo "⚠️  WARNING: This will overwrite existing databases!"
echo "Restoring from backup: $TIMESTAMP"
echo "Press Ctrl+C within 10 seconds to cancel..."
sleep 10

# Restore databases
for backup_file in $BACKUP_SUBDIR/*.sql.gz; do
    if [ -f "$backup_file" ]; then
        echo "Restoring $backup_file..."
        zcat "$backup_file" | mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD
        echo "✅ Restored $(basename $backup_file)"
    fi
done

echo "✅ Database restore completed"
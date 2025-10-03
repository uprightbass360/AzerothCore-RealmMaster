#!/bin/bash
set -e

# Configuration from environment variables
MYSQL_HOST=${MYSQL_HOST:-ac-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-password}
BACKUP_DIR="/backups"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
DATE_FORMAT="%Y%m%d_%H%M%S"

# Database names
DATABASES=("acore_auth" "acore_world" "acore_characters")

# Create backup directory
mkdir -p $BACKUP_DIR

# Generate timestamp
TIMESTAMP=$(date +$DATE_FORMAT)
BACKUP_SUBDIR="$BACKUP_DIR/$TIMESTAMP"
mkdir -p $BACKUP_SUBDIR

echo "[$TIMESTAMP] Starting AzerothCore database backup..."

# Backup each database
for db in "${DATABASES[@]}"; do
    echo "[$TIMESTAMP] Backing up database: $db"
    mysqldump -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD \
        --single-transaction --routines --triggers --events \
        --hex-blob --quick --lock-tables=false \
        --add-drop-database --databases $db \
        | gzip > $BACKUP_SUBDIR/${db}.sql.gz

    if [ $? -eq 0 ]; then
        SIZE=$(du -h $BACKUP_SUBDIR/${db}.sql.gz | cut -f1)
        echo "[$TIMESTAMP] ✅ Successfully backed up $db ($SIZE)"
    else
        echo "[$TIMESTAMP] ❌ Failed to backup $db"
        exit 1
    fi
done

# Create backup manifest
cat > $BACKUP_SUBDIR/manifest.json <<EOF
{
    "timestamp": "$TIMESTAMP",
    "databases": ["${DATABASES[@]}"],
    "backup_size": "$(du -sh $BACKUP_SUBDIR | cut -f1)",
    "retention_days": $RETENTION_DAYS,
    "mysql_version": "$(mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'SELECT VERSION();' -s -N)"
}
EOF

# Clean up old backups based on retention policy
echo "[$TIMESTAMP] Cleaning up backups older than $RETENTION_DAYS days..."
find $BACKUP_DIR -type d -name "[0-9]*" -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

# Log backup completion
echo "[$TIMESTAMP] ✅ Backup completed successfully"
echo "[$TIMESTAMP] Backup location: $BACKUP_SUBDIR"
echo "[$TIMESTAMP] Current backups:"
ls -la $BACKUP_DIR/
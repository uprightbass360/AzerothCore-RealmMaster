#!/bin/bash
set -e

# Configuration from environment variables
MYSQL_HOST=${MYSQL_HOST:-ac-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-password}
BACKUP_DIR="/backups"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-3}
DATE_FORMAT="%Y%m%d_%H%M%S"

# Database names from environment variables
DATABASES=("${DB_AUTH_NAME:-acore_auth}" "${DB_WORLD_NAME:-acore_world}" "${DB_CHARACTERS_NAME:-acore_characters}")

# Create daily backup directory
DAILY_DIR="$BACKUP_DIR/daily"
mkdir -p $DAILY_DIR

# Generate timestamp
TIMESTAMP=$(date +$DATE_FORMAT)
BACKUP_SUBDIR="$DAILY_DIR/$TIMESTAMP"
mkdir -p $BACKUP_SUBDIR

echo "[$TIMESTAMP] Starting AzerothCore daily backup..."

# Backup each database with additional options for daily backups
for db in "${DATABASES[@]}"; do
    echo "[$TIMESTAMP] Backing up database: $db"
    mysqldump -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD \
        --single-transaction --routines --triggers --events \
        --hex-blob --quick --lock-tables=false \
        --add-drop-database --databases $db \
        --master-data=2 --flush-logs \
        | gzip > $BACKUP_SUBDIR/${db}.sql.gz

    if [ $? -eq 0 ]; then
        SIZE=$(du -h $BACKUP_SUBDIR/${db}.sql.gz | cut -f1)
        echo "[$TIMESTAMP] ✅ Successfully backed up $db ($SIZE)"
    else
        echo "[$TIMESTAMP] ❌ Failed to backup $db"
        exit 1
    fi
done

# Create comprehensive backup manifest for daily backups
BACKUP_SIZE=$(du -sh $BACKUP_SUBDIR | cut -f1)
MYSQL_VERSION=$(mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'SELECT VERSION();' -s -N)

cat > $BACKUP_SUBDIR/manifest.json <<EOF
{
    "timestamp": "$TIMESTAMP",
    "type": "daily",
    "databases": ["${DATABASES[@]}"],
    "backup_size": "$BACKUP_SIZE",
    "retention_days": $RETENTION_DAYS,
    "mysql_version": "$MYSQL_VERSION",
    "backup_method": "mysqldump with master-data and flush-logs",
    "created_by": "acore-compose2 backup system"
}
EOF

# Create database statistics for daily backups
echo "[$TIMESTAMP] Generating database statistics..."
for db in "${DATABASES[@]}"; do
    echo "[$TIMESTAMP] Statistics for $db:"
    mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD -e "
        SELECT
            TABLE_SCHEMA as 'Database',
            COUNT(*) as 'Tables',
            ROUND(SUM(DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as 'Size_MB'
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = '$db'
        GROUP BY TABLE_SCHEMA;
    " >> $BACKUP_SUBDIR/database_stats.txt
done

# Clean up old daily backups (keep only last N days)
echo "[$TIMESTAMP] Cleaning up daily backups older than $RETENTION_DAYS days..."
find $DAILY_DIR -type d -name "[0-9]*" -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

# Log backup completion
echo "[$TIMESTAMP] ✅ Daily backup completed successfully"
echo "[$TIMESTAMP] Backup location: $BACKUP_SUBDIR"
echo "[$TIMESTAMP] Backup size: $BACKUP_SIZE"
echo "[$TIMESTAMP] Current daily backups:"
ls -la $DAILY_DIR/ | tail -n +2
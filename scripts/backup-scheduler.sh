#!/bin/bash
set -e

echo "🔧 Starting enhanced backup service with hourly and daily schedules..."

# Install curl if not available (handle different package managers)
microdnf install -y curl || yum install -y curl || apt-get update && apt-get install -y curl

# Download backup scripts from GitHub
echo "📥 Downloading backup scripts from GitHub..."
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/backup.sh -o /tmp/backup.sh
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/backup-hourly.sh -o /tmp/backup-hourly.sh
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/backup-daily.sh -o /tmp/backup-daily.sh
chmod +x /tmp/backup.sh /tmp/backup-hourly.sh /tmp/backup-daily.sh

# Wait for MySQL to be ready before starting backup service
echo "⏳ Waiting for MySQL to be ready..."
sleep 30

# Run initial daily backup
echo "🚀 Running initial daily backup..."
/tmp/backup-daily.sh

# Enhanced scheduler with hourly and daily backups
echo "⏰ Starting enhanced backup scheduler:"
echo "   📅 Daily backups: ${BACKUP_DAILY_TIME}:00 UTC (retention: ${BACKUP_RETENTION_DAYS} days)"
echo "   ⏰ Hourly backups: every hour (retention: ${BACKUP_RETENTION_HOURS} hours)"

# Track last backup times to avoid duplicates
last_daily_hour=""
last_hourly_minute=""

while true; do
  current_hour=$(date +%H)
  current_minute=$(date +%M)
  current_time="$current_hour:$current_minute"

  # Daily backup check (configurable time)
  if [ "$current_hour" = "${BACKUP_DAILY_TIME}" ] && [ "$current_minute" = "00" ] && [ "$last_daily_hour" != "$current_hour" ]; then
    echo "📅 [$(date)] Daily backup time reached, running daily backup..."
    /tmp/backup-daily.sh
    last_daily_hour="$current_hour"
    # Sleep for 2 minutes to avoid running multiple times
    sleep 120
  # Hourly backup check (every hour at minute 0, except during daily backup)
  elif [ "$current_minute" = "00" ] && [ "$current_hour" != "${BACKUP_DAILY_TIME}" ] && [ "$last_hourly_minute" != "$current_minute" ]; then
    echo "⏰ [$(date)] Hourly backup time reached, running hourly backup..."
    /tmp/backup-hourly.sh
    last_hourly_minute="$current_minute"
    # Sleep for 2 minutes to avoid running multiple times
    sleep 120
  else
    # Sleep for 1 minute before checking again
    sleep 60
  fi
done
# Enhanced Backup Detection and Restoration System

## Overview

This enhanced system provides intelligent backup detection and conditional database import to prevent data loss and streamline AzerothCore startup.

## Key Improvements

### 1. Smart Backup Detection
- **Multiple backup formats supported**: Legacy single-file, timestamped directories, daily/hourly backups
- **Automatic latest backup selection**: Prioritizes daily → hourly → legacy backups
- **Backup validation**: Verifies SQL file integrity before restoration
- **Fallback logic**: Tries multiple backup sources if one fails

### 2. Conditional Database Import
- **Restoration-aware**: Skips import entirely if backup was successfully restored
- **Data protection**: Prevents overwriting restored data with fresh schema
- **Status tracking**: Uses marker files to communicate between services
- **Verification**: Checks database population before and after operations

### 3. Status Communication System
- **Restoration markers**:
  - `.restore-completed`: Backup successfully restored, skip import
  - `.restore-failed`: No backup found, proceed with import
  - `.import-completed`: Fresh database import successful
  - `.import-failed`: Import process failed

## File Structure

```
scripts/
├── db-init-enhanced.sh      # Enhanced database initialization
├── db-import-conditional.sh # Conditional database import
└── (original files remain unchanged)

docker-compose-azerothcore-database.yml # Updated to use enhanced scripts
```

## Startup Flow

### Original Flow (Data Loss Risk)
```
MySQL Start → db-init → restore backup → db-import → OVERWRITE with fresh data ❌
```

### Enhanced Flow (Data Protection)
```
MySQL Start → db-init-enhanced → detect backups
├── Backup found → restore → mark success → db-import → SKIP ✅
└── No backup → create empty → mark failed → db-import → POPULATE ✅
```

## Backup Detection Priority

1. **Legacy backup**: `/var/lib/mysql-persistent/backup.sql`
2. **Daily backups**: `/backups/daily/{timestamp}/`
3. **Hourly backups**: `/backups/hourly/{timestamp}/`
4. **Legacy timestamped**: `/backups/{timestamp}/`

## Configuration Changes

### Updated Docker Compose Service: `ac-db-init`
- Added backup volume mount: `${HOST_BACKUP_PATH}:/backups`
- Changed script URL to use `db-init-enhanced.sh`

### Updated Docker Compose Service: `ac-db-import`
- Added persistent volume mount: `${STORAGE_PATH}/mysql-data:/var/lib/mysql-persistent`
- Replaced default dbimport entrypoint with conditional script
- Added environment variables for database connection

## Status Markers

Located in `/var/lib/mysql-persistent/`:

### `.restore-completed`
```
2023-10-12 10:30:15: Backup successfully restored
```
**Effect**: db-import service exits immediately without importing

### `.restore-failed`
```
2023-10-12 10:30:15: No backup restored - fresh databases created
```
**Effect**: db-import service proceeds with fresh data population

### `.import-completed`
```
2023-10-12 10:35:20: Database import completed successfully
```
**Effect**: Confirms successful fresh database population

## Benefits

1. **Data Loss Prevention**: Never overwrites restored backups
2. **Faster Startup**: Skips unnecessary import when restoring from backup
3. **Automatic Detection**: No manual intervention required
4. **Backward Compatibility**: Works with existing backup formats
5. **Status Visibility**: Clear indicators of what happened during startup
6. **Validation**: Verifies backup integrity and import success

## Migration from Original System

### Automatic Migration
- Enhanced scripts are backward compatible
- Existing backup structures continue to work
- No data migration required

### Deployment
1. Update docker-compose file to use enhanced scripts
2. Restart database layer: `docker-compose -f docker-compose-azerothcore-database.yml up`
3. Monitor logs for backup detection and restoration status

## Troubleshooting

### Check Status Markers
```bash
# Check what happened during last startup
ls -la ./storage/azerothcore/mysql-data/.restore-* .import-*

# View status details
cat ./storage/azerothcore/mysql-data/.restore-completed
cat ./storage/azerothcore/mysql-data/.import-completed
```

### Force Fresh Import
```bash
# Remove restoration markers to force fresh import
rm -f ./storage/azerothcore/mysql-data/.restore-*
docker-compose -f docker-compose-azerothcore-database.yml restart ac-db-import
```

### Force Backup Detection
```bash
# Restart db-init to re-run backup detection
docker-compose -f docker-compose-azerothcore-database.yml restart ac-db-init
```

## Security Considerations

- Backup validation prevents execution of malicious SQL
- Status markers are read-only after creation
- No additional network exposure
- Maintains existing access controls

## Performance Impact

- **Positive**: Reduces startup time when restoring from backup
- **Minimal**: Backup detection adds ~5-10 seconds to cold start
- **Optimized**: Only scans backup directories when needed
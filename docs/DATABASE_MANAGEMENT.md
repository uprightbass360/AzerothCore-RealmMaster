# AzerothCore Database Management Guide

**Version:** 1.0
**Last Updated:** 2025-01-14

This guide covers all aspects of database management in your AzerothCore deployment, including backups, restores, migrations, and troubleshooting.

---

## Table of Contents

- [Overview](#overview)
- [Database Structure](#database-structure)
- [Backup System](#backup-system)
- [Restore Procedures](#restore-procedures)
- [Health Monitoring](#health-monitoring)
- [Module SQL Management](#module-sql-management)
- [Migration & Upgrades](#migration--upgrades)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

### Databases in AzerothCore

Your server uses four primary databases:

| Database | Purpose | Size (typical) |
|----------|---------|----------------|
| **acore_auth** | Account authentication, realm list | Small (< 50MB) |
| **acore_world** | Game world data (creatures, quests, items) | Large (1-3GB) |
| **acore_characters** | Player character data | Medium (100MB-1GB) |
| **acore_playerbots** | Playerbot AI data (if enabled) | Small (< 100MB) |

### Update System

AzerothCore uses a built-in update system that:
- Automatically detects and applies SQL updates on server startup
- Tracks applied updates in the `updates` table (in each database)
- Uses SHA1 hashes to prevent duplicate execution
- Supports module-specific updates

---

## Database Structure

### Core Tables by Database

**Auth Database (acore_auth)**
- `account` - User accounts
- `account_access` - GM permissions
- `realmlist` - Server realm configuration
- `updates` - Applied SQL updates

**World Database (acore_world)**
- `creature` - NPC spawns
- `gameobject` - Object spawns
- `quest_template` - Quest definitions
- `item_template` - Item definitions
- `updates` - Applied SQL updates

**Characters Database (acore_characters)**
- `characters` - Player characters
- `item_instance` - Player items
- `character_spell` - Character spells
- `character_inventory` - Equipped/bagged items
- `updates` - Applied SQL updates

### Updates Table Structure

Every database has an `updates` table:

```sql
CREATE TABLE `updates` (
  `name` varchar(200) NOT NULL,           -- Filename (e.g., 2025_01_14_00.sql)
  `hash` char(40) DEFAULT '',             -- SHA1 hash of file
  `state` enum('RELEASED','CUSTOM','MODULE','ARCHIVED','PENDING'),
  `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP,
  `speed` int unsigned DEFAULT '0',       -- Execution time (ms)
  PRIMARY KEY (`name`)
);
```

**Update States:**
- `RELEASED` - Official AzerothCore updates
- `MODULE` - Module-specific updates
- `CUSTOM` - Your custom SQL changes
- `ARCHIVED` - Historical updates (consolidated)
- `PENDING` - Queued for application

---

## Backup System

### Automated Backups

The system automatically creates backups on two schedules:

**Hourly Backups**
- Frequency: Every N minutes (default: 60)
- Retention: Last N hours (default: 6)
- Location: `storage/backups/hourly/YYYYMMDD_HHMMSS/`

**Daily Backups**
- Frequency: Once per day at configured hour (default: 09:00)
- Retention: Last N days (default: 3)
- Location: `storage/backups/daily/YYYYMMDD_HHMMSS/`

### Configuration

Edit `.env` to configure backup settings:

```bash
# Backup intervals
BACKUP_INTERVAL_MINUTES=60          # Hourly backup frequency
BACKUP_RETENTION_HOURS=6            # How many hourly backups to keep
BACKUP_RETENTION_DAYS=3             # How many daily backups to keep
BACKUP_DAILY_TIME=09                # Daily backup hour (00-23)

# Additional databases
BACKUP_EXTRA_DATABASES=""           # Comma-separated list
```

### Manual Backups

Create an on-demand backup:

```bash
./scripts/bash/manual-backup.sh --label my-backup-name
```

Options:
- `--label NAME` - Custom backup name
- `--container NAME` - Backup container name (default: ac-backup)

Output location: `manual-backups/LABEL_YYYYMMDD_HHMMSS/`

### Export Backups

Create a portable backup for migration:

```bash
./scripts/bash/backup-export.sh \
  --password YOUR_MYSQL_PASSWORD \
  --auth-db acore_auth \
  --characters-db acore_characters \
  --world-db acore_world \
  --db auth,characters,world \
  -o ./export-location
```

This creates: `ExportBackup_YYYYMMDD_HHMMSS/` with:
- Compressed SQL files (.sql.gz)
- manifest.json (metadata)

---

## Restore Procedures

### Automatic Restore on Startup

The system automatically detects and restores backups on first startup:

1. Searches for backups in priority order:
   - `/backups/daily/` (latest)
   - `/backups/hourly/` (latest)
   - `storage/backups/ExportBackup_*/`
   - `manual-backups/`

2. If backup found:
   - Restores all databases
   - Marks restoration complete
   - Skips schema import

3. If no backup:
   - Creates fresh databases
   - Runs `dbimport` to populate schemas
   - Applies all pending updates

### Restore Safety Checks & Sentinels

Because MySQL stores its hot data in a tmpfs (`/var/lib/mysql-runtime`) while persisting the durable files inside the Docker volume `mysql-data` (mounted at `/var/lib/mysql-persistent`), it is possible for the runtime data to be wiped (for example, after a host reboot) while the sentinel `.restore-completed` file still claims the databases are ready. To prevent the worldserver and authserver from entering restart loops, the `ac-db-import` workflow now performs an explicit sanity check before trusting those markers:

- The import script queries MySQL for the combined table count across `acore_auth`, `acore_world`, and `acore_characters`.
- If **any tables exist**, the script logs `Backup restoration completed successfully` and skips the expensive restore just as before.
- If **no tables are found or the query fails**, the script logs `Restoration marker found, but databases are empty - forcing re-import`, automatically clears the stale marker, and reruns the backup restore + `dbimport` pipeline so services always start with real data.

On graceful shutdown, the MySQL container now syncs the tmpfs datadir back into `/var/lib/mysql-persistent` so a normal restart keeps the latest state. Unclean shutdowns (host reboot, OOM kill) can still lose recent changes, so the backup restore path remains the safety net.

To complement that one-shot safety net, the long-running `ac-db-guard` service now watches the runtime tmpfs. It polls MySQL, and if it ever finds those schemas empty (the usual symptom after a daemon restart), it automatically reruns `db-import-conditional.sh` to rehydrate from the most recent backup before marking itself healthy. All auth/world services now depend on `ac-db-guard`'s health check, guaranteeing that AzerothCore never boots without real tables in memory. The guard also mounts the working SQL tree from `local-storage/source/azerothcore-playerbots/data/sql` into the db containers so that every `dbimport` run uses the exact SQL that matches your checked-out source, even if the Docker image was built earlier.

Because new features sometimes require schema changes even when the databases already contain data, `ac-db-guard` now performs a `dbimport` verification sweep (configurable via `DB_GUARD_VERIFY_INTERVAL_SECONDS`) to proactively apply any outstanding updates from the mounted SQL tree. By default it runs once per bootstrap and then every 24 hours, so the auth/world servers always see the columns/tables expected by their binaries without anyone having to run host scripts manually.

Manual intervention is only required if you intentionally want to force a fresh import despite having data. In that scenario:

1. Stop the stack: `docker compose down`
2. Delete the sentinel inside the volume: `docker run --rm -v mysql-data:/var/lib/mysql-persistent alpine sh -c 'rm -f /var/lib/mysql-persistent/.restore-completed'`
3. Run `docker compose run --rm ac-db-import`

See [docs/ADVANCED.md#database-hardening](ADVANCED.md#database-hardening) for more background on the tmpfs/persistent split and why the sentinel exists, and review [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md#database-connection-issues) for quick steps when the automation logs the warning above.

### Manual Restore

**Restore from backup directory:**

```bash
./scripts/bash/backup-import.sh \
  --backup-dir ./storage/backups/ExportBackup_20250114_120000 \
  --password YOUR_MYSQL_PASSWORD \
  --auth-db acore_auth \
  --characters-db acore_characters \
  --world-db acore_world \
  --all
```

**Selective restore (only specific databases):**

```bash
./scripts/bash/backup-import.sh \
  --backup-dir ./path/to/backup \
  --password YOUR_PASSWORD \
  --db characters \
  --characters-db acore_characters
```

**Skip specific databases:**

```bash
./scripts/bash/backup-import.sh \
  --backup-dir ./path/to/backup \
  --password YOUR_PASSWORD \
  --all \
  --skip world
```

### Merge Backups (Advanced)

Merge accounts/characters from another server:

```bash
./scripts/bash/backup-merge.sh \
  --backup-dir ../old-server/backup \
  --password YOUR_PASSWORD \
  --all-accounts \
  --all-characters \
  --exclude-bots
```

This intelligently:
- Remaps GUIDs to avoid conflicts
- Preserves existing data
- Imports character progression (spells, talents, etc.)
- Handles item instances

Options:
- `--all-accounts` - Import all accounts
- `--all-characters` - Import all characters
- `--exclude-bots` - Skip playerbot characters
- `--account "name1,name2"` - Import specific accounts
- `--dry-run` - Show what would be imported

---

## Health Monitoring

### Database Health Check

Check overall database health:

```bash
./scripts/bash/db-health-check.sh
```

Output includes:
- ✅ Database status (exists, responsive)
- 📊 Update counts (released, module, custom)
- 🕐 Last update timestamp
- 💾 Database sizes
- 📦 Module update summary
- 👥 Account/character counts

**Options:**
- `-v, --verbose` - Show detailed information
- `-p, --pending` - Show pending updates
- `-m, --no-modules` - Hide module updates
- `-c, --container NAME` - Specify MySQL container

**Example output:**

```
🗄️  AZEROTHCORE DATABASE HEALTH CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🗄️  Database Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✅ Auth DB (acore_auth)
     🔄 Updates: 45 applied
     🕐 Last update: 2025-01-14 14:30:22
     💾 Size: 12.3 MB (23 tables)

  ✅ World DB (acore_world)
     🔄 Updates: 1,234 applied (15 module)
     🕐 Last update: 2025-01-14 14:32:15
     💾 Size: 2.1 GB (345 tables)

  ✅ Characters DB (acore_characters)
     🔄 Updates: 89 applied
     🕐 Last update: 2025-01-14 14:31:05
     💾 Size: 180.5 MB (67 tables)

📊 Server Statistics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ℹ️  Accounts: 25
  ℹ️  Characters: 145
  ℹ️  Active (24h): 8

💾 Total Database Storage: 2.29 GB
```

### Backup Status

Check backup system status:

```bash
./scripts/bash/backup-status.sh
```

Shows:
- Backup tier summary (hourly, daily, manual)
- Latest backup timestamps
- Storage usage
- Next scheduled backups

**Options:**
- `-d, --details` - Show all available backups
- `-t, --trends` - Show size trends over time

### Query Applied Updates

Check which updates have been applied:

```sql
-- Show all updates for world database
USE acore_world;
SELECT name, state, timestamp FROM updates ORDER BY timestamp DESC LIMIT 20;

-- Show only module updates
SELECT name, state, timestamp FROM updates WHERE state='MODULE' ORDER BY timestamp DESC;

-- Count updates by state
SELECT state, COUNT(*) as count FROM updates GROUP BY state;
```

---

## Module SQL Management

### How Module SQL Works

When you enable a module that includes SQL changes:

1. **Module Installation:** Module is cloned to `modules/<module-name>/`
2. **SQL Detection:** SQL files are found in `data/sql/{base,updates,custom}/`
3. **SQL Staging:** SQL is copied to AzerothCore's update directories
4. **Auto-Application:** On next server startup, SQL is auto-applied
5. **Tracking:** Updates are tracked in `updates` table with `state='MODULE'`

### Module SQL Structure

Modules follow this structure:

```
modules/mod-example/
└── data/
    └── sql/
        ├── base/              # Initial schema (runs once)
        │   ├── db_auth/
        │   ├── db_world/
        │   └── db_characters/
        ├── updates/           # Incremental updates
        │   ├── db_auth/
        │   ├── db_world/
        │   └── db_characters/
        └── custom/            # Optional custom SQL
            └── db_world/
```

### Verifying Module SQL

Check if module SQL was applied:

```bash
# Run health check with module details
./scripts/bash/db-health-check.sh --verbose

# Or query directly
mysql -e "SELECT * FROM acore_world.updates WHERE name LIKE '%mod-example%'"
```

### Manual SQL Execution

If you need to run SQL manually:

```bash
# Connect to database
docker exec -it ac-mysql mysql -uroot -p

# Select database
USE acore_world;

# Run your SQL
SOURCE /path/to/your/file.sql;

# Or pipe from host
docker exec -i ac-mysql mysql -uroot -pPASSWORD acore_world < yourfile.sql
```

### Module SQL Staging

`./scripts/bash/stage-modules.sh` recopies every enabled module SQL file into `/azerothcore/data/sql/updates/{db_world,db_characters,db_auth}` each time it runs. Files are named deterministically (`MODULE_mod-name_file.sql`) and left on disk permanently. AzerothCore’s auto-updater consults the `updates` tables to decide whether a script needs to run; if it already ran, the entry in `updates` prevents a reapply, but leaving the file in place avoids “missing history” warnings and provides a clear audit trail.

### Restore-Time SQL Reconciliation

During a backup restore the `ac-db-import` service now runs `scripts/bash/restore-and-stage.sh`, which simply drops `storage/modules/.modules-meta/.restore-prestaged`. On the next `./scripts/bash/stage-modules.sh --yes`, the script sees the flag, clears any previously staged files, and recopies every enabled SQL file before worldserver boots. Because the files are always present, AzerothCore’s updater has the complete history it needs to apply or skip scripts correctly—no hash/ledger bookkeeping required.

This snapshot-driven workflow means restoring a new backup automatically replays any newly added module SQL while avoiding duplicate inserts for modules that were already present. See **[docs/ADVANCED.md](ADVANCED.md)** for a deeper look at the marker workflow and container responsibilities.

### Forcing a Module SQL Re-stage

If you intentionally need to reapply all module SQL (for example after manually cleaning tables):

1. Stop services: `docker compose down`
2. (Optional) Drop the relevant records from the `updates` table if you want AzerothCore to rerun them, e.g.:
   ```bash
   docker exec -it ac-mysql mysql -uroot -p \
     -e "DELETE FROM acore_characters.updates WHERE name LIKE '%MODULE_mod-ollama-chat%';"
   ```
3. Run `./scripts/bash/stage-modules.sh --yes`

Only perform step 3 if you understand the impact—deleting entries causes worldserver to execute those SQL scripts again on next startup.

---

## Migration & Upgrades

### Upgrading from Older Backups

When restoring an older backup to a newer AzerothCore version:

1. **Restore the backup** as normal
2. **Verification happens automatically** - The system runs `dbimport` after restore
3. **Missing updates are applied** - Any new schema changes are detected and applied
4. **Check for errors** in worldserver logs

### Manual Migration Steps

If automatic migration fails:

```bash
# 1. Backup current state
./scripts/bash/manual-backup.sh --label pre-migration

# 2. Run dbimport manually
docker exec -it ac-worldserver /bin/bash
cd /azerothcore/env/dist/bin
./dbimport

# 3. Check for errors
tail -f /azerothcore/env/dist/logs/DBErrors.log

# 4. Verify with health check
./scripts/bash/db-health-check.sh --verbose --pending
```

### Schema Version Checking

Check your database version:

```sql
-- World database version
SELECT * FROM acore_world.version;

-- Check latest update
SELECT name, timestamp FROM acore_world.updates ORDER BY timestamp DESC LIMIT 1;
```

---

## Troubleshooting

### Database Won't Start

**Symptom:** MySQL container keeps restarting

**Solutions:**

1. Check logs:
```bash
docker logs ac-mysql
```

2. Check disk space:
```bash
df -h
```

3. Reset MySQL data (WARNING: deletes all data):
```bash
docker-compose down
rm -rf storage/mysql/*
docker-compose up -d
```

### Updates Not Applying

**Symptom:** SQL updates in `pending_db_*` not getting applied

**Solutions:**

1. Check `Updates.EnableDatabases` setting:
```bash
grep "Updates.EnableDatabases" storage/config/worldserver.conf
# Should be 7 (auth+char+world) or 15 (all including playerbots)
```

2. Check for SQL errors:
```bash
docker logs ac-worldserver | grep -i "sql error"
```

3. Manually run dbimport:
```bash
docker exec -it ac-worldserver /bin/bash
cd /azerothcore/env/dist/bin
./dbimport
```

### Backup Restore Fails

**Symptom:** Backup import reports errors

**Solutions:**

1. Verify backup integrity:
```bash
./scripts/bash/verify-backup-complete.sh /path/to/backup
```

2. Check SQL file format:
```bash
zcat backup.sql.gz | head -20
# Should see SQL statements like CREATE DATABASE, INSERT INTO
```

3. Check database names in manifest:
```bash
cat backup/manifest.json
# Verify database names match your .env
```

4. Try importing individual databases:
```bash
# Extract and import manually
zcat backup/acore_world.sql.gz | docker exec -i ac-mysql mysql -uroot -pPASSWORD acore_world
```

### Missing Characters After Restore

**Symptom:** Characters don't appear in-game

**Common Causes:**

1. **Wrong database restored** - Check you restored characters DB
2. **GUID mismatch** - Items reference wrong GUIDs
3. **Incomplete restore** - Check for SQL errors during restore

**Fix with backup-merge:**

```bash
# Use merge instead of import to remap GUIDs
./scripts/bash/backup-merge.sh \
  --backup-dir ./path/to/backup \
  --password PASSWORD \
  --all-characters
```

### Duplicate SQL Execution

**Symptom:** "Duplicate key" errors in logs

**Cause:** SQL update ran twice

**Prevention:** The `updates` table prevents this, but if table is missing:

```sql
-- Recreate updates table
CREATE TABLE IF NOT EXISTS `updates` (
  `name` varchar(200) NOT NULL,
  `hash` char(40) DEFAULT '',
  `state` enum('RELEASED','CUSTOM','MODULE','ARCHIVED','PENDING') NOT NULL DEFAULT 'RELEASED',
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `speed` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Performance Issues

**Symptom:** Database queries are slow

**Solutions:**

1. Check database size:
```bash
./scripts/bash/db-health-check.sh
```

2. Optimize tables:
```sql
USE acore_world;
OPTIMIZE TABLE creature;
OPTIMIZE TABLE gameobject;

USE acore_characters;
OPTIMIZE TABLE characters;
OPTIMIZE TABLE item_instance;
```

3. Check MySQL configuration:
```bash
docker exec ac-mysql mysql -uroot -pPASSWORD -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'"
```

4. Increase buffer pool (edit docker-compose.yml):
```yaml
environment:
  MYSQL_INNODB_BUFFER_POOL_SIZE: 512M  # Increase from 256M
```

---

## Best Practices

### Backup Strategy

✅ **DO:**
- Keep at least 3 days of daily backups
- Test restore procedures regularly
- Store backups in multiple locations
- Monitor backup size trends
- Verify backup completion

❌ **DON'T:**
- Rely solely on automated backups
- Store backups only on same disk as database
- Skip verification of backup integrity
- Ignore backup size growth warnings

### Update Management

✅ **DO:**
- Let AzerothCore's auto-updater handle SQL
- Review `DBErrors.log` after updates
- Keep `Updates.EnableDatabases` enabled
- Test module updates in development first

❌ **DON'T:**
- Manually modify core database tables
- Skip module SQL when installing modules
- Disable auto-updates in production
- Run untested SQL in production

### Module Installation

✅ **DO:**
- Enable modules via `.env` file
- Verify module SQL applied via health check
- Check module compatibility before enabling
- Test modules individually first

❌ **DON'T:**
- Copy SQL files manually
- Edit module source SQL
- Enable incompatible module combinations
- Skip SQL verification after module install

### Performance

✅ **DO:**
- Run `OPTIMIZE TABLE` on large tables monthly
- Monitor database size growth
- Set appropriate MySQL buffer pool size
- Use SSD storage for MySQL data

❌ **DON'T:**
- Store MySQL data on slow HDDs
- Run database on same disk as backup
- Ignore slow query logs
- Leave unused data unarchived

---

## Quick Reference

### Essential Commands

```bash
# Check database health
./scripts/bash/db-health-check.sh

# Check backup status
./scripts/bash/backup-status.sh

# Create manual backup
./scripts/bash/manual-backup.sh --label my-backup

# Restore from backup
./scripts/bash/backup-import.sh --backup-dir ./path/to/backup --password PASS --all

# Export portable backup
./scripts/bash/backup-export.sh --password PASS --all -o ./export

# Connect to MySQL
docker exec -it ac-mysql mysql -uroot -p

# View worldserver logs
docker logs ac-worldserver -f

# Restart services
docker-compose restart ac-worldserver ac-authserver
```

### Important File Locations

```
storage/
├── mysql/                    # MySQL data directory
├── backups/
│   ├── hourly/              # Automated hourly backups
│   └── daily/               # Automated daily backups
├── config/                  # Server configuration files
└── logs/                    # Server log files

manual-backups/              # Manual backup storage
local-storage/
└── modules/                 # Installed module files
```

### Support Resources

- **Health Check:** `./scripts/bash/db-health-check.sh --help`
- **Backup Status:** `./scripts/bash/backup-status.sh --help`
- **AzerothCore Wiki:** https://www.azerothcore.org/wiki
- **AzerothCore Discord:** https://discord.gg/gkt4y2x
- **Issue Tracker:** https://github.com/uprightbass360/AzerothCore-RealmMaster/issues

---

**End of Database Management Guide**

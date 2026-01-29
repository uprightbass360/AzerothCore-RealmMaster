# AzerothCore RealmMaster - Troubleshooting Guide

This guide covers common issues, diagnostic steps, and solutions for AzerothCore RealmMaster deployments. Use this reference when encountering problems with your server setup, modules, or ongoing operations.

## Table of Contents

- [Common Issues](#common-issues)
- [Getting Help](#getting-help)
- [Backup and Restoration System](#backup-and-restoration-system)

---

## Common Issues

**Containers failing to start**
```bash
# Check container logs
docker logs <container_name>

# Verify network connectivity
docker network ls | grep azerothcore

# Check port conflicts
ss -tulpn | grep -E "(3784|8215|8081|4201)"
```

**Module not working**
```bash
# Check if module is enabled in environment
grep MODULE_NAME .env

# Verify module installation
ls storage/modules/

# Check module-specific configuration
ls storage/config/mod_*.conf*
```

**Database connection issues**
```bash
# Check if source repository is set up (common issue after remote deployment)
ls -la local-storage/source/azerothcore*/data/sql/base/db_world/

# If empty or missing, set up source:
./scripts/bash/setup-source.sh

# Then restart database import:
docker compose run --rm ac-db-import

# Error: "SQL source directory not found"
# This means the AzerothCore source repository hasn't been cloned.
# Solution: Run ./scripts/bash/setup-source.sh
# See docs/GETTING_STARTED.md for details

# Legacy database issues:
# Verify MySQL is running and responsive
docker exec ac-mysql mysql -u root -p -e "SELECT 1;"

# Starting with the 2025-11-17 release the import job checks if
# the runtime tables exist before trusting restoration markers. If you see
# "Restoration marker found, but databases are empty - forcing re-import" in
# `docker logs ac-db-import`, just let the container finish; it will automatically
# clear stale markers and replay the latest backup so the services never boot
# against an empty tmpfs volume. See docs/DATABASE_MANAGEMENT.md#restore-safety-checks--sentinels
# for full details.

# Forcing a fresh import (if schema missing/invalid)
# 1. Stop the stack
docker compose down
# 2. Remove the sentinel created after a successful restore (inside the docker volume)
docker run --rm -v mysql-data:/var/lib/mysql-persistent alpine sh -c 'rm -f /var/lib/mysql-persistent/.restore-completed'
# 3. Re-run the import pipeline (either stand-alone or via stage-modules)
docker compose run --rm ac-db-import
#    or
./scripts/bash/stage-modules.sh --yes
#
# See docs/ADVANCED.md#database-hardening for details on the sentinel workflow and why it's required.

**Permission denied writing to local-storage or storage**
```bash
# Reset ownership/permissions on the shared directories
./scripts/bash/repair-storage-permissions.sh
```
> This script reuses the same helper container as the staging workflow to `chown`
> `storage/`, `local-storage/`, and module metadata paths back to the current
> host UID/GID so tools like `scripts/python/modules.py` can regenerate
> `modules.env` without manual intervention.

# Check database initialization
docker logs ac-db-init
docker logs ac-db-import
```
> Need more context on why the sentinel exists or how the restore-aware SQL stage cooperates with backups? See [docs/ADVANCED.md#database-hardening](ADVANCED.md#database-hardening) for the full architecture notes.

**Worldserver restart loop (duplicate module SQL)**
> After a backup restore the ledger snapshot is synced and `.restore-prestaged` is set so the next `./scripts/bash/stage-modules.sh` run recopies EVERY module SQL file into `/azerothcore/data/sql/updates/*` with deterministic names. Check `docker logs ac-worldserver` to confirm it sees those files; the `updates` table still prevents reapplication, but the files remain on disk so the server never complains about missing history.
```bash
# 1. Inspect the worldserver log for errors like
#    "Duplicate entry ... MODULE_<module_name>_<file>"
docker logs ac-worldserver

# 2. Remove the staged SQL file that keeps replaying:
docker exec ac-worldserver rm /azerothcore/data/sql/updates/<db>/<filename>.sql

# 3. Re-run the staging workflow
./scripts/bash/stage-modules.sh --yes

# 4. Restart the worldserver container
docker compose restart ac-worldserver-playerbots  # or the profile you use

# See docs/DATABASE_MANAGEMENT.md#module-sql-management for details on the workflow.
```

**Legacy backup missing module SQL snapshot**

Legacy backups behave the same as new ones now—just rerun `./scripts/bash/stage-modules.sh --yes` after a restore and the updater will apply whatever the database still needs.

**Source rebuild issues**
```bash
# Check rebuild logs
docker logs ac-modules | grep -A20 -B5 "rebuild"

# Verify source path exists
ls -la "${STORAGE_PATH_LOCAL:-./local-storage}/source/azerothcore/"

# Force source setup
./scripts/bash/setup-source.sh
```

## Getting Help

1. **Check service status**: `./status.sh --watch`
2. **Review logs**: `docker logs <service-name> -f`
3. **Verify configuration**: Check `.env` file for proper module toggles
4. **Clean deployment**: Stop all services and redeploy with `./deploy.sh`

## Backup and Restoration System

The stack includes an intelligent backup and restoration system:

**Automated Backup Schedule**
- **Hourly backups**: Retained for 6 hours (configurable via `BACKUP_RETENTION_HOURS`)
- **Daily backups**: Retained for 3 days (configurable via `BACKUP_RETENTION_DAYS`)
- **Automatic cleanup**: Old backups removed based on retention policies

**Smart Backup Detection**
- **Multiple format support**: Detects daily, hourly, and legacy timestamped backups
- **Priority-based selection**: Automatically selects the most recent available backup
- **Integrity validation**: Verifies backup files before attempting restoration

**Intelligent Startup Process**
- **Automatic restoration**: Detects and restores from existing backups on startup
- **Conditional import**: Skips database import when backup restoration succeeds
- **Data protection**: Prevents overwriting restored data with fresh schema

**Backup Structure**
```
storage/backups/
├── daily/
│   └── YYYYMMDD_HHMMSS/          # Daily backup directories
│       ├── acore_auth.sql.gz
│       ├── acore_characters.sql.gz
│       ├── acore_world.sql.gz
│       └── manifest.json
└── hourly/
    └── YYYYMMDD_HHMMSS/          # Hourly backup directories
        ├── acore_auth.sql.gz
        ├── acore_characters.sql.gz
        └── acore_world.sql.gz

# User data import/export
ExportBackup_YYYYMMDD_HHMMSS/     # Created by scripts/bash/backup-export.sh
├── acore_auth.sql.gz             # User accounts
├── acore_characters.sql.gz       # Character data
└── manifest.json

ExportBackup_YYYYMMDD_HHMMSS/     # Optional manual drop-in under storage/backups/
├── acore_auth.sql.gz
├── acore_characters.sql.gz
└── manifest.json

Place extracted dumps from any `ExportBackup_*` archive inside `storage/backups/` (for automatic detection) or pass the directory directly to `scripts/bash/backup-import.sh --backup-dir <path>` when performing a manual restore.
```

---

## Additional Resources

- **Main Documentation**: See [README.md](../README.md) for complete setup instructions
- **Getting Started**: See [GETTING_STARTED.md](./GETTING_STARTED.md) for deployment walkthrough
- **Module Reference**: See [MODULES.md](./MODULES.md) for complete module catalog
- **Script Reference**: See [SCRIPTS.md](./SCRIPTS.md) for detailed script documentation
- **Advanced Configuration**: See [ADVANCED.md](./ADVANCED.md) for technical details

For additional support:
1. Check the [AzerothCore Wiki](https://www.azerothcore.org/wiki/home)
2. Visit the [AzerothCore Discord](https://discord.gg/gkt4y2x)
3. Review [GitHub Issues](https://github.com/azerothcore/azerothcore-wotlk/issues) for known problems

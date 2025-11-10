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
# Verify MySQL is running and responsive
docker exec ac-mysql mysql -u root -p -e "SELECT 1;"

# Check database initialization
docker logs ac-db-init
docker logs ac-db-import
```

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

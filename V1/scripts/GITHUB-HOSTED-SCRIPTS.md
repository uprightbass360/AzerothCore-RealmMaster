# GitHub-Hosted Service Scripts Documentation

This document describes the GitHub-hosted scripts that are automatically downloaded and executed by Docker containers during AzerothCore deployment.

## Overview

The AzerothCore Docker deployment uses a hybrid script management approach:
- **Local Scripts**: Run from your environment for setup and management
- **GitHub-Hosted Scripts**: Downloaded at runtime by containers for service operations

This pattern ensures Portainer compatibility while maintaining flexibility and maintainability.

## GitHub-Hosted Scripts

### 🗂️ `download-client-data.sh`
**Purpose**: Downloads and extracts WoW 3.3.5a client data files (~15GB)

**Features**:
- Intelligent caching system to avoid re-downloads
- Progress monitoring during extraction
- Integrity verification of downloaded files
- Fallback URLs for reliability
- Automatic directory structure validation

**Container Usage**: `ac-client-data` service
**Volumes Required**:
- `/cache` - For caching downloaded files
- `/azerothcore/data` - For extracted game data

**Environment Variables**:
```bash
# Automatically set by container, no manual configuration needed
```

**Process Flow**:
1. Fetches latest release info from wowgaming/client-data
2. Checks cache for existing files
3. Downloads if not cached or corrupted
4. Extracts with progress monitoring
5. Validates directory structure (maps, vmaps, mmaps, dbc)

---

### 🔧 `manage-modules.sh`
**Purpose**: Comprehensive AzerothCore module management and configuration

**Features**:
- Dynamic module installation based on environment variables
- Automatic removal of disabled modules
- Configuration file management (.conf.dist → .conf)
- SQL script execution for module databases
- Module state tracking for rebuild detection
- Integration with external SQL script library

**Container Usage**: `ac-modules` service
**Volumes Required**:
- `/modules` - Module installation directory
- `/azerothcore/env/dist/etc` - Configuration files

**Environment Variables**:
```bash
# Git Configuration
GIT_EMAIL=your-email@example.com
GIT_PAT=your-github-token
GIT_USERNAME=your-username

# Module Toggle Variables (1=enabled, 0=disabled)
MODULE_PLAYERBOTS=1
MODULE_AOE_LOOT=1
MODULE_LEARN_SPELLS=1
MODULE_FIREWORKS=1
MODULE_INDIVIDUAL_PROGRESSION=1
MODULE_AHBOT=1
MODULE_AUTOBALANCE=1
MODULE_TRANSMOG=1
MODULE_NPC_BUFFER=1
MODULE_DYNAMIC_XP=1
MODULE_SOLO_LFG=1
MODULE_1V1_ARENA=1
MODULE_PHASED_DUELS=1
MODULE_BREAKING_NEWS=1
MODULE_BOSS_ANNOUNCER=1
MODULE_ACCOUNT_ACHIEVEMENTS=1
MODULE_AUTO_REVIVE=1
MODULE_GAIN_HONOR_GUARD=1
MODULE_ELUNA=1
MODULE_TIME_IS_TIME=1
MODULE_POCKET_PORTAL=1
MODULE_RANDOM_ENCHANTS=1
MODULE_SOLOCRAFT=1
MODULE_PVP_TITLES=1
MODULE_NPC_BEASTMASTER=1
MODULE_NPC_ENCHANTER=1
MODULE_INSTANCE_RESET=1
MODULE_LEVEL_GRANT=1
MODULE_ARAC=1
MODULE_ASSISTANT=1
MODULE_REAGENT_BANK=1
MODULE_BLACK_MARKET_AUCTION_HOUSE=1

# Database Configuration
CONTAINER_MYSQL=ac-mysql
MYSQL_ROOT_PASSWORD=your-password
DB_AUTH_NAME=acore_auth
DB_WORLD_NAME=acore_world
DB_CHARACTERS_NAME=acore_characters
```

**Process Flow**:
1. Sets up Git configuration for module downloads
2. Removes disabled modules from `/modules` directory
3. Clones enabled modules from GitHub repositories
4. Installs module configuration files
5. Executes module SQL scripts via `manage-modules-sql.sh`
6. Tracks module state changes for rebuild detection
7. Downloads rebuild script for user convenience

---

### 🗄️ `manage-modules-sql.sh`
**Purpose**: SQL script execution functions for module database setup

**Features**:
- Systematic SQL file discovery and execution
- Support for multiple database targets (auth, world, characters)
- Error handling and logging
- MariaDB client installation if needed

**Container Usage**: Sourced by `manage-modules.sh`
**Dependencies**: Requires MariaDB/MySQL client tools

**Function**: `execute_module_sql_scripts()`
- Executes SQL for all enabled modules
- Searches common SQL directories (`data/sql/`, `sql/`)
- Handles auth, world, and character database scripts

---

### 🚀 `mysql-startup.sh`
**Purpose**: MySQL initialization with backup restoration support

**Features**:
- NFS-compatible permission handling
- Automatic backup detection and restoration
- Support for multiple backup formats (daily, hourly, legacy)
- Configurable MySQL parameters
- Background restore operations

**Container Usage**: `ac-mysql` service
**Volumes Required**:
- `/var/lib/mysql-runtime` - Runtime MySQL data (tmpfs)
- `/backups` - Backup storage directory

**Environment Variables**:
```bash
MYSQL_CHARACTER_SET=utf8mb4
MYSQL_COLLATION=utf8mb4_unicode_ci
MYSQL_MAX_CONNECTIONS=500
MYSQL_INNODB_BUFFER_POOL_SIZE=1G
MYSQL_INNODB_LOG_FILE_SIZE=256M
MYSQL_ROOT_PASSWORD=your-password
```

**Process Flow**:
1. Creates and configures runtime MySQL directory
2. Scans for available backups (daily → hourly → legacy)
3. Starts MySQL in background if restore needed
4. Downloads and executes restore script from GitHub
5. Runs MySQL normally if no restore required

---

### ⏰ `backup-scheduler.sh`
**Purpose**: Enhanced backup scheduler with hourly and daily schedules

**Features**:
- Configurable backup timing
- Separate hourly and daily backup retention
- Automatic backup script downloading
- Collision avoidance between backup types
- Initial backup execution

**Container Usage**: `ac-backup` service
**Volumes Required**:
- `/backups` - Backup storage directory

**Environment Variables**:
```bash
BACKUP_DAILY_TIME=03          # Hour for daily backups (UTC)
BACKUP_RETENTION_DAYS=7       # Daily backup retention
BACKUP_RETENTION_HOURS=48     # Hourly backup retention
MYSQL_HOST=ac-mysql
MYSQL_ROOT_PASSWORD=your-password
```

**Process Flow**:
1. Downloads backup scripts from GitHub
2. Waits for MySQL to be available
3. Executes initial daily backup
4. Runs continuous scheduler loop
5. Executes hourly/daily backups based on time

---

### 🏗️ `db-init.sh`
**Purpose**: Database creation and initialization

**Features**:
- MySQL readiness validation
- Legacy backup restoration support
- AzerothCore database creation
- Character set and collation configuration

**Container Usage**: `ac-db-init` service

**Environment Variables**:
```bash
MYSQL_HOST=ac-mysql
MYSQL_USER=root
MYSQL_ROOT_PASSWORD=your-password
DB_AUTH_NAME=acore_auth
DB_WORLD_NAME=acore_world
DB_CHARACTERS_NAME=acore_characters
MYSQL_CHARACTER_SET=utf8mb4
MYSQL_COLLATION=utf8mb4_unicode_ci
DB_WAIT_RETRIES=60
DB_WAIT_SLEEP=5
```

---

### 📥 `db-import.sh`
**Purpose**: Database schema import operations

**Features**:
- Database availability verification
- Dynamic configuration file generation
- AzerothCore dbimport execution
- Extended timeout handling

**Container Usage**: `ac-db-import` service

**Environment Variables**:
```bash
CONTAINER_MYSQL=ac-mysql
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_ROOT_PASSWORD=your-password
DB_AUTH_NAME=acore_auth
DB_WORLD_NAME=acore_world
DB_CHARACTERS_NAME=acore_characters
```

## Script Deployment Pattern

### Download Pattern
All GitHub-hosted scripts use this consistent pattern:
```bash
# Install curl if needed
apk add --no-cache curl  # Alpine
# OR
apt-get update && apt-get install -y curl  # Debian/Ubuntu

# Download script
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/SCRIPT_NAME.sh -o /tmp/SCRIPT_NAME.sh

# Make executable and run
chmod +x /tmp/SCRIPT_NAME.sh
/tmp/SCRIPT_NAME.sh
```

### Error Handling
- All scripts use `set -e` for immediate exit on errors
- Network failures trigger retries or fallback mechanisms
- Missing dependencies are automatically installed
- Detailed logging with emoji indicators for easy monitoring

### Security Considerations
- Scripts are downloaded from the official repository
- HTTPS is used for all downloads
- File integrity is verified where applicable
- Minimal privilege escalation (only when necessary)

## Troubleshooting

### Common Issues

**Script Download Failures**:
```bash
# Check network connectivity
ping raw.githubusercontent.com

# Manual download test
curl -v https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/download-client-data.sh
```

**Module Installation Issues**:
```bash
# Check module environment variables
docker exec ac-modules env | grep MODULE_

# Verify Git authentication
docker exec ac-modules git config --list
```

**Database Connection Issues**:
```bash
# Test MySQL connectivity
docker exec ac-db-init mysql -h ac-mysql -u root -p[password] -e "SELECT 1;"

# Check database container status
docker logs ac-mysql
```

### Manual Script Testing

You can download and test any GitHub-hosted script manually:

```bash
# Create test environment
mkdir -p /tmp/script-test
cd /tmp/script-test

# Download script
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/SCRIPT_NAME.sh -o test-script.sh

# Review script content
cat test-script.sh

# Set required environment variables
export MYSQL_ROOT_PASSWORD=testpass
# ... other variables as needed

# Execute (with caution - some scripts modify filesystem)
chmod +x test-script.sh
./test-script.sh
```

## Benefits of GitHub-Hosted Pattern

### ✅ Portainer Compatibility
- Only requires `docker-compose.yml` and `.env` files
- No additional file dependencies
- Works with any Docker Compose deployment method

### ✅ Maintainability
- Scripts can be updated without rebuilding containers
- Version control for all service logic
- Easy rollback to previous versions

### ✅ Consistency
- Same scripts across all environments
- Centralized script management
- Reduced configuration drift

### ✅ Reliability
- Fallback mechanisms for network failures
- Automatic dependency installation
- Comprehensive error handling

This pattern makes the AzerothCore deployment both powerful and portable, suitable for everything from local development to production Portainer deployments.
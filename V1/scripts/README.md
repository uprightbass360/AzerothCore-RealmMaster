# Scripts Directory

This directory contains deployment, configuration, and management scripts for the AzerothCore Docker deployment.

## Core Scripts

### 🚀 Setup & Deployment
- **`setup-server.sh`** - Interactive server setup wizard (recommended for new users)
- **`deploy-and-check.sh`** - Automated deployment and comprehensive health check script
- **`auto-post-install.sh`** - Automated post-installation configuration

### 🔧 Configuration & Management
- **`configure-modules.sh`** - Module configuration analysis and guidance tool
- **`setup-eluna.sh`** - Lua scripting environment setup
- **`update-realmlist.sh`** - Update server address in realmlist configuration
- **`update-config.sh`** - Configuration file updates and management

### 💾 Backup & Restore
- **`backup.sh`** - Manual database backup
- **`backup-hourly.sh`** - Hourly automated backup script
- **`backup-daily.sh`** - Daily automated backup script
- **`backup-scheduler.sh`** - Enhanced backup scheduler with hourly and daily schedules
- **`restore.sh`** - Database restoration from backup

### 🧹 Maintenance
- **`cleanup.sh`** - Resource cleanup script with multiple cleanup levels
- **`rebuild-with-modules.sh`** - Rebuild containers with module compilation
- **`test-local-worldserver.sh`** - Local worldserver testing

### 🔧 Service Management (GitHub-hosted)
- **`download-client-data.sh`** - Downloads and extracts WoW client data files
- **`manage-modules.sh`** - Comprehensive module management and configuration
- **`manage-modules-sql.sh`** - SQL execution functions for module database setup
- **`mysql-startup.sh`** - MySQL initialization with backup restoration support
- **`db-init.sh`** - Database creation and initialization
- **`db-import.sh`** - Database schema import operations

### 📚 Documentation
- **`DEPLOYMENT.md`** - Complete documentation for deployment scripts
- **`CLEANUP.md`** - Complete documentation for cleanup scripts
- **`GITHUB-HOSTED-SCRIPTS.md`** - Comprehensive documentation for service scripts

## Quick Usage

### 🆕 First-Time Setup (Recommended)
```bash
# Interactive setup wizard
./scripts/setup-server.sh
```

### 🔧 Module Configuration Analysis
```bash
# Check module configuration requirements
./scripts/configure-modules.sh
```

### 🎮 Lua Scripting Setup
```bash
# Setup Eluna scripting environment
./scripts/setup-eluna.sh
```

### 🩺 Health Checks & Deployment

**Run Health Check on Current Deployment**
```bash
cd scripts
./deploy-and-check.sh --skip-deploy
```

**Full Deployment with Health Checks**
```bash
cd scripts
./deploy-and-check.sh
```

**Quick Health Check (Basic Tests Only)**
```bash
cd scripts
./deploy-and-check.sh --skip-deploy --quick-check
```

### 🧹 Cleanup Resources
```bash
cd scripts

# Stop containers only (safe)
./cleanup.sh --soft

# Remove containers + networks (preserves data)
./cleanup.sh --hard

# Complete removal (DESTROYS ALL DATA)
./cleanup.sh --nuclear

# Dry run to see what would happen
./cleanup.sh --hard --dry-run
```

### 💾 Backup & Restore Operations
```bash
# Manual backup
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backup_filename.sql

# Setup automated backups (already configured in containers)
# Hourly: ./scripts/backup-hourly.sh
# Daily: ./scripts/backup-daily.sh
```

### ☁️ GitHub-Hosted Script Usage

The GitHub-hosted scripts are automatically executed by Docker containers, but you can also run them manually for testing:

```bash
# Download and test client data script
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/download-client-data.sh -o /tmp/download-client-data.sh
chmod +x /tmp/download-client-data.sh
# Note: Requires proper environment variables and volume mounts

# Download and test module management script
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/manage-modules.sh -o /tmp/manage-modules.sh
chmod +x /tmp/manage-modules.sh
# Note: Requires module environment variables

# Download backup scheduler
curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/backup-scheduler.sh -o /tmp/backup-scheduler.sh
chmod +x /tmp/backup-scheduler.sh
# Note: Requires backup environment variables
```

**Script Dependencies:**
- **Client Data Script**: Requires `/cache` and `/azerothcore/data` volumes
- **Module Scripts**: Require module environment variables and `/modules` volume
- **Database Scripts**: Require MySQL environment variables and connectivity
- **Backup Scripts**: Require `/backups` volume and MySQL connectivity

## GitHub-Hosted Service Scripts

The AzerothCore deployment uses a hybrid approach for script management:

### 🏠 Local Scripts
Traditional scripts that you run directly from your local environment for setup, configuration, and management tasks.

### ☁️ GitHub-Hosted Scripts
Service scripts that are automatically downloaded and executed by Docker containers at runtime. These scripts handle:
- **Client Data Management**: Automated download and caching of ~15GB WoW client data
- **Module Management**: Dynamic installation and configuration of AzerothCore modules
- **Database Operations**: MySQL initialization, backup restoration, and schema imports
- **Service Initialization**: Container startup logic with error handling and logging

**Benefits of GitHub-Hosted Scripts:**
- ✅ **Portainer Compatible**: Only requires docker-compose.yml and .env files
- ✅ **Always Current**: Scripts are pulled from the latest repository version
- ✅ **Maintainable**: Updates don't require container rebuilds
- ✅ **Consistent**: Same logic across all deployment environments

## Features

### 🚀 Setup & Deployment Features
✅ **Interactive Setup Wizard**: Guided configuration for new users
✅ **Automated Server Deployment**: Complete three-layer deployment system
✅ **Module Management**: Automated installation and configuration of 13 enhanced modules
✅ **Post-Install Automation**: Automatic database setup, realmlist configuration, and service restart

### 🔧 Configuration Features
✅ **Module Analysis**: Identifies missing configurations and requirements
✅ **Lua Scripting Setup**: Automated Eluna environment with example scripts
✅ **Realmlist Management**: Dynamic server address configuration
✅ **Config File Management**: Automated .conf file generation from .conf.dist templates

### 🩺 Health & Monitoring Features
✅ **Container Health Validation**: Checks all core containers
✅ **Port Connectivity Tests**: Validates all external ports
✅ **Web Service Verification**: HTTP response and content validation
✅ **Database Validation**: Schema and realm configuration checks
✅ **Comprehensive Reporting**: Color-coded status with detailed results

### 💾 Backup & Maintenance Features
✅ **Automated Backups**: Scheduled hourly and daily database backups
✅ **Manual Backup/Restore**: On-demand backup and restoration tools
✅ **Multi-Level Cleanup**: Safe, hard, and nuclear cleanup options
✅ **Container Rebuilding**: Module compilation and container rebuilding support

## Script Usage Examples

### First-Time Server Setup
```bash
# Complete guided setup (recommended)
./scripts/setup-server.sh

# Follow the interactive prompts to configure:
# - Server network settings
# - Storage locations
# - Database passwords
# - Module selections
```

### Post-Installation Configuration
```bash
# Analyze and configure modules
./scripts/configure-modules.sh

# Setup Lua scripting environment
./scripts/setup-eluna.sh

# Update server address after IP changes
./scripts/update-realmlist.sh new.server.address
```

### Maintenance Operations
```bash
# Health check existing deployment
./scripts/deploy-and-check.sh --skip-deploy

# Clean restart (preserves data)
./scripts/cleanup.sh --hard
./scripts/deploy-and-check.sh

# Backup before major changes
./scripts/backup.sh
```

## Configuration Variables

The scripts work with the updated environment variable names:
- `MYSQL_EXTERNAL_PORT` (database port)
- `AUTH_EXTERNAL_PORT` (authentication server port)
- `WORLD_EXTERNAL_PORT` (world server port)
- `SOAP_EXTERNAL_PORT` (SOAP API port)
- `MYSQL_ROOT_PASSWORD` (database root password)
- `SERVER_ADDRESS` (external server address)
- `STORAGE_ROOT` (data storage location)

For complete documentation, see `DEPLOYMENT.md` and `CLEANUP.md`.
# AzerothCore RealmMaster - Script Reference

This document provides comprehensive documentation for all scripts included in the AzerothCore RealmMaster project. These scripts automate deployment, module management, backup operations, and system administration tasks.

## Overview

The AzerothCore RealmMaster includes a comprehensive set of scripts organized into several categories:

- **Core Deployment Scripts** - Essential scripts for setup, build, and deployment
- **Container Lifecycle Management** - Scripts for managing Docker containers and services
- **Database & Backup Management** - Tools for backup, restore, and data management
- **Module Management Scripts** - Automated module staging, configuration, and integration
- **Post-Deployment Automation** - Scripts that run after deployment for configuration
- **Advanced Deployment Tools** - Specialized tools for remote deployment and validation
- **Backup System Scripts** - Automated backup scheduling and management

## Script Reference

### Core Deployment Scripts

#### `setup.sh` - Interactive Environment Configuration
Interactive `.env` generator with module selection, server configuration, and deployment profiles.

```bash
./setup.sh                                    # Interactive configuration
./setup.sh --module-config RealmMaster        # Use predefined module profile (see config/module-profiles)
./setup.sh --playerbot-max-bots 3000          # Set playerbot limits
```

**Features:**
- Server address and port configuration
- Module selection with presets
- Storage path configuration (NFS/local)
- Playerbot configuration
- Backup retention settings
- User/group permission settings

#### `build.sh` - Custom Image Builder
Compiles AzerothCore with enabled C++ modules and creates deployment-ready Docker images.

```bash
./build.sh                                    # Interactive build
./build.sh --yes                              # Auto-confirm all prompts
./build.sh --force                            # Force rebuild regardless of state
./build.sh --source-path /custom/path         # Use custom source path
./build.sh --skip-source-setup                # Skip source repo setup
```

**What it does:**
- Clones/updates AzerothCore source repository
- Stages enabled modules into source tree
- Compiles server binaries with modules
- Builds and tags Docker images (`<project>:authserver-modules-latest`, etc.)
- Updates build state markers

#### `deploy.sh` - Deployment Orchestrator
Module-aware deployment with automatic profile selection and optional remote deployment.

```bash
./deploy.sh                                    # Interactive deployment
./deploy.sh --yes                              # Auto-confirm deployment
./deploy.sh --profile standard                 # Force standard AzerothCore
./deploy.sh --profile playerbots               # Force playerbots branch
./deploy.sh --profile modules                  # Force custom modules build
./deploy.sh --no-watch                         # Don't tail worldserver logs
./deploy.sh --keep-running                     # Deploy and exit immediately

# Remote deployment
./deploy.sh --remote-host server.com \
            --remote-user username \
            --remote-project-dir /path/to/project
```

**Automated workflow:**
1. Loads environment configuration
2. Detects required profile based on enabled modules
3. Triggers build if C++ modules or playerbots enabled
4. Launches Docker Compose with appropriate profiles
5. Optionally migrates stack to remote host

#### `cleanup.sh` - Project Cleanup Utility
Comprehensive cleanup with multiple destruction levels and safety checks.

```bash
./cleanup.sh                                  # Interactive cleanup
./cleanup.sh --soft                           # Stop containers only
./cleanup.sh --hard                           # Remove containers, networks, volumes
./cleanup.sh --nuclear                        # Full cleanup including images
./cleanup.sh --preserve-backups               # Retain backup data during cleanup
./cleanup.sh --dry-run                        # Preview cleanup actions
```

### Container Lifecycle Management

#### `scripts/bash/start-containers.sh` - Service Startup
Starts all configured containers using appropriate profiles.

#### `scripts/bash/stop-containers.sh` - Graceful Shutdown
Stops all containers with proper cleanup and data protection.

#### `status.sh` - Service Health Monitoring
```bash
./status.sh                                    # Single status check with summary
./status.sh --watch                           # Continuous monitoring mode
./status.sh --once                            # Script-friendly single check
```

### Database & Backup Management

#### `scripts/bash/backup-export.sh` - User Data Export
Exports user accounts and character data for migration or backup purposes.

```bash
./scripts/bash/backup-export.sh                            # Export to ExportBackup_<timestamp>/
./scripts/bash/backup-export.sh /path/to/backup/dir       # Export to specific directory
```

**Output Structure:**
```
ExportBackup_YYYYMMDD_HHMMSS/
├── acore_auth.sql.gz         # User accounts
├── acore_characters.sql.gz   # Character data
└── manifest.json             # Backup metadata
```

#### `scripts/bash/backup-import.sh` - User Data Import
Restores user accounts and characters from backup while preserving world data.

```bash
./scripts/bash/backup-import.sh --backup-dir storage/backups/ExportBackup_20241029_120000 --password azerothcore123

# Restore directly from an ExportBackup archive you just unpacked
./scripts/bash/backup-import.sh --backup-dir ExportBackup_20241029_120000 --password azerothcore123 --all
```

> The importer always requires `--backup-dir`. A common workflow is to extract an `ExportBackup_*` archive into `storage/backups/` (so automated jobs can see it) and pass that directory to the script, but you can point to any folder that contains the SQL dumps.

**Required Files:**
- `acore_auth.sql[.gz]` - User accounts (required)
- `acore_characters.sql[.gz]` - Character data (required)
- `acore_world.sql[.gz]` - World data (optional)

#### `scripts/bash/pdump-import.sh` - Character Import
Imports individual character dump files into the database.

```bash
# Import character from pdump file
./scripts/bash/pdump-import.sh --file character.pdump --account testuser --password azerothcore123

# Import with character rename
./scripts/bash/pdump-import.sh --file oldchar.pdump --account newuser --name "NewName" --password azerothcore123

# Validate pdump without importing (dry run)
./scripts/bash/pdump-import.sh --file character.pdump --account testuser --password azerothcore123 --dry-run
```

**Features:**
- Automatic GUID assignment or manual override with `--guid`
- Character renaming during import with `--name`
- Account validation and character name uniqueness checks
- Automatic database backup before import
- Safe server restart handling

#### `scripts/bash/import-pdumps.sh` - Batch Character Import
Processes multiple character dump files from the `import/pdumps/` directory.

```bash
# Import all pdumps with environment settings
./scripts/bash/import-pdumps.sh --password azerothcore123 --account defaultuser

# Non-interactive batch import
./scripts/bash/import-pdumps.sh --password azerothcore123 --non-interactive
```

**Directory Structure:**
```
import/pdumps/
├── character1.pdump      # Character dump files
├── character2.sql        # SQL dump files also supported
├── configs/              # Optional per-character configuration
│   ├── character1.conf   # account=user1, name=NewName
│   └── character2.conf   # account=user2, guid=5000
└── processed/            # Successfully imported files moved here
```

**Configuration Format (`.conf`):**
```ini
account=target_account_name_or_id
name=new_character_name      # Optional: rename character
guid=force_specific_guid     # Optional: force GUID
```

### Security Management Scripts

#### `scripts/bash/bulk-2fa-setup.sh` - Bulk 2FA Setup
Configures TOTP 2FA for multiple AzerothCore accounts using official SOAP API.

```bash
# Setup 2FA for all accounts without it
./scripts/bash/bulk-2fa-setup.sh --all

# Setup for specific accounts
./scripts/bash/bulk-2fa-setup.sh --account user1 --account user2

# Force regenerate with custom issuer
./scripts/bash/bulk-2fa-setup.sh --all --force --issuer "MyServer"

# Preview what would be done
./scripts/bash/bulk-2fa-setup.sh --all --dry-run

# Use custom SOAP credentials
./scripts/bash/bulk-2fa-setup.sh --all --soap-user admin --soap-pass adminpass

# Show help / options
./scripts/bash/bulk-2fa-setup.sh --help
```

**Features:**
- **Official AzerothCore API Integration**: Uses SOAP commands instead of direct database manipulation
- Generates AzerothCore-compatible 16-character Base32 TOTP secrets (longer secrets are rejected by SOAP)
- Automatic account discovery or specific targeting
- QR code generation for authenticator apps
- Force regeneration of existing 2FA secrets
- Comprehensive output with setup instructions
- Safe dry-run mode for testing
- SOAP connectivity validation
- Proper error handling and validation

**Requirements:**
- AzerothCore worldserver with SOAP enabled (SOAP.Enabled = 1)
- SOAP port exposed on 7778 (SOAP.Port = 7878, mapped to external 7778)
- Remote Access enabled (Ra.Enable = 1) in worldserver.conf
- SOAP.IP = "0.0.0.0" for external connectivity
- GM account with sufficient privileges (gmlevel 3)
- Provide SOAP credentials explicitly via `--soap-user` and `--soap-pass` (these are required; no env fallback)

**Output Structure:**
```
./2fa-setup-TIMESTAMP/
├── qr-codes/               # QR code images for each account
├── setup-report.txt        # Complete setup summary
├── console-commands.txt    # Manual verification commands
└── secrets-backup.csv      # Secure backup of all secrets
```

**Security Notes:**
- Generated QR codes and backup files contain sensitive TOTP secrets
- Distribute QR codes securely to users
- Delete or encrypt backup files after distribution
- TOTP secrets are also stored in AzerothCore database

#### `scripts/bash/generate-2fa-qr.sh` / `generate-2fa-qr.py` - Individual 2FA Setup
Generate QR codes for individual account 2FA setup.

> Tip: each script supports `-h/--help` to see all options.

```bash
# Generate QR code for single account
./scripts/bash/generate-2fa-qr.sh -u username

# Use custom issuer and output path
./scripts/bash/generate-2fa-qr.sh -u username -i "MyServer" -o /tmp/qr.png

# Use existing secret
./scripts/bash/generate-2fa-qr.sh -u username -s JBSWY3DPEHPK3PXP

# Show help / options
./scripts/bash/generate-2fa-qr.sh -h
```

> AzerothCore's SOAP endpoint only accepts 16-character Base32 secrets (A-Z and 2-7). The generators enforce this length to avoid "The provided two-factor authentication secret is not valid" errors.

#### `scripts/bash/test-2fa-token.py` - Generate TOTP Test Codes
Quickly verify a 16-character Base32 secret produces valid 6-digit codes.

```bash
# Show help
./scripts/bash/test-2fa-token.py --help

# Generate two consecutive codes for a secret
./scripts/bash/test-2fa-token.py -s JBSWY3DPEHPK3PXP -c 2
```

### Module Management Scripts

#### `scripts/bash/stage-modules.sh` - Module Staging
Downloads and stages enabled modules for source integration.

```bash
./scripts/bash/stage-modules.sh                    # Stage all enabled modules
```

Called automatically by `build.sh`. Downloads enabled modules from GitHub and prepares them for compilation.

#### `scripts/bash/setup-source.sh` - Source Repository Setup
Initializes or updates AzerothCore source repositories for compilation.

```bash
./scripts/bash/setup-source.sh                     # Setup source for current configuration
```

Automatically clones the appropriate AzerothCore fork (main or playerbot) based on configuration.

#### `scripts/bash/manage-modules.sh` - Module Management Container
Internal script that runs inside the `ac-modules` container to handle module lifecycle:
- Downloads module source code
- Executes module SQL scripts
- Manages module configuration files
- Tracks installation state

#### `config/module-manifest.json` & `scripts/python/modules.py`
Central module registry and management system:
- **`config/module-manifest.json`** - Declarative manifest defining all 30+ supported modules with metadata:
  - Repository URLs
  - Module type (cpp, data, lua)
  - Build requirements
  - SQL scripts and config files
  - Dependencies
- **`scripts/python/modules.py`** - Python helper that reads the manifest and `.env` to:
  - Generate `modules.env` with enabled module lists
  - Determine if rebuild is required
  - Provide module metadata to shell scripts

This centralized approach eliminates duplicate module definitions across scripts.

#### `scripts/python/update_module_manifest.py` - GitHub Topic Sync
Automates manifest population directly from the official AzerothCore GitHub topics.

```bash
# Preview new modules across all default topics
python3 scripts/python/update_module_manifest.py --dry-run --log

# Update config/module-manifest.json with latest repos (requires GITHUB_TOKEN)
GITHUB_TOKEN=ghp_yourtoken python3 scripts/python/update_module_manifest.py --refresh-existing
```

- Queries `azerothcore-module`, `azerothcore-lua`, `azerothcore-sql`, `azerothcore-tools`, and `azerothcore-module+ac-premium`
- Merges new repositories without touching existing customizations
- Optional `--refresh-existing` flag rehydrates names/descriptions from GitHub
- Designed for both local execution and the accompanying GitHub Action workflow

#### `scripts/bash/manage-modules-sql.sh` - Module Database Integration
Executes module-specific SQL scripts for database schema updates.

#### `scripts/bash/copy-module-configs.sh` - Configuration File Management
Creates module `.conf` files from `.dist.conf` templates for active modules.

```bash
./scripts/bash/copy-module-configs.sh              # Create missing module configs
```

### Post-Deployment Automation

#### `scripts/bash/auto-post-install.sh` - Post-Installation Configuration
Automated post-deployment tasks including module configuration, service verification, and initial setup.

```bash
./scripts/bash/auto-post-install.sh                # Run post-install tasks
```

**Automated Tasks:**
1. Module configuration file creation
2. Service health verification
3. Database connectivity testing
4. Initial realm configuration

#### `scripts/bash/manual-backup.sh` - On-Demand Backup Helper
Runs the `ac-backup` container's dump logic immediately and stores results under `/backups/<label>_<timestamp>`.

```bash
./scripts/bash/manual-backup.sh                     # Manual backup with default label
./scripts/bash/manual-backup.sh --label hotfix      # Custom label for the backup directory
```

### Advanced Deployment Tools

#### `scripts/bash/migrate-stack.sh` - Remote Deployment Migration
Exports and transfers locally built images to remote hosts via SSH.

```bash
./scripts/bash/migrate-stack.sh \
  --host docker-server \
  --user sam \
  --project-dir /home/sam/AzerothCore-RealmMaster

./scripts/bash/migrate-stack.sh \
  --host remote.example.com \
  --user deploy \
  --port 2222 \
  --identity ~/.ssh/deploy_key \
  --skip-storage
```

**What it does:**
1. Exports module images to `local-storage/images/acore-modules-images.tar`
2. Syncs project files (.env, docker-compose.yml, scripts) via rsync/scp
3. Syncs storage directory (unless `--skip-storage`)
4. Imports images on remote host

**Note:** Typically called via `./deploy.sh --remote-host` rather than directly.

#### `scripts/bash/deploy-tools.sh` - Management Tools Deployment
Deploys web-based management tools (phpMyAdmin, Keira3) independently.

```bash
./scripts/bash/deploy-tools.sh                     # Deploy management tools only
```

#### `scripts/bash/verify-deployment.sh` - Deployment Validation
Comprehensive deployment verification with health checks and service validation.

```bash
./scripts/bash/verify-deployment.sh                        # Full deployment verification
./scripts/bash/verify-deployment.sh --skip-deploy         # Verify existing deployment
./scripts/bash/verify-deployment.sh --quick               # Quick health check only
```

#### `scripts/bash/validate-env.sh` - Environment Configuration Validator
Validates `.env` configuration for required and optional variables with detailed reporting.

```bash
./scripts/bash/validate-env.sh                    # Basic validation (required vars only)
./scripts/bash/validate-env.sh --strict           # Validate required + optional vars
./scripts/bash/validate-env.sh --quiet            # Errors only, suppress success messages
```

**Exit Codes:**
- `0` - All required variables present (and optional if --strict)
- `1` - Missing required variables
- `2` - Missing optional variables (only in --strict mode)

**Validates:**
- **Project Configuration:** `COMPOSE_PROJECT_NAME`, `NETWORK_NAME`
- **Repository URLs:** Standard and playerbots AzerothCore repositories
- **Storage Paths:** `STORAGE_PATH`, `STORAGE_PATH_LOCAL`, `MODULES_REBUILD_SOURCE_PATH`
- **Database Settings:** MySQL credentials, ports, database names
- **Container Config:** Container names and user permissions
- **Build Paths:** Module rebuild source paths (optional)
- **Performance Tuning:** MySQL buffer pool, InnoDB settings (optional)
- **Image References:** Docker image tags (optional)

**Use Cases:**
- Pre-deployment validation
- Troubleshooting configuration issues
- CI/CD pipeline checks
- Documentation of environment requirements

**Example Output:**
```
ℹ️  Validating environment configuration...
✅ Loaded environment from /path/to/.env

ℹ️  Checking required variables...
✅ COMPOSE_PROJECT_NAME=azerothcore-realmmaster
✅ NETWORK_NAME=azerothcore
✅ STORAGE_PATH=./storage
✅ MYSQL_ROOT_PASSWORD=********
✅ All required variables are set

✅ Environment validation passed ✨
```

### Backup System Scripts

#### `scripts/bash/backup-scheduler.sh` - Automated Backup Service
Runs inside the backup container to provide scheduled database backups.

**Features:**
- Hourly backups (retained for 6 hours)
- Daily backups (retained for 3 days)
- Automatic cleanup based on retention policies
- Database detection (includes playerbots if present)

## Script Usage Patterns

### Common Workflows

#### Initial Setup and Deployment
```bash
# 1. Configure environment and select modules
./setup.sh

# 2. Build custom images (if using C++ modules or playerbots)
./build.sh --yes

# 3. Deploy services
./deploy.sh
```

#### Module Configuration Changes
```bash
# 1. Reconfigure modules
./setup.sh

# 2. Rebuild if you changed C++ modules
./build.sh --yes

# 3. Redeploy with new configuration
./deploy.sh
```

#### Remote Deployment
```bash
# 1. Configure and build locally
./setup.sh
./build.sh --yes

# 2. Deploy to remote host
./deploy.sh --remote-host server.com --remote-user username
```

#### Service Management
```bash
# Check service status
./status.sh

# Monitor continuously
./status.sh --watch

# Stop all services
./scripts/bash/stop-containers.sh

# Start services
./scripts/bash/start-containers.sh
```

#### Backup and Restore Operations
```bash
# Export user data for migration
./scripts/bash/backup-export.sh

# Import user data from backup
./scripts/bash/backup-import.sh /path/to/backup

# Verify deployment health
./scripts/bash/verify-deployment.sh --quick
```

#### Project Cleanup
```bash
# Soft cleanup (stop containers)
./cleanup.sh --soft

# Full cleanup with backup preservation
./cleanup.sh --nuclear --preserve-backups
```

## Script Dependencies and Requirements

### System Requirements
- Docker and Docker Compose
- Bash 4.0+ (most scripts)
- Python 3.6+ (module management)
- rsync and ssh (remote deployment)
- Standard Unix utilities (grep, awk, sed, etc.)

### Environment Variables
Most scripts rely on environment variables defined in `.env`. Key variables include:

- `PROJECT_NAME` - Docker image and container naming
- `STORAGE_PATH` - Primary storage location
- `STORAGE_PATH_LOCAL` - Local build storage
- Module toggles (`MODULE_*` variables)
- Docker Compose profile settings
- Backup retention configurations

### File Dependencies
- `.env` - Environment configuration (created by `setup.sh`)
- `docker-compose.yml` - Container orchestration
- `config/module-manifest.json` - Module definitions
- `config/module-profiles/*.json` - Module presets

## Troubleshooting Scripts

When scripts encounter issues, use these debugging approaches:

### General Debugging
```bash
# Run scripts with debug output
bash -x ./script-name.sh

# Check script exit codes
echo $? # after running a script
```

### Container-Related Issues
```bash
# Check Docker daemon
systemctl status docker

# Verify Docker Compose
docker compose version

# Check container logs
docker logs <container-name>
```

### Environment Issues
```bash
# Verify .env file
cat .env | grep -v '^#'

# Check module configuration
./scripts/python/modules.py --list-enabled
```

### Permission Issues
```bash
# Check file ownership
ls -la storage/

# Fix permissions (if needed)
sudo chown -R $USER:$USER storage/
```

---

For additional help and troubleshooting information, refer to the main README.md file or check the project repository issues.

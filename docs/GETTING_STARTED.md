# Getting Started with AzerothCore RealmMaster

This guide provides a complete walkthrough for deploying AzerothCore RealmMaster on your local machine or remote server.

***Note: All :port and credential information is based on default configuration and should be updated based on your settings.***
***If you have any suggestions about how to make this documentation better, please file an issue and I will look into it.***

## Prerequisites

Before you begin, ensure you have:
- **Docker** with Docker Compose
- **16GB+ RAM** and **64GB+ storage**
- **Linux/macOS/WSL2** (Windows with WSL2 recommended)

## Quick Overview

AzerothCore RealmMaster provides three deployment options:
1. **Local Deployment** - Deploy and run on your local machine
2. **Remote Deployment** - Build locally, deploy to a remote server
3. **Standard/Playerbots/Modules** - Choose your feature set

---

## Local Deployment

Complete setup and deployment on your local machine.

### Step 1: Initial Setup

**1.1 Clone the Repository**
```bash
git clone https://github.com/uprightbass360/AzerothCore-RealmMaster.git
cd AzerothCore-RealmMaster
```

**1.2 Run Interactive Setup**
```bash
./setup.sh
```

The setup wizard will guide you through:
- **Server Configuration**: IP address, ports, timezone
- **Module Selection**: Choose from hundreds of official modules (348 in manifest; 221 currently supported) or use presets
- **Module Definitions**: Customize defaults in `config/module-manifest.json` and optional presets under `config/module-profiles/`
- **Storage Paths**: Configure NFS/local storage locations
- **Playerbot Settings**: Max bots, account limits (if enabled)
- **Backup Settings**: Retention policies for automated backups
- **Permissions**: User/group IDs for file ownership

**Setup Output:** Creates `.env` file with your configuration

### Step 2: Build Images (if using C++ modules or playerbots)

```bash
./build.sh
```

**Skip this step if:**
- You're using only Lua/data modules
- You want vanilla AzerothCore without playerbots

**Required when:**
- Playerbots enabled (`MODULE_PLAYERBOTS=1`)
- Any C++ module enabled (modules with `"type": "cpp"` in `config/module-manifest.json`)

**Build process:**
1. Clones AzerothCore source to `local-storage/source/`
2. Downloads and stages enabled modules
3. Compiles server binaries with modules
4. Creates Docker images tagged as `<project-name>:authserver-modules-latest`, etc.
5. Takes 20-60 minutes depending on hardware

### Step 3: Deploy Services

```bash
./deploy.sh
```

**Deployment flow:**
1. Validates environment configuration
2. Auto-selects Docker Compose profile:
   - `services-standard` - Vanilla AzerothCore
   - `services-playerbots` - Playerbot build
   - `services-modules` - Custom C++ modules build
3. Starts services in dependency order:
   - Database layer (`ac-mysql`, `ac-db-init`, `ac-db-import`, `ac-backup`)
   - Module management (`ac-modules`, `ac-post-install`)
   - Client data (`ac-client-data`)
   - Game servers (`ac-authserver`, `ac-worldserver`)
4. Tails worldserver logs (Ctrl+C to detach safely)

**First deployment takes longer** due to:
- Database schema import (~5-10 minutes)
- Client data download (~15GB, ~10-30 minutes)
- Module SQL execution

**Subsequent deployments** restore from backups and skip imports.

### Step 4: Create Admin Account

```bash
# Attach to worldserver console
docker attach ac-worldserver

# Create admin account
account create admin yourpassword
account set gmlevel admin 3 -1

# Detach: Ctrl+P, Ctrl+Q (NOT Ctrl+C - that stops the server!)
```

### Step 5: Connect Game Client

Edit `realmlist.wtf` in your WoW 3.3.5a client folder:
```
set realmlist 127.0.0.1
```

For custom ports:
```
set realmlist 127.0.0.1 8215
```

### Step 6: Access Management Tools

- **phpMyAdmin**: http://localhost:8081 - Database administration
- **Keira3**: http://localhost:4201 - World database editor

**Credentials:**
- Username: `root`
- Password: From `MYSQL_ROOT_PASSWORD` in `.env`

---

## Remote Deployment

Deploy your configured realm to a remote server while building images locally.

### Remote Deployment Workflow

**Step 1: Configure & Build Locally**
```bash
# Interactive configuration with module selection
./setup.sh

# Build custom images (if using C++ modules or playerbots)
./build.sh --yes
```

### Step 2: Package & Transfer to Remote Host

You can deploy remotely in two ways:

**Option A: Interactive (Recommended)**
```bash
./deploy.sh
# When prompted, select "2) Remote host (package for SSH deployment)"
# Follow prompts for hostname, username, and paths
```

**Option B: Non-Interactive**
```bash
./deploy.sh --yes \
  --remote-host your-server.com \
  --remote-user youruser \
  --remote-project-dir /home/youruser/AzerothCore-RealmMaster
```

Optional flags:
- `--remote-port 2222` - Custom SSH port
- `--remote-identity ~/.ssh/custom_key` - Specific SSH key
- `--remote-skip-storage` - Don't sync storage directory (fresh install on remote)
- `--remote-clean-containers` - Stop/remove existing `ac-*` containers and project images during migration
- `--remote-skip-env` - Leave the remote `.env` untouched (won't upload local one)
- `--remote-preserve-containers` - Do not stop/remove existing `ac-*` containers/images during migration
- `--remote-storage-path /mnt/acore-storage` - Override STORAGE_PATH on the remote host (local-storage stays per .env)
- `--remote-container-user 1001:1001` - Override CONTAINER_USER on the remote host (uid:gid)
  - Note: do not combine `--remote-clean-containers` with `--remote-preserve-containers`; the flags are mutually exclusive.

### Step 3: Deploy on Remote Host
```bash
ssh your-server.com
cd /home/youruser/AzerothCore-RealmMaster
./deploy.sh --yes --no-watch
```

The remote deployment uses the images you built locally (no rebuild needed).

### Step 4: Verify Deployment
```bash
./status.sh
# Check service logs
docker logs ac-worldserver -f
```

### What Gets Transferred

The remote deployment process transfers:
- ✅ Docker images (exported to `local-storage/images/`)
- ✅ Project files (scripts, configs, docker-compose.yml, .env)
- ✅ Storage directory (unless `--remote-skip-storage` is used)
- ❌ AzerothCore source repository (must be set up separately - see below)

**IMPORTANT: AzerothCore Source Setup**

The AzerothCore source repository (~2GB) is NOT synced during migration to avoid slow transfers. However, it's **required** for database initialization.

**Option 1: Automatic Setup (Recommended)**

Use the `--remote-setup-source` flag to automatically clone the source on the remote host:

```bash
./deploy.sh --remote-host your-server --remote-user youruser --remote-setup-source
```

**Option 2: Manual Setup**

After migration completes, SSH to the remote host and run:

```bash
ssh your-server
cd ~/AzerothCore-RealmMaster  # or your custom project directory
./scripts/bash/setup-source.sh
```

**Without this step, database initialization will fail with:**
`❌ FATAL: SQL source directory not found`

### Module Presets

- Define JSON presets in `config/module-profiles/*.json`. Each file contains:
  - `modules` (array, required) – list of `MODULE_*` identifiers to enable.
  - `label` (string, optional) – text shown in the setup menu (emoji welcome).
  - `description` (string, optional) – short help text for maintainers.
  - `order` (number, optional) – determines the menu position (lower appears first).
  Example:

  ```json
  {
    "modules": ["MODULE_ELUNA", "MODULE_SOLO_LFG", "MODULE_SOLOCRAFT"],
    "label": "⭐ Suggested Modules",
    "description": "Baseline solo-friendly quality of life mix",
    "order": 1
  }
  ```
- `setup.sh` automatically adds these presets to the module menu and enables the listed modules when selected or when `--module-config <name>` is provided.
- Built-in presets:
  - `config/module-profiles/RealmMaster.json` – 33-module baseline used for testing.
  - `config/module-profiles/suggested-modules.json` – light AzerothCore QoL stack without playerbots.
  - `config/module-profiles/playerbots-suggested-modules.json` – suggested QoL stack plus playerbots.
  - `config/module-profiles/azerothcore-vanilla.json` – pure AzerothCore (no optional modules).
  - `config/module-profiles/playerbots-only.json` – playerbot prerequisites only (tune bot counts separately).
  - `config/module-profiles/all-modules.json` – enable everything currently marked supported/active (not recommended).
- Module metadata lives in `config/module-manifest.json`; update that file if you need to add new modules or change repositories/branches.

---

## Post-Installation Steps

### Create Admin Account

```bash
# Attach to worldserver console
docker attach ac-worldserver

# Create admin account
account create admin yourpassword
account set gmlevel admin 3 -1

# Detach: Ctrl+P, Ctrl+Q (NOT Ctrl+C - that stops the server!)
```

### Access Management Tools

- **phpMyAdmin**: http://localhost:8081 - Database administration
- **Keira3**: http://localhost:4201 - World database editor

**Credentials:**
- Username: `root`
- Password: From `MYSQL_ROOT_PASSWORD` in `.env`

### Configure Server for Public Access

```sql
-- Update realmlist for public server
UPDATE acore_auth.realmlist
SET address = 'your-public-ip', port = 8215
WHERE id = 1;
```

### Spawn Custom NPCs

The server includes 14 custom NPCs providing enhanced functionality. Use GM commands to spawn them at appropriate locations:

```bash
# Quick reference - spawn essential NPCs
.npc add 199999    # Kaylub - Free Professions
.npc add 601015    # Beauregard - Enchanter
.npc add 601016    # Buffmaster - Player Buffs
.npc add 601026    # White Fang - BeastMaster
.npc add 190010    # Warpweaver - Transmog

# See complete guide with coordinates and functions
```

**📖 For complete spawn commands, coordinates, and NPC functionality details, see [docs/NPCS.md](docs/NPCS.md)**

---

## Management & Operations

Essential commands and workflows for operating your AzerothCore server.

### Common Workflows

#### Changing Module Configuration

```bash
# 1. Reconfigure modules
./setup.sh

# 2. Rebuild if you changed C++ modules
./build.sh --yes

# 3. Redeploy with new configuration
./deploy.sh
```

#### Updating to Latest Code

```bash
# Pull latest changes
git pull origin main

# Rebuild images (if using modules/playerbots)
./build.sh --force

# Restart services
docker compose down
./deploy.sh
```

#### Managing Services

```bash
# Check service status
./status.sh

# View logs
docker logs ac-worldserver -f
docker logs ac-authserver -f
docker logs ac-mysql -f

# Restart specific service
docker compose restart ac-worldserver

# Stop all services
./scripts/bash/stop-containers.sh

# Start services
./scripts/bash/start-containers.sh
```

### Management Commands

#### Health Monitoring
```bash
# Check realm status
./status.sh

# Watch services continuously
./status.sh --watch

# View service logs
docker logs ac-worldserver -f
docker logs ac-authserver -f

# Check module management
docker logs ac-modules --tail 50
```

#### Web Tools Access

Once deployed, access the management tools in your browser:

```bash
# Database Management (phpMyAdmin)
http://YOUR_SERVER_IP:8081

# World Database Editor (Keira3)
http://YOUR_SERVER_IP:4201

# Replace YOUR_SERVER_IP with your actual server address
# Example: http://192.168.1.100:4201
```

**Note**: Initial Keira3 startup may show database connection errors until the world database import completes. This is expected behavior.

#### Module Management

```bash
# Reconfigure modules via interactive setup
./setup.sh

# Build custom images with enabled modules
./build.sh                          # Interactive build (prompts for confirmation)
./build.sh --yes                    # Auto-confirm build
./build.sh --force                  # Force rebuild regardless of state

# Deploy with automatic profile selection
./deploy.sh                         # Auto-detects and deploys correct profile
./deploy.sh --profile standard      # Force standard AzerothCore
./deploy.sh --profile playerbots    # Force playerbots branch
./deploy.sh --profile modules       # Force custom modules build

# Lower-level module operations
./scripts/bash/stage-modules.sh                    # Download enabled modules
./scripts/bash/setup-source.sh                     # Initialize AzerothCore source
./scripts/bash/copy-module-configs.sh              # Create module .conf files
./scripts/bash/manage-modules-sql.sh               # Execute module SQL scripts

# Management tools
./scripts/bash/deploy-tools.sh                     # Launch phpMyAdmin + Keira3
```

#### Container Management
```bash
# Start specific services
./scripts/bash/start-containers.sh                           # Start all configured containers

# Stop services gracefully
./scripts/bash/stop-containers.sh                            # Stop all containers

# Monitor service health
./status.sh                                     # Check realm status
./status.sh --watch                            # Watch services continuously
./status.sh --once                             # Single status check
```

#### Deployment Verification
```bash
# Quick health check
./scripts/bash/verify-deployment.sh --skip-deploy --quick

# Full deployment verification
./scripts/bash/verify-deployment.sh
```

#### Cleaning Up

```bash
# Soft cleanup (stop containers only)
./cleanup.sh --soft

# Hard cleanup (remove containers and networks)
./cleanup.sh --hard

# Nuclear cleanup (everything including images and data)
./cleanup.sh --nuclear --preserve-backups
```

### Database Operations

```bash
# Access database via phpMyAdmin
open http://localhost:8081

# Direct MySQL access
docker exec -it ac-mysql mysql -u root -p

# Manual backup operations
# Export user accounts & characters to a named directory
./scripts/bash/backup-export.sh storage/backups/ExportBackup_manual_$(date +%Y%m%d_%H%M%S)

# Import data from a directory that contains the SQL dumps
./scripts/bash/backup-import.sh --backup-dir storage/backups/ExportBackup_20241029_120000 --password azerothcore123

# View available backups
ls -la storage/backups/
```

---

## Next Steps

After completing the installation, consider these additional steps:

### In-Game Setup

1. **Create GM Account** and test module functionality
2. **Configure Realmlist** for public access if needed
3. **Test Modules** - Verify enabled modules are working properly

### Server Administration

1. **Set Up Monitoring** with `./status.sh --watch`
2. **Configure Backups** and test backup/restore procedures
3. **Customize Modules** by editing configs in `storage/config/mod_*.conf`
4. **Add Lua Scripts** in `storage/lua_scripts/` for custom functionality

### Performance Tuning

1. **Database Optimization** - Adjust MySQL settings in `.env`
2. **Playerbot Scaling** - Tune bot limits and monitor resources
3. **Network Configuration** - Open firewall ports and configure NAT

For detailed information about troubleshooting, architecture, and advanced configuration, see the complete documentation referenced in the main README.md file.

---

## Important Notes

- **First deployment takes 30-60 minutes** for database setup and client data download
- **Subsequent starts are much faster** due to intelligent backup restoration
- **Use Ctrl+P, Ctrl+Q to detach** from containers (NOT Ctrl+C which stops the server)
- **Module presets** help quickly configure common setups
- **Remote deployment** keeps builds local while deploying remotely

For troubleshooting and advanced configuration options, refer to the main project documentation.

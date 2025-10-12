# AzerothCore Docker/Podman Stack

A complete containerized deployment of AzerothCore WoW 3.3.5a (Wrath of the Lich King) private server with 13 enhanced modules, automated management, and production-ready features.

## 🚀 Quick Start

### Prerequisites
- **Docker** or **Podman** with Docker Compose
- **4GB+ RAM** and **20GB+ storage**
- **Linux/macOS/WSL2** (Windows with WSL2 recommended)

### ⚡ Automated Setup (Recommended)

**1. Get the Code**
```bash
git clone https://github.com/uprightbass360/acore-compose.git
cd acore-compose
```

**2. Run Interactive Setup**
```bash
./scripts/setup-server.sh
```

**3. Deploy Server**
```bash
# Use the generated custom environment files
docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml up -d
docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml up -d
docker compose --env-file docker-compose-azerothcore-tools-custom.env -f docker-compose-azerothcore-tools.yml up -d
```

**4. Create Admin Account**

Once the worldserver is running:

```bash
# Attach to worldserver console
docker attach ac-worldserver

# In the worldserver console, create admin account:
account create admin yourpassword
account set gmlevel admin 3 -1
server info

# Detach from console without stopping: Ctrl+P, Ctrl+Q
```

**5. Configure Game Client**

**Client Connection Instructions**:

1. **Locate your WoW 3.3.5a client directory**
2. **Edit `realmlist.wtf` file** (in your WoW client folder):
   ```
   set realmlist SERVER_ADDRESS
   ```

**Examples based on your server configuration**:
```bash
# Local development
set realmlist 127.0.0.1

# LAN server
set realmlist 192.168.1.100

# Public server with custom port
set realmlist your-domain.com 8215
# or for IP with custom port
set realmlist 203.0.113.100 8215
```

**6. Access Your Server**
- **Game Server**: `your-server-ip:8215` (or port you configured)
- **Database Admin**: http://localhost:8081 (phpMyAdmin)
- **Game Content Editor**: http://localhost:4201 (Keira3)

✅ **That's it!** Your server is ready with all 13 modules installed and configured.

---

## 🔧 Manual Setup (Advanced Users)

### Step 1: Clone Repository
```bash
git clone https://github.com/uprightbass360/acore-compose.git
cd acore-compose
```

### Step 2: Configure Environment Files
Edit these files to match your setup:
- `docker-compose-azerothcore-database.env`
- `docker-compose-azerothcore-services.env`
- `docker-compose-azerothcore-tools.env`

Key settings to modify:
```bash
# Server network configuration
SERVER_ADDRESS=your-server-ip
REALM_PORT=8215
AUTH_EXTERNAL_PORT=3784

# Storage location
STORAGE_ROOT=./storage  # Local setup
# STORAGE_ROOT=/nfs/containers  # NFS/network storage

# Database settings
MYSQL_ROOT_PASSWORD=your-secure-password
```

### Step 3: Deploy Layers in Order
```bash
# 1. Database layer (MySQL + backup system)
docker compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml up -d

# 2. Services layer (auth/world servers + modules)
docker compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml up -d

# 3. Tools layer (phpMyAdmin + Keira3)
docker compose --env-file docker-compose-azerothcore-tools.env -f docker-compose-azerothcore-tools.yml up -d
```

### Step 4: Monitor Deployment
```bash
# Watch post-install configuration
docker logs ac-post-install -f

# Check all services are healthy
docker ps
```

---

## 📋 What Gets Installed Automatically

### ✅ Core Server Components
- **AzerothCore 3.3.5a** - WotLK server application
- **MySQL 8.0** - Database with intelligent initialization and restoration
- **Smart Backup System** - Automated hourly/daily backups with intelligent restoration
- **phpMyAdmin** - Web-based database administration
- **Keira3** - Game content editor and developer tools

### ✅ 13 Enhanced Modules (✅ VERIFIED INTEGRATED)
All modules are automatically downloaded, configured, and SQL scripts executed:

| Module | Description | Status |
|--------|-------------|---------|
| **mod-playerbots** | AI companions for solo play | ✅ INTEGRATED |
| **mod-aoe-loot** | Streamlined loot collection | ✅ INTEGRATED |
| **mod-learn-spells** | Automatic spell learning | ✅ INTEGRATED |
| **mod-fireworks** | Level-up celebrations | ✅ INTEGRATED |
| **mod-individual-progression** | Personal advancement system | ✅ INTEGRATED |
| **mod-transmog** | Appearance customization | ✅ INTEGRATED |
| **mod-solo-lfg** | Solo dungeon access | ✅ INTEGRATED |
| **mod-eluna** | Lua scripting engine | ✅ INTEGRATED |
| **mod-arac** | All races/classes unlocked | ✅ INTEGRATED |
| **mod-npc-enchanter** | Enchanting services | ✅ INTEGRATED |
| **mod-assistant** | AI automation features | ✅ INTEGRATED |
| **mod-reagent-bank** | Reagent storage system | ✅ INTEGRATED |
| **mod-black-market** | Rare item auctions | ✅ INTEGRATED |

### ✅ Automated Configuration
- **Intelligent Database Setup** - Smart backup detection, restoration, and conditional schema import
- **Backup Management** - Automated scheduling, retention policies, and integrity validation
- **Realmlist Configuration** - Server address and port setup
- **Module Integration** - SQL scripts execution and config deployment
- **Service Restart** - Automatic restart to apply configurations
- **Health Monitoring** - Container health checks and restart policies

### ✅ Lua Scripting Environment
- **Example Scripts** - Welcome messages, level rewards, server info commands
- **Volume Mounting** - Scripts automatically loaded from `storage/lua_scripts/`
- **Development Tools** - Script reloading with `.reload eluna` command

---

## ⚠️ Manual Configuration Required

While most setup is automated, some modules require manual configuration:

### ✅ Module Integration Verification

**mod-playerbots Integration Status**
- **RESOLVED**: Now using compatible Docker images
- **Images**: `uprightbass360/azerothcore-wotlk-playerbots:*-Playerbot`
- **Branch**: AzerothCore Playerbot branch (confirmed in logs)
- **Database**: Playerbot tables created (`playerbots_rpg_races`)
- **Status**: Fully integrated and operational

**Module System Verification (All 13 modules)**
- **Binary Integration**: ✅ Compiled into WorldServer (Playerbot branch)
- **File System**: ✅ All modules present in `/azerothcore/modules/`
- **Database**: ✅ Module tables and SQL scripts executed
- **Configuration**: ✅ Module framework active in worldserver.conf
- **Process**: ✅ WorldServer running with 1.9GB RAM (normal for module build)

**Technical Verification Details**
- **Server Version**: `AzerothCore rev. 509eb73e0115+ (Playerbot branch)`
- **Docker Images**: All using `uprightbass360/azerothcore-wotlk-playerbots:*-Playerbot`
- **VMap Errors**: Non-critical cosmetic 3D model loading (safe to ignore)
- **Module Tables**: `module_string`, `module_string_locale`, `playerbots_rpg_races`
- **Lua Scripting**: Active with TypeScript compilation via ac-eluna container

### 📦 Client-Side Patches Required

**mod-individual-progression**
- **Required**: `patch-V.mpq` (Vanilla crafting/recipes)
- **Optional**: `patch-J.mpq`, `patch-U.mpq`
- **Location**: `storage/azerothcore/modules/mod-individual-progression/optional/`
- **Install**: Copy patches to client `WoW/Data/` directory

**mod-arac (All Races All Classes)**
- **Required**: `Patch-A.MPQ`
- **Location**: `storage/azerothcore/modules/mod-arac/patch-contents/`
- **Install**: Copy to client `WoW/Data/` directory

### ⚙️ Server Configuration Changes

**mod-individual-progression** requires worldserver.conf updates:
```ini
# Required settings in storage/azerothcore/config/worldserver.conf
EnablePlayerSettings = 1
DBC.EnforceItemAttributes = 0
```

**mod-aoe-loot** optimization:
```ini
# Prevent corpse cleanup issues
Rate.Corpse.Decay.Looted = 0.01
```

### 🤖 NPC Spawning Required

Several modules need NPCs spawned with GM commands:
```bash
# Transmog NPC
.npc add 190010

# Reagent Bank NPC
.npc add 290011

# NPC Enchanter (check module docs for ID)
.npc add [enchanter_id]
```

### 📋 Configuration Analysis Tool

Check your setup for missing configurations:
```bash
./scripts/configure-modules.sh
```

This script analyzes your enabled modules and provides specific guidance for resolving configuration issues.

---

## 🏗️ Architecture Overview

### Container Layers
```
┌─────────────────────────────────────────┐
│              Tools Layer                │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ phpMyAdmin  │  │   Keira3    │      │
│  │   :8081     │  │   :4201     │      │
│  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│             Services Layer              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │   Auth   │ │  World   │ │ Modules  │ │
│  │  :3784   │ │  :8215   │ │ Manager  │ │
│  └──────────┘ └──────────┘ └──────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ Client   │ │  Eluna   │ │Post-Inst │ │
│  │   Data   │ │TypeScript│ │  Config  │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│            Database Layer               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │  MySQL   │ │ DB-Init  │ │ Backup   │ │
│  │  :64306  │ │ (setup)  │ │ System   │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────┘
```

### Storage Structure
```
storage/azerothcore/
├── config/           # Server configuration files
├── data/             # Game client data (maps, DBC files)
├── logs/             # Server log files
├── modules/          # Module source code and configs
├── lua_scripts/      # Eluna Lua scripts
├── mysql-data/       # Database files
└── backups/          # Automated database backups
```

---

## 🛠️ Management Commands

### Health Monitoring
```bash
# Check all containers
docker ps

# View service logs
docker logs ac-worldserver -f
docker logs ac-authserver -f
docker logs ac-post-install -f

# Check module installation
docker logs ac-modules --tail 50
```

### Module Management
```bash
# Analyze module configuration
./scripts/configure-modules.sh

# Setup Lua scripting environment
./scripts/setup-eluna.sh

# Test Eluna scripts
docker exec ac-worldserver /bin/bash -c 'echo "reload eluna"'
```

### Database Operations
```bash
# Access database via phpMyAdmin
open http://localhost:8081

# Direct MySQL access
docker exec -it ac-mysql mysql -u root -p

# Manual backup
./scripts/backup.sh

# View backup status and restore options
ls -la storage/azerothcore/backups/
```

### Backup and Restoration System

The stack includes an intelligent backup and restoration system that automatically:

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
- **Status tracking**: Creates markers to communicate restoration status between services

**Backup Structure**
```
storage/azerothcore/backups/
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
```

**Manual Backup Operations**
```bash
# Create immediate backup
./scripts/backup.sh

# Restore from specific backup (interactive)
./scripts/restore.sh YYYYMMDD_HHMMSS

# View backup contents
zcat storage/azerothcore/backups/daily/20241004_090000/acore_world.sql.gz | head

# Check restoration status
cat storage/azerothcore/mysql-data/.restore-completed
```

---

## 🔧 Troubleshooting

### Common Issues

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
# Check if module is enabled
grep MODULE_NAME docker-compose-azerothcore-services.env

# Verify module installation
ls storage/azerothcore/modules/

# Check configuration files
ls storage/azerothcore/config/mod_*.conf*
```

**Database connection issues**
```bash
# Verify MySQL is running
docker exec ac-mysql mysql -u root -p -e "SELECT 1;"

# Check database initialization and backup detection
docker logs ac-db-init

# Check conditional import status
docker logs ac-db-import
```

**Backup and restoration issues**
```bash
# Check backup detection and restoration status
docker logs ac-db-init | grep -E "(backup|restore)"

# Verify backup directory contents
ls -la storage/azerothcore/backups/

# Check restoration status markers
ls -la storage/azerothcore/mysql-data/.restore-*
cat storage/azerothcore/mysql-data/.restore-completed

# Force fresh database import (if needed)
rm -f storage/azerothcore/mysql-data/.restore-*
docker compose -f docker-compose-azerothcore-database.yml restart ac-db-init
```

### Getting Help

Run the configuration analysis tool for specific guidance:
```bash
./scripts/configure-modules.sh
```

---

## 📚 Additional Documentation

- **[Module Configuration Requirements](docs/module-configuration-requirements.md)** - Detailed manual setup steps
- **[Lua Scripting Guide](storage/azerothcore/lua_scripts/README.md)** - Eluna development
- **[Deployment Scripts](scripts/README.md)** - Automation tools reference
- **[GitHub-Hosted Scripts](scripts/GITHUB-HOSTED-SCRIPTS.md)** - Service script documentation
- **[Deployment Guide](scripts/DEPLOYMENT.md)** - Complete deployment procedures
- **[Cleanup Guide](scripts/CLEANUP.md)** - Resource management procedures

---

## 🎯 Next Steps After Installation

1. **Test Client Connection** - Connect with WoW 3.3.5a client
2. **Spawn Required NPCs** - Use GM commands for service modules
3. **Apply Client Patches** - For mod-arac and mod-individual-progression
4. **Test Module Functionality** - Verify each module works as expected

---

## 📄 Implementation Credits

This project builds upon:
- **[AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)** - Core server application
- **[AzerothCore Docker Setup](https://github.com/coc0nut/AzerothCore-with-Playerbots-Docker-Setup)** - Initial containerization approach

### Key Improvements
- ✅ **Fully Automated Setup** - Interactive configuration script
- ✅ **13 Enhanced Modules** - Complete gameplay enhancement suite
- ✅ **Production Ready** - Health checks, backups, monitoring
- ✅ **Cross-Platform** - Docker and Podman support
- ✅ **Comprehensive Documentation** - Clear setup and troubleshooting guides
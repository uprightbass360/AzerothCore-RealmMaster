# AzerothCore Docker/Compose Stack

A complete containerized deployment of AzerothCore WoW 3.3.5a (Wrath of the Lich King) private server with 20+ enhanced modules, intelligent automation, and production-ready features.

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
./setup.sh
```

**3. Deploy Your Realm**
```bash
./deploy.sh
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

**6. Access Your Realm**
- **Game Server**: `your-server-ip:8215` (or port you configured)
- **Database Admin**: http://localhost:8081 (phpMyAdmin)
- **Game Content Editor**: http://localhost:4201 (Keira3)

✅ **That's it!** Your realm is ready with all enabled modules installed and configured.

---

## 📋 What Gets Installed Automatically

### ✅ Core Server Components
- **AzerothCore 3.3.5a** - WotLK server application
- **MySQL 8.0** - Database with intelligent initialization and restoration
- **Smart Module System** - Automated module management and source builds
- **phpMyAdmin** - Web-based database administration
- **Keira3** - Game content editor and developer tools

### ✅ Available Enhanced Modules

All modules are automatically downloaded, configured, and SQL scripts executed when enabled:

| Module | Description | Default Status |
|--------|-------------|----------------|
| **mod-solo-lfg** | Solo dungeon finder access | ✅ ENABLED |
| **mod-solocraft** | Dynamic instance scaling for solo play | ✅ ENABLED |
| **mod-autobalance** | Automatic raid/dungeon balancing | ✅ ENABLED |
| **mod-transmog** | Appearance customization system | ✅ ENABLED |
| **mod-npc-buffer** | NPC buffing services | ✅ ENABLED |
| **mod-learn-spells** | Automatic spell learning | ✅ ENABLED |
| **mod-fireworks** | Level-up celebrations | ✅ ENABLED |
| **mod-playerbots** | AI companions for solo play | 🔧 OPTIONAL |
| **mod-aoe-loot** | Streamlined loot collection | 🔧 OPTIONAL |
| **mod-individual-progression** | Personal advancement system | ❌ DISABLED* |
| **mod-ahbot** | Auction house bot | ❌ DISABLED* |
| **mod-dynamic-xp** | Dynamic experience rates | 🔧 OPTIONAL |
| **mod-1v1-arena** | Solo arena battles | 🔧 OPTIONAL |
| **mod-phased-duels** | Phased dueling system | 🔧 OPTIONAL |
| **mod-breaking-news** | Server announcement system | ❌ DISABLED* |
| **mod-boss-announcer** | Boss kill announcements | 🔧 OPTIONAL |
| **mod-account-achievements** | Account-wide achievements | 🔧 OPTIONAL |
| **mod-auto-revive** | Automatic resurrection | 🔧 OPTIONAL |
| **mod-gain-honor-guard** | Honor from guard kills | 🔧 OPTIONAL |
| **mod-arac** | All races/classes unlocked | 🔧 OPTIONAL |
| **mod-time-is-time** | Time manipulation | ❌ DISABLED* |
| **mod-pocket-portal** | Portal convenience | ❌ DISABLED* |
| **mod-random-enchants** | Random item enchantments | 🔧 OPTIONAL |
| **mod-pvp-titles** | PvP title system | 🔧 OPTIONAL |
| **mod-npc-beastmaster** | Pet management NPC | ❌ DISABLED* |
| **mod-npc-enchanter** | Enchanting services NPC | ❌ DISABLED* |
| **mod-assistant** | AI automation features | 🔧 OPTIONAL |
| **mod-reagent-bank** | Reagent storage system | 🔧 OPTIONAL |
| **mod-black-market** | Rare item auctions | 🔧 OPTIONAL |
| **mod-instance-reset** | Instance reset controls | ❌ DISABLED* |

*\* Disabled modules require additional configuration or have compatibility issues*

### ✅ Automated Configuration
- **Intelligent Database Setup** - Smart backup detection, restoration, and conditional schema import
- **Backup Management** - Automated hourly/daily backups with intelligent restoration
- **Module Integration** - Automatic source builds when C++ modules are enabled
- **Realmlist Configuration** - Server address and port setup
- **Service Orchestration** - Profile-based deployment (standard/playerbots/modules)
- **Health Monitoring** - Container health checks and restart policies

### ✅ Lua Scripting Environment
- **Eluna Engine** - Built-in Lua scripting support with TypeScript compilation
- **Script Auto-loading** - Scripts automatically loaded from `storage/lua_scripts/`
- **Development Tools** - Script reloading with `.reload eluna` command
- **Volume Mounting** - Hot-reload development environment

---

## 🏗️ Architecture Overview

### Container Profiles
```
┌─────────────────────────────────────────┐
│               Tools Profile             │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ phpMyAdmin  │  │   Keira3    │      │
│  │   :8081     │  │   :4201     │      │
│  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│            Services Profiles            │
│  Standard | Playerbots | Modules        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │   Auth   │ │  World   │ │  Client  │ │
│  │  :3784   │ │  :8215   │ │   Data   │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│          Database & Modules             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │  MySQL   │ │  Module  │ │ DB-Init  │ │
│  │  :64306  │ │ Manager  │ │  & Imp.  │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────┘
```

### Service Inventory & Ports

| Service / Container | Role | Ports (host → container) | Profile |
|---------------------|------|--------------------------|---------|
| `ac-mysql` | MySQL 8.0 database | `64306 → 3306` | `db` |
| `ac-authserver` | Auth server (standard) | `3784 → 3724` | `services-standard` |
| `ac-worldserver` | World server (standard) | `8215 → 8085`, `7778 → 7878` | `services-standard` |
| `ac-authserver-playerbots` | Playerbots auth | `3784 → 3724` | `services-playerbots` |
| `ac-worldserver-playerbots` | Playerbots world | `8215 → 8085`, `7778 → 7878` | `services-playerbots` |
| `ac-authserver-modules` | Custom build auth | `3784 → 3724` | `services-modules` |
| `ac-worldserver-modules` | Custom build world | `8215 → 8085`, `7778 → 7878` | `services-modules` |
| `ac-client-data` | Client data fetcher | – | `client-data` |
| `ac-modules` | Module manager | – | `modules` |
| `ac-phpmyadmin` | Database admin UI | `8081 → 80` | `tools` |
| `ac-keira3` | Game content editor | `4201 → 8080` | `tools` |

### Storage Structure
```
storage/
├── config/           # Server configuration files
├── data/             # Game client data (maps, DBC files)
├── logs/             # Server log files
├── modules/          # Module source code and configs
├── mysql-data/       # Database files
└── backups/          # Automated database backups
```

---

## 🛠️ Management Commands

### Health Monitoring
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

### Module Management
```bash
# Reconfigure modules via interactive setup
./setup.sh

# Deploy with specific profile
./deploy.sh --profile standard      # Standard AzerothCore
./deploy.sh --profile playerbots    # Playerbots branch
./deploy.sh --profile modules       # Custom modules build

# Force source rebuild
./scripts/rebuild-with-modules.sh --yes

# Stage services without full deployment
./scripts/stage-modules.sh

# Launch management tooling (phpMyAdmin + Keira3)
./scripts/deploy-tools.sh
```

### Database Operations
```bash
# Access database via phpMyAdmin
open http://localhost:8081

# Direct MySQL access
docker exec -it ac-mysql mysql -u root -p

# Manual backup operations
./scripts/backup.sh                              # Create immediate backup
./scripts/restore.sh YYYYMMDD_HHMMSS            # Restore from specific backup

# View available backups
ls -la storage/backups/
```

### Deployment Verification
```bash
# Quick health check
./verify-deployment.sh --skip-deploy --quick

# Full deployment verification
./verify-deployment.sh
```

---

## 🔧 Advanced Configuration

### Module-Specific Requirements

Some modules require additional manual configuration after deployment:

#### mod-playerbots
- Requires playerbots-specific AzerothCore branch
- Automatically handled when `MODULE_PLAYERBOTS=1` is set in setup

#### mod-individual-progression
- **Client patches required**: `patch-V.mpq` (found in module storage)
- **Server config**: Add `EnablePlayerSettings = 1` and `DBC.EnforceItemAttributes = 0` to worldserver.conf

#### mod-transmog / mod-npc-* modules
- **NPC spawning required**: Use GM commands to spawn service NPCs
- Examples:
  ```bash
  .npc add 190010    # Transmog NPC
  .npc add 290011    # Reagent Bank NPC
  # Check module docs for enchanter/beastmaster NPC IDs
  ```

#### mod-arac (All Races All Classes)
- **Client patches required**: `Patch-A.MPQ` (found in module storage)
- **Installation**: Players must copy to `WoW/Data/` directory
- **Server-side**: DBC files automatically applied during module installation

### Profile Selection

The deployment system automatically selects profiles based on enabled modules:

- **services-standard**: No special modules enabled
- **services-playerbots**: `MODULE_PLAYERBOTS=1` enabled
- **services-modules**: Any C++ modules enabled (requires source rebuild)

### Custom Builds

When C++ modules are enabled, the system automatically:
1. Clones/updates AzerothCore source
2. Syncs enabled modules into source tree
3. Rebuilds server images with modules compiled in
4. Tags custom images for deployment

### MySQL Runtime Storage & Timezone Data

- `MYSQL_RUNTIME_TMPFS_SIZE` controls the in-memory datadir used by the MySQL container. Increase this value if you see `No space left on device` errors inside `/var/lib/mysql-runtime`.
- `MYSQL_INNODB_REDO_LOG_CAPACITY` increases redo log headroom (defaults to `512M`). Raise it further if logs report `log_checkpointer` lag.
- `HOST_ZONEINFO_PATH` should point to a host directory containing timezone definitions (defaults to `/usr/share/zoneinfo`). The path is mounted read-only so the container can load timezone tables without extra image customization. Set it to a valid directory on your host if your OS stores zoneinfo elsewhere.

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
ls -la ./source/azerothcore/

# Force source setup
./scripts/setup-source.sh
```

### Getting Help

1. **Check service status**: `./status.sh --watch`
2. **Review logs**: `docker logs <service-name> -f`
3. **Verify configuration**: Check `.env` file for proper module toggles
4. **Clean deployment**: Stop all services and redeploy with `./deploy.sh`

### Backup and Restoration System

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
```

---

## 📚 Advanced Deployment Options

### Custom Environment Configuration
```bash
# Generate environment with custom settings
./setup.sh

# Deploy with specific options
./deploy.sh --profile modules --no-watch --keep-running
```

### Source Management
```bash
# Setup/update AzerothCore source
./scripts/setup-source.sh

# Rebuild with modules (manual)
./scripts/rebuild-with-modules.sh --yes --source ./custom/path
```

### Cleanup Operations
```bash
# Stop all services
docker compose --profile db --profile services-standard \
  --profile services-playerbots --profile services-modules \
  --profile client-data --profile modules --profile tools down

# Clean rebuild (modules changed)
rm -f storage/modules/.requires_rebuild
./deploy.sh --profile modules
```

---

## 🎯 Next Steps After Installation

1. **Test Client Connection** - Connect with WoW 3.3.5a client using configured realmlist
2. **Create Characters** - Test account creation and character creation
3. **Verify Modules** - Test enabled module functionality in-game
4. **Configure Optional Features** - Enable additional modules as needed
5. **Set Up Backups** - Configure automated backup retention policies

---

## 📄 Project Credits

This project builds upon:
- **[AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)** - Core server application
- **[AzerothCore Module Community](https://github.com/azerothcore)** - Enhanced gameplay modules

### Key Features
- ✅ **Fully Automated Setup** - Interactive configuration and deployment
- ✅ **Intelligent Module System** - Automatic source builds and profile selection
- ✅ **Production Ready** - Health checks, backups, monitoring
- ✅ **Cross-Platform** - Docker and Podman support
- ✅ **Comprehensive Documentation** - Clear setup and troubleshooting guides

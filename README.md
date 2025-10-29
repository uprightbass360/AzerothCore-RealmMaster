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

> ℹ️ **Image Sources:** Vanilla/standard profiles run the upstream `acore/*` images. As soon as you enable playerbots or any C++ module, the toolchain switches to the `uprightbass360/azerothcore-wotlk-playerbots` fork, rebuilds it locally when needed, and produces fresh `uprightbass360/...:modules-latest` tags.

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
- **Smart Module System** - Automated module management and source builds (compiles the uprightbass360 playerbot fork whenever modules need C++ changes)
- **phpMyAdmin** - Web-based database administration
- **Keira3** - Game content editor and developer tools

### ✅ Available Enhanced Modules

All modules are automatically downloaded, configured, and SQL scripts executed when enabled:

| Module | Description | Default Status |
|--------|-------------|----------------|
| **[mod-solo-lfg](https://github.com/azerothcore/mod-solo-lfg)** | A solo-friendly queue that lets every player run dungeons without needing a premade group. | ✅ ENABLED |
| **[mod-solocraft](https://github.com/azerothcore/mod-solocraft)** | Automatically scales dungeon and raid encounters so solo players or small teams can clear content. | ✅ ENABLED |
| **[mod-autobalance](https://github.com/azerothcore/mod-autobalance)** | Adjusts creature health and damage in real time to keep fights tuned for the current party size. | ✅ ENABLED |
| **[mod-transmog](https://github.com/azerothcore/mod-transmog)** | Adds a transmogrification vendor so players can restyle gear without changing stats. | ✅ ENABLED |
| **[mod-npc-buffer](https://github.com/azerothcore/mod-npc-buffer)** | Provides a ready-to-use buff NPC who hands out class buffs, food, and utility spells. | ✅ ENABLED |
| **[mod-learn-spells](https://github.com/azerothcore/mod-learn-spells)** | Teaches class spells automatically at the correct level to streamline leveling. | ✅ ENABLED |
| **[mod-fireworks](https://github.com/azerothcore/mod-fireworks-on-level)** | Spawns celebratory fireworks whenever a player dings a new level. | ✅ ENABLED |
| **[mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)** | Adds scriptable playerbot characters that can form dungeon parties, raid, and PvP with humans. | 🔧 OPTIONAL |
| **[mod-aoe-loot](https://github.com/azerothcore/mod-aoe-loot)** | Lets characters loot multiple corpses with one click for faster farming. | 🔧 OPTIONAL |
| **[mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression)** | Tracks each character through Vanilla → TBC → WotLK progression, unlocking content sequentially. | ❌ DISABLED* |
| **[mod-ahbot](https://github.com/azerothcore/mod-ahbot)** | Populates the auction house with configurable buying/selling behavior to keep markets active. | ❌ DISABLED* |
| **[mod-dynamic-xp](https://github.com/azerothcore/mod-dynamic-xp)** | Tweaks XP gain based on population or custom rules to keep leveling flexible. | 🔧 OPTIONAL |
| **[mod-1v1-arena](https://github.com/azerothcore/mod-1v1-arena)** | Creates a structured 1v1 ranked arena ladder for duel enthusiasts. | 🔧 OPTIONAL |
| **[mod-phased-duels](https://github.com/azerothcore/mod-phased-duels)** | Moves duelers into their own phase to block interference and griefing. | 🔧 OPTIONAL |
| **[mod-breaking-news](https://github.com/azerothcore/mod-breaking-news-override)** | Replaces the client breaking-news panel with server-managed announcements. | ❌ DISABLED* |
| **[mod-boss-announcer](https://github.com/azerothcore/mod-boss-announcer)** | Broadcasts dramatic messages when raid bosses fall to your players. | 🔧 OPTIONAL |
| **[mod-account-achievements](https://github.com/azerothcore/mod-account-achievements)** | Shares achievements across characters on the same account for persistent milestones. | 🔧 OPTIONAL |
| **[mod-auto-revive](https://github.com/azerothcore/mod-auto-revive)** | Automatically resurrects characters on death—handy for casual PvE or testing realms. | 🔧 OPTIONAL |
| **[mod-gain-honor-guard](https://github.com/azerothcore/mod-gain-honor-guard)** | Awards honor when players kill city guards, spicing up world PvP raids. | 🔧 OPTIONAL |
| **[mod-arac](https://github.com/heyitsbench/mod-arac)** | Unlocks every race/class pairing so players can roll any combination they want (needs client patch). | 🔧 OPTIONAL |
| **[mod-time-is-time](https://github.com/dunjeon/mod-TimeIsTime)** | Adds experimental time-twisting mechanics suited for custom events (requires extra tuning). | ❌ DISABLED* |
| **[mod-pocket-portal](https://github.com/azerothcore/mod-pocket-portal)** | Gives players a portal gadget for quick travel to configured destinations. | ❌ DISABLED* |
| **[mod-random-enchants](https://github.com/azerothcore/mod-random-enchants)** | Rolls randomised stat bonuses on loot to add Diablo-style gear chasing. | 🔧 OPTIONAL |
| **[mod-pvp-titles](https://github.com/azerothcore/mod-pvp-titles)** | Restores classic honor titles with a configurable ranking ladder. | 🔧 OPTIONAL |
| **[mod-npc-beastmaster](https://github.com/azerothcore/mod-npc-beastmaster)** | Adds an NPC who can teach, reset, and manage hunter pets for convenience. | ❌ DISABLED* |
| **[mod-npc-enchanter](https://github.com/azerothcore/mod-npc-enchanter)** | Introduces an enchanting vendor who applies enchants directly for a fee. | ❌ DISABLED* |
| **[mod-assistant](https://github.com/noisiver/mod-assistant)** | Spawns an all-purpose assistant NPC with heirlooms, professions, and convenience commands. | 🔧 OPTIONAL |
| **[mod-reagent-bank](https://github.com/ZhengPeiRu21/mod-reagent-bank)** | Lets players stash crafting reagents with a dedicated banker NPC. | 🔧 OPTIONAL |
| **[mod-black-market](https://github.com/Youpeoples/Black-Market-Auction-House)** | Backports the Mists-era Black Market Auction House via Eluna scripts. | 🔧 OPTIONAL |
| **[mod-instance-reset](https://github.com/azerothcore/mod-instance-reset)** | Adds commands to reset instances quickly—useful for testing or events. | ❌ DISABLED* |
| **[mod-challenge-modes](https://github.com/ZhengPeiRu21/mod-challenge-modes)** | Implements keystone-style timed runs with leaderboards and scaling modifiers. | 🔧 OPTIONAL |
| **[mod-ollama-chat](https://github.com/DustinHendrickson/mod-ollama-chat)** | Connects playerbots to an Ollama LLM so they can chat with humans organically. | ❌ DISABLED* |
| **[mod-player-bot-level-brackets](https://github.com/DustinHendrickson/mod-player-bot-level-brackets)** | Keeps bot levels spread evenly across configured brackets to match your player base. | 🔧 OPTIONAL |
| **[mod-bg-slaveryvalley](https://github.com/Helias/mod-bg-slaveryvalley)** | Adds the Slavery Valley battleground complete with objectives and queue hooks. | ❌ DISABLED* |
| **[mod-azerothshard](https://github.com/azerothcore/mod-azerothshard)** | Bundles AzerothShard tweaks: utility NPCs, scripted events, and gameplay improvements. | 🔧 OPTIONAL |
| **[mod-worgoblin](https://github.com/heyitsbench/mod-worgoblin)** | Enables Worgen and Goblin characters, including necessary DB/DBC adjustments (client patch required). | ❌ DISABLED* |
| **[StatBooster](https://github.com/AnchyDev/StatBooster)** | Lets players refine gear stats by rerolling random enchantments with special materials. | 🔧 OPTIONAL |
| **[DungeonRespawn](https://github.com/AnchyDev/DungeonRespawn)** | Teleports dead players back to the dungeon entrance instead of a distant graveyard. | 🔧 OPTIONAL |
| **[skeleton-module](https://github.com/azerothcore/skeleton-module)** | Provides a minimal AzerothCore module scaffold so you can build new features quickly. | 🔧 OPTIONAL |
| **[eluna-ts](https://github.com/azerothcore/eluna-ts)** | Adds a TS-to-Lua workflow so Eluna scripts can be authored with modern tooling. | 🔧 OPTIONAL |

*\* Disabled modules require additional configuration or have compatibility issues*

### Module Summaries
- **mod-solo-lfg** – Enables the Dungeon Finder for solo players so every character can queue without a full party.
- **mod-solocraft** – Dynamically scales dungeon and raid encounters to match the current group size for flexible difficulty.
- **mod-autobalance** – Automatically adjusts creature health and damage to keep combat balanced for any party composition.
- **mod-transmog** – Adds the transmogrification system so players can change the appearance of their gear without losing stats.
- **mod-npc-buffer** – Introduces a convenient buff vendor that can apply class buffs, raid consumables, and other services.
- **mod-learn-spells** – Grants characters their class spells automatically at the appropriate levels to streamline leveling.
- **mod-fireworks** – Celebrates each level up by launching fireworks around the player for a festive visual effect.
- **mod-playerbots** – Spawns AI-controlled characters that can form parties, fill raids, and run battlegrounds alongside real players.
- **mod-aoe-loot** – Allows players to loot all nearby corpses with a single click, speeding up farming runs.
- **mod-individual-progression** – Tracks progression per character so content unlocks in a Vanilla → TBC → WotLK order.
- **mod-ahbot** – Provides an automated auction house with configurable buying and selling behavior to keep markets stocked.
- **mod-dynamic-xp** – Adjusts experience rates based on population or configured rules to keep leveling pace consistent.
- **mod-1v1-arena** – Adds a dedicated duel-style arena ladder where players can queue for structured 1v1 battles.
- **mod-phased-duels** – Moves duel participants into a phased area to prevent outside interference during the fight.
- **mod-breaking-news** – Replaces the character select breaking news panel with custom announcements hosted by your server.
- **mod-boss-announcer** – Broadcasts dramatic kill messages when raid bosses die to spotlight your community’s victories.
- **mod-account-achievements** – Shares achievements across characters on the same account so progress feels persistent.
- **mod-auto-revive** – Revives players automatically on death, ideal for testing realms or ultra-casual PvE environments.
- **mod-gain-honor-guard** – Awards honor for killing enemy guards to encourage city raids and world PvP skirmishes.
- **mod-arac** – Unlocks every race/class combination, letting players create any fantasy they can imagine (client patch required).
- **mod-time-is-time** – Provides time-manipulation gameplay hooks for custom events or encounter scripting (requires tuning).
- **mod-pocket-portal** – Gives players a personal portal device for fast travel to configured locations.
- **mod-random-enchants** – Rolls random stat bonuses on loot to introduce an ARPG-style layer of gear hunting.
- **mod-pvp-titles** – Restores classic PvP titles with configurable ranking so your battleground heroes stand out.
- **mod-npc-beastmaster** – Adds a beastmaster NPC who sells, resets, and manages hunter pets for convenience.
- **mod-npc-enchanter** – Offers enchanting services via an NPC who can apply chosen enchants for a fee.
- **mod-assistant** – Spawns an all-in-one assistant NPC that handles heirlooms, glyphs, professions, and utility commands.
- **mod-reagent-bank** – Creates a reagent banker NPC with extra storage tailored to crafters and raid prep.
- **mod-black-market** – Backports the Mists of Pandaria Black Market Auction House with Lua-powered bidding and rotation.
- **mod-instance-reset** – Adds commands and automation to reset instances on demand, useful for rapid testing.
- **mod-challenge-modes** – Introduces timed keystone-style dungeon runs with leaderboards and escalating modifiers.
- **mod-ollama-chat** – Connects playerbots to an Ollama LLM endpoint so they can converse with human players in natural language.
- **mod-player-bot-level-brackets** – Keeps playerbot levels evenly distributed by moving bots between configured brackets.
- **mod-bg-slaveryvalley** – Ports the custom Slavery Valley battleground complete with objectives and queue integration.
- **mod-azerothshard** – Bundles numerous AzerothShard quality-of-life tweaks, NPCs, and scripted content in one module.
- **mod-worgoblin** – Adds Worgen and Goblin as playable races, including start zones and necessary data patches.
- **StatBooster** – Lets players reroll item stats using a random enchant system to chase perfect gear.
- **DungeonRespawn** – Teleports dead players back to dungeon entrances instead of the nearest graveyard to cut down on downtime.
- **skeleton-module** – Provides a minimal module template with build hooks and examples for rapidly prototyping your own features.
- **eluna-ts** – Adds a TypeScript toolchain that transpiles to Eluna Lua scripts so you can author scripts with modern tooling.

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

## 🚀 Deploying to a Remote Server

Use this workflow to build locally, then push the same stack to a remote host:

1. **Configure & Rebuild Locally**
   ```bash
   ./setup.sh
   ./scripts/rebuild-with-modules.sh --yes
   ```
   (Answer “y” to the rebuild prompt in `setup.sh`, or run the rebuild manually.)

2. **Package & Push for Remote Deploy**
   ```bash
   ./deploy.sh --yes \
     --remote-host docker-server \
     --remote-user sam \
     --remote-project-dir /home/sam/src/acore-compose
   ```
   Add `--remote-identity ~/.ssh/id_ed25519` if you need a non-default SSH key, or `--remote-skip-storage` to avoid syncing the `storage/` directory.

3. **Deploy Remotely**
   ```bash
ssh docker-server '
  cd /home/sam/src/acore-compose &&
  ./deploy.sh --yes --no-watch
'
   ```
   Because the `.env` now points the modules profile at the `uprightbass360/...:modules-latest` tags, the remote compose run uses the build you just migrated—no additional rebuild required.

4. **Verify**
   ```bash
   ./status.sh --once
   docker compose --profile services-playerbots logs --tail 100 ac-worldserver
   ```

### Remote Deploy Workflow
1. **Configure & Build Locally**
   ```bash
   ./setup.sh --module-config sam --playerbot-max-bots 3000
   ./scripts/rebuild-with-modules.sh --yes
   ```
2. **Migrate Stack to Remote**
   ```bash
   ./deploy.sh --yes \
     --remote-host docker-server \
     --remote-user sam \
     --remote-project-dir /home/sam/src/acore-compose
   ```
   (Under the hood this wraps `scripts/migrate-stack.sh`, exporting module images to `local-storage/images/acore-modules-images.tar` and syncing `storage/` unless `--remote-skip-storage` is provided.)
3. **Deploy on Remote Host**
   ```bash
ssh docker-server '
  cd /home/sam/src/acore-compose &&
  ./deploy.sh --yes --no-watch
'
   ```
4. **Verify Services**
   ```bash
   ./status.sh --once
   docker compose --profile services-playerbots logs --tail 100 ac-worldserver
   ```

### Module Presets
- Drop comma-separated module lists into `configurations/*.conf` (for example `configurations/playerbot-modules.conf`).
- `setup.sh` automatically adds these presets to the module menu and enables the listed modules when selected or when `--module-config <name>` is provided.
- Built-in presets:
  - `configurations/suggested-modules.conf` – default solo-friendly QoL stack.
  - `configurations/playerbots-suggested-modules.conf` – suggested stack plus playerbots.
  - `configurations/playerbot-only.conf` – playerbot-focused profile (adjust `--playerbot-max-bots`).
- Custom example:
  - `configurations/sam.conf` – Sam's playerbot-focused profile (set `--playerbot-max-bots 3000` when using this preset).

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
│  ┌─────────────────────────────────────┐ │
│  │      Post-Install Config            │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│        Database & Module System         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │  MySQL   │ │  Module  │ │ DB-Init  │ │
│  │  :64306  │ │ Manager  │ │  Setup   │ │
│  └──────────┘ └──────────┘ └──────────┘ │
│  ┌──────────┐ ┌─────────────────────────┐ │
│  │ DB-Import│ │      Backup System      │ │
│  │  Schema  │ │    (Automated Tasks)    │ │
│  └──────────┘ └─────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Service Inventory & Ports

| Service / Container | Role | Ports (host → container) | Profile |
|---------------------|------|--------------------------|---------|
| `ac-mysql` | MySQL 8.0 database | `64306 → 3306` | `db` |
| `ac-db-init` | Database schema initialization | – | `db` |
| `ac-db-import` | Database content import | – | `db` |
| `ac-backup` | Automated backup system | – | `db` |
| `ac-authserver` | Auth server (standard) | `3784 → 3724` | `services-standard` |
| `ac-worldserver` | World server (standard) | `8215 → 8085`, `7778 → 7878` | `services-standard` |
| `ac-authserver-playerbots` | Playerbots auth | `3784 → 3724` | `services-playerbots` |
| `ac-worldserver-playerbots` | Playerbots world | `8215 → 8085`, `7778 → 7878` | `services-playerbots` |
| `ac-authserver-modules` | Custom build auth | `3784 → 3724` | `services-modules` |
| `ac-worldserver-modules` | Custom build world | `8215 → 8085`, `7778 → 7878` | `services-modules` |
| `ac-client-data` | Client data fetcher | – | `client-data` |
| `ac-modules` | Module manager | – | `modules` |
| `ac-post-install` | Post-installation configuration | – | Auto-start |
| `ac-phpmyadmin` | Database admin UI | `8081 → 80` | `tools` |
| `ac-keira3` | Game content editor | `4201 → 8080` | `tools` |

### Storage Structure
```
storage/
├── config/           # Server configuration files
├── logs/             # Server log files
├── modules/          # Module source code and configs
├── mysql-data/       # Database files (now under ./local-storage)
└── backups/          # Automated database backups
```

`ac-client-data` keeps unpacked game assets in the `${CLIENT_DATA_VOLUME:-ac-client-data}` Docker volume so reads stay on the local host, while download archives are cached under `${CLIENT_DATA_CACHE_PATH}` on fast local storage even when `${STORAGE_PATH}` points to remote or NFS storage.

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

### Web Tools Access

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

### Module Management
```bash
# Reconfigure modules via interactive setup
./setup.sh

# Deploy with specific profile
./deploy.sh --profile standard      # Standard AzerothCore
./deploy.sh --profile playerbots    # Playerbots branch
./deploy.sh --profile modules       # Custom modules build

# Module staging and compilation
./scripts/stage-modules.sh                    # Download and stage enabled modules (preps upright playerbot builds)
./scripts/rebuild-with-modules.sh --yes       # Rebuild uprightbass360/playerbot images with your modules
./scripts/setup-source.sh                     # Initialize/update source repositories (auto-switches to playerbot fork for modules)

# Module configuration management
./scripts/copy-module-configs.sh              # Create module .conf files
./scripts/manage-modules-sql.sh               # Execute module SQL scripts

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

# User data backup/import utilities
./backup-export.sh [output_dir]                 # Export user accounts & characters
./backup-import.sh [backup_dir]                 # Import user data from backup

# View available backups
ls -la storage/backups/
```

### Container Management
```bash
# Start specific services
./start-containers.sh                           # Start all configured containers

# Stop services gracefully
./stop-containers.sh                            # Stop all containers

# Monitor service health
./status.sh                                     # Check realm status
./status.sh --watch                            # Watch services continuously
./status.sh --once                             # Single status check
```

### Deployment Verification
```bash
# Quick health check
./verify-deployment.sh --skip-deploy --quick

# Full deployment verification
./verify-deployment.sh
```

---

## 📜 Script Reference

### Core Deployment Scripts

#### `setup.sh` - Interactive Environment Configuration
Interactive `.env` generator with module selection, server configuration, and deployment profiles.

```bash
./setup.sh                                      # Interactive configuration
./setup.sh --module-config sam                 # Use predefined module preset
./setup.sh --playerbot-max-bots 3000          # Set playerbot limits
```

#### `deploy.sh` - High-Level Deployment Orchestrator
Module-aware deployment with automatic source builds and profile selection.

```bash
./deploy.sh                                     # Auto-deploy with optimal profile
./deploy.sh --profile standard                 # Force standard AzerothCore
./deploy.sh --profile playerbots               # Force playerbots branch
./deploy.sh --profile modules                  # Force custom modules build
./deploy.sh --skip-rebuild --no-watch         # Deploy without rebuild/logs
./deploy.sh --keep-running                     # Deploy and exit (no log tailing)
```

#### `cleanup.sh` - Project Cleanup Utility
Comprehensive cleanup with multiple destruction levels and safety checks.

```bash
./cleanup.sh                                   # Interactive cleanup
./cleanup.sh --soft                           # Stop containers only
./cleanup.sh --hard                           # Remove containers, networks, volumes
./cleanup.sh --nuclear                        # Full cleanup including images
./cleanup.sh --preserve-backups               # Retain backup data during cleanup
./cleanup.sh --dry-run                        # Preview cleanup actions
```

### Container Lifecycle Management

#### `start-containers.sh` - Service Startup
Starts all configured containers using appropriate profiles.

#### `stop-containers.sh` - Graceful Shutdown
Stops all containers with proper cleanup and data protection.

#### `status.sh` - Service Health Monitoring
```bash
./status.sh                                    # Single status check with summary
./status.sh --watch                           # Continuous monitoring mode
./status.sh --once                            # Script-friendly single check
```

### Database & Backup Management

#### `backup-export.sh` - User Data Export
Exports user accounts and character data for migration or backup purposes.

```bash
./backup-export.sh                            # Export to ExportBackup_<timestamp>/
./backup-export.sh /path/to/backup/dir       # Export to specific directory
```

**Output Structure:**
```
ExportBackup_YYYYMMDD_HHMMSS/
├── acore_auth.sql.gz         # User accounts
├── acore_characters.sql.gz   # Character data
└── manifest.json             # Backup metadata
```

#### `backup-import.sh` - User Data Import
Restores user accounts and characters from backup while preserving world data.

```bash
./backup-import.sh                            # Import from ImportBackup/
./backup-import.sh /path/to/backup           # Import from specific directory
```

**Required Files:**
- `acore_auth.sql[.gz]` - User accounts (required)
- `acore_characters.sql[.gz]` - Character data (required)
- `acore_world.sql[.gz]` - World data (optional)

### Module Management Scripts

#### `scripts/stage-modules.sh` - Module Staging
Downloads and stages enabled modules for source integration.

```bash
./scripts/stage-modules.sh                    # Stage all enabled modules
```

#### `scripts/rebuild-with-modules.sh` - Source Compilation
Rebuilds AzerothCore with enabled C++ modules compiled into the binaries.

```bash
./scripts/rebuild-with-modules.sh --yes       # Rebuild with confirmation bypass
./scripts/rebuild-with-modules.sh --source ./custom/path  # Custom source path
```

#### `scripts/setup-source.sh` - Source Repository Setup
Initializes or updates AzerothCore source repositories for compilation.

```bash
./scripts/setup-source.sh                     # Setup source for current configuration
```

#### `scripts/manage-modules.sh` - Module Management Container
Internal script that manages module lifecycle within the ac-modules container.

#### `scripts/manage-modules-sql.sh` - Module Database Integration
Executes module-specific SQL scripts for database schema updates.

#### `scripts/copy-module-configs.sh` - Configuration File Management
Creates module `.conf` files from `.dist.conf` templates for active modules.

```bash
./scripts/copy-module-configs.sh              # Create missing module configs
```

### Post-Deployment Automation

#### `scripts/auto-post-install.sh` - Post-Installation Configuration
Automated post-deployment tasks including module configuration, service verification, and initial setup.

```bash
./scripts/auto-post-install.sh                # Run post-install tasks
```

**Automated Tasks:**
1. Module configuration file creation
2. Service health verification
3. Database connectivity testing
4. Initial realm configuration

### Advanced Deployment Tools

#### `scripts/migrate-stack.sh` - Remote Deployment Migration
Migrates locally built images and configuration to remote hosts.
You can call this directly, or use `./deploy.sh --remote-host <host> --remote-user <user>` which wraps the same workflow.

```bash
./scripts/migrate-stack.sh \
  --host docker-server \
  --user sam \
  --project-dir /home/sam/acore-compose       # Migrate to remote host

./scripts/migrate-stack.sh \
  --host remote.example.com \
  --identity ~/.ssh/deploy_key \
  --skip-storage                              # Migrate without storage sync
```

#### `scripts/deploy-tools.sh` - Management Tools Deployment
Deploys web-based management tools (phpMyAdmin, Keira3) independently.

```bash
./scripts/deploy-tools.sh                     # Deploy management tools only
```

#### `verify-deployment.sh` - Deployment Validation
Comprehensive deployment verification with health checks and service validation.

```bash
./verify-deployment.sh                        # Full deployment verification
./verify-deployment.sh --skip-deploy         # Verify existing deployment
./verify-deployment.sh --quick               # Quick health check only
```

### Backup System Scripts

#### `scripts/backup-scheduler.sh` - Automated Backup Service
Runs inside the backup container to provide scheduled database backups.

**Features:**
- Hourly backups (retained for 6 hours)
- Daily backups (retained for 3 days)
- Automatic cleanup based on retention policies
- Database detection (includes playerbots if present)

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
ls -la "${STORAGE_PATH_LOCAL:-./local-storage}/source/azerothcore/"

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

# User data import/export
ExportBackup_YYYYMMDD_HHMMSS/     # Created by backup-export.sh
├── acore_auth.sql.gz             # User accounts
├── acore_characters.sql.gz       # Character data
└── manifest.json

ImportBackup/                     # Used by backup-import.sh
├── acore_auth.sql[.gz]           # Required: accounts
├── acore_characters.sql[.gz]     # Required: characters
└── acore_world.sql[.gz]          # Optional: world data
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

## 🧭 Ownership Hardening TODO

- [ ] MySQL container: prototype running as `${CONTAINER_USER}` (or via Docker userns remap/custom entrypoint) so shared `${STORAGE_PATH}` data stays user-owned while preserving required init privileges.

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

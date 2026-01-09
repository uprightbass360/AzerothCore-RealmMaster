# Deploying Pre-Built RealmMaster Images

This guide explains how to deploy AzerothCore RealmMaster using pre-built Docker images from Docker Hub. **No local building required!**

## What's Included in Pre-Built Images

The pre-built images are automatically built nightly with the **RealmMaster module profile**, which includes **32 carefully selected modules**:

- **MODULE_PLAYERBOTS** - AI-controlled player characters
- **MODULE_TRANSMOG** - Transmogrification system
- **MODULE_SOLO_LFG** - Solo dungeon finder
- **MODULE_ELUNA** - Lua scripting engine
- **MODULE_AIO** - All-in-one interface
- **MODULE_NPC_BUFFER** - Buff NPC
- **MODULE_NPC_BEASTMASTER** - Pet management
- **MODULE_SOLOCRAFT** - Solo dungeon scaling
- **MODULE_1V1_ARENA** - 1v1 arena system
- **MODULE_ACCOUNT_ACHIEVEMENTS** - Account-wide achievements
- ...and 22 more modules!

See `config/module-profiles/RealmMaster.json` for the complete list.

## Prerequisites

- Docker with Docker Compose v2
- 16GB+ RAM
- 64GB+ storage
- Linux/macOS/WSL2

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/uprightbass360/AzerothCore-RealmMaster.git
cd AzerothCore-RealmMaster
```

### 2. Create Configuration File

```bash
# Copy the pre-built images template
cp .env.prebuilt .env
```

### 3. Configure Docker Hub Username

Edit `.env` and set your Docker Hub username:

```bash
# Change this line:
DOCKERHUB_USERNAME=your-dockerhub-username

# To (example):
DOCKERHUB_USERNAME=uprightbass360
```

### 4. Optional: Customize Settings

Edit `.env` to customize:

- **Server address**: `SERVER_ADDRESS=your-server-ip`
- **Passwords**: `MYSQL_ROOT_PASSWORD=your-password`
- **Playerbot population**: `PLAYERBOT_MIN_BOTS` and `PLAYERBOT_MAX_BOTS`
- **Server preset**: `SERVER_CONFIG_PRESET=fast-leveling` (or blizzlike, hardcore-pvp, casual-pve)

### 5. Deploy

```bash
./deploy.sh
```

The deployment will:
- Pull pre-built images from Docker Hub
- Set up MySQL database with all module SQL
- Configure client data
- Start all services

**First deployment takes 30-60 minutes** for database setup and client data download.

## Image Tags

The CI/CD workflow publishes images with **profile-specific tags** so you know exactly which modules are included:

### Profile-Tagged Images (Recommended)

Each module profile gets its own tag:

- **`:authserver-realmmaster-latest`** - RealmMaster profile (32 modules)
- **`:worldserver-realmmaster-latest`** - RealmMaster profile (32 modules)
- **`:authserver-realmmaster-YYYYMMDD`** - Date-tagged RealmMaster builds
- **`:worldserver-realmmaster-YYYYMMDD`** - Date-tagged RealmMaster builds

Other profiles (available when built via GitHub Actions):
- **`:authserver-suggested-modules-latest`** - Suggested modules profile (not yet published)
- **`:authserver-all-modules-latest`** - All modules profile (not yet published)
- **`:authserver-playerbots-only-latest`** - Playerbots only (not yet published)

**Note**: Currently only the RealmMaster profile is built nightly. Other profiles can be built on-demand by manually triggering the CI/CD workflow.

### Generic Tags (Backward Compatibility)

- **`:authserver-latest`** - Latest build (defaults to RealmMaster profile)
- **`:worldserver-latest`** - Latest build (defaults to RealmMaster profile)

### Choosing a Profile

In `.env.prebuilt`, set the `MODULE_PROFILE` variable:

```bash
# Choose your profile
MODULE_PROFILE=realmmaster          # 32 modules (default, recommended)
# MODULE_PROFILE=suggested-modules  # Alternative module set
# MODULE_PROFILE=all-modules        # All supported modules
# MODULE_PROFILE=playerbots-only    # Just playerbots

# Images automatically reference the selected profile
AC_AUTHSERVER_IMAGE_MODULES=${DOCKERHUB_USERNAME}/${COMPOSE_PROJECT_NAME}:authserver-${MODULE_PROFILE}-latest
AC_WORLDSERVER_IMAGE_MODULES=${DOCKERHUB_USERNAME}/${COMPOSE_PROJECT_NAME}:worldserver-${MODULE_PROFILE}-latest
```

### Using Date-Tagged Images

To pin to a specific build date, edit `.env`:

```bash
# Set your profile
MODULE_PROFILE=realmmaster

# Pin to a specific date (example: January 9, 2026)
AC_AUTHSERVER_IMAGE_MODULES=${DOCKERHUB_USERNAME}/${COMPOSE_PROJECT_NAME}:authserver-${MODULE_PROFILE}-20260109
AC_WORLDSERVER_IMAGE_MODULES=${DOCKERHUB_USERNAME}/${COMPOSE_PROJECT_NAME}:worldserver-${MODULE_PROFILE}-20260109
```

## Differences from Local Build

### What You DON'T Need

When using pre-built images, you **skip**:
- ❌ Running `./setup.sh` (module selection)
- ❌ Running `./build.sh` (compilation)
- ❌ 15-45 minute build time
- ❌ Build dependencies (Go compiler, etc.)

### What's the Same

Everything else works identically:
- ✅ Database setup and migrations
- ✅ Module SQL installation
- ✅ Configuration management
- ✅ Backup system
- ✅ All management commands
- ✅ phpMyAdmin and Keira3 tools

## Verifying Your Deployment

After deployment completes:

### 1. Check Container Status

```bash
./status.sh
```

You should see all services running:
- ✅ ac-mysql
- ✅ ac-authserver
- ✅ ac-worldserver
- ✅ ac-phpmyadmin
- ✅ ac-keira3

### 2. Verify Modules Are Loaded

Check the worldserver logs:

```bash
docker logs ac-worldserver | grep "module"
```

You should see messages about 32 modules being loaded.

### 3. Access Management Tools

- **phpMyAdmin**: http://localhost:8081
- **Keira3**: http://localhost:4201

## Post-Installation

### Create Admin Account

1. Attach to the worldserver container:

```bash
docker attach ac-worldserver
```

2. Create an account and set GM level:

```
account create admin password
account set gmlevel admin 3 -1
```

3. Detach: Press `Ctrl+P` then `Ctrl+Q`

### Configure Client

Edit your WoW 3.3.5a client's `realmlist.wtf`:

```
set realmlist 127.0.0.1
```

(Replace `127.0.0.1` with your server's IP if remote)

## Updating to Latest Images

To update to the latest nightly build:

```bash
# Pull latest images
docker compose pull

# Restart services
docker compose down
docker compose up -d
```

**Note**: Database schema updates will be applied automatically on restart.

## Switching Between Pre-Built and Local Build

### From Pre-Built to Local Build

If you want to customize modules and build locally:

```bash
# Remove pre-built .env
rm .env

# Run interactive setup
./setup.sh

# Build with your custom modules
./build.sh

# Deploy
./deploy.sh
```

### From Local Build to Pre-Built

If you want to use pre-built images instead:

```bash
# Back up your current .env
mv .env .env.custom

# Use pre-built configuration
cp .env.prebuilt .env

# Edit DOCKERHUB_USERNAME in .env

# Deploy
./deploy.sh
```

## Troubleshooting

### Image Pull Errors

**Problem**: `Error response from daemon: manifest not found`

**Solutions**:
1. Verify `DOCKERHUB_USERNAME` is set correctly in `.env`
2. Check that the images exist at: https://hub.docker.com/u/your-username
3. Ensure the CI/CD workflow has run successfully

### Module SQL Not Applied

**Problem**: Modules don't seem to be working

**Solution**: The module SQL is automatically applied during deployment. Check:

```bash
# Verify module SQL staging
ls -la storage/module-sql-updates/

# Check database for module tables
docker exec -it ac-mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW TABLES" acore_world | grep -i module
```

### Performance Issues

**Problem**: Server is slow or laggy

**Solutions**:
1. Increase MySQL tmpfs size in `.env`: `MYSQL_RUNTIME_TMPFS_SIZE=16G`
2. Reduce playerbot population: `PLAYERBOT_MAX_BOTS=100`
3. Check system resources: `docker stats`

## Advanced Configuration

### Custom Module Selection

Pre-built images include all RealmMaster modules. To disable specific modules:

1. Edit server configuration files in `storage/config/`
2. Set module enable flags to 0
3. Restart worldserver: `docker compose restart ac-worldserver`

**Note**: You can only disable modules, not add new ones (requires local build).

### Server Configuration Presets

Apply configuration presets for different server types:

```bash
# In .env, set one of these presets:
SERVER_CONFIG_PRESET=blizzlike        # Authentic WotLK experience (1x rates)
SERVER_CONFIG_PRESET=fast-leveling    # 3x XP rates, QoL improvements
SERVER_CONFIG_PRESET=hardcore-pvp     # Competitive PvP (1.5x rates)
SERVER_CONFIG_PRESET=casual-pve       # Relaxed PvE (2x rates)
```

Restart after changing: `docker compose restart ac-worldserver`

## Getting Help

- **Documentation**: See other guides in `docs/`
- **GitHub Issues**: https://github.com/uprightbass360/AzerothCore-RealmMaster/issues
- **AzerothCore Discord**: https://discord.gg/gkt4y2x

## Next Steps

- [Database Management](DATABASE_MANAGEMENT.md) - Backups, restores, migrations
- [Getting Started Guide](GETTING_STARTED.md) - Detailed walkthrough
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions
- [Module Catalog](MODULES.md) - Complete list of available modules

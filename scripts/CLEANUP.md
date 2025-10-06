# AzerothCore Cleanup Script

This script provides safe and comprehensive cleanup options for AzerothCore Docker resources with multiple levels of cleanup intensity.

## Quick Reference

```bash
cd scripts

# Safe cleanup - stop containers only
./cleanup.sh --soft

# Moderate cleanup - remove containers and networks (preserves data)
./cleanup.sh --hard

# Complete cleanup - remove everything (DESTROYS ALL DATA)
./cleanup.sh --nuclear

# See what would happen without doing it
./cleanup.sh --hard --dry-run
```

## Cleanup Levels

### 🟢 **Soft Cleanup** (`--soft`)
- **What it does**: Stops all AzerothCore containers
- **What it preserves**: Everything (data, networks, images)
- **Use case**: Temporary shutdown, reboot, or switching between deployments
- **Recovery**: Quick restart with deployment script

```bash
./cleanup.sh --soft
```

**After soft cleanup:**
- All your game data is safe
- Quick restart: `./deploy-and-check.sh --skip-deploy`

### 🟡 **Hard Cleanup** (`--hard`)
- **What it does**: Removes containers and networks
- **What it preserves**: Data volumes and Docker images
- **Use case**: Clean slate deployment while keeping your data
- **Recovery**: Full deployment (but reuses existing data)

```bash
./cleanup.sh --hard
```

**After hard cleanup:**
- Your database and game data is preserved
- Fresh deployment: `./deploy-and-check.sh`
- No need to re-download client data

### 🔴 **Nuclear Cleanup** (`--nuclear`)
- **What it does**: Removes EVERYTHING
- **What it preserves**: Nothing
- **Use case**: Complete fresh start or when troubleshooting major issues
- **Recovery**: Full deployment with fresh downloads

```bash
./cleanup.sh --nuclear
```

**⚠️ WARNING: This permanently deletes ALL AzerothCore data including:**
- Database schemas and characters
- Client data (15GB+ will need re-download)
- Configuration files
- Logs and backups
- All containers and images

## Command Options

| Option | Description |
|--------|-------------|
| `--soft` | Stop containers only (safest) |
| `--hard` | Remove containers + networks (preserves data) |
| `--nuclear` | Complete removal (DESTROYS ALL DATA) |
| `--dry-run` | Show what would be done without actually doing it |
| `--force` | Skip confirmation prompts (useful for scripts) |
| `--help` | Show help message |

## Examples

### Safe Exploration
```bash
# See what would be removed with hard cleanup
./cleanup.sh --hard --dry-run

# See what would be removed with nuclear cleanup
./cleanup.sh --nuclear --dry-run
```

### Automated Scripts
```bash
# Force cleanup without prompts (for CI/CD)
./cleanup.sh --hard --force

# Dry run for validation
./cleanup.sh --nuclear --dry-run --force
```

### Interactive Cleanup
```bash
# Standard cleanup with confirmation
./cleanup.sh --hard

# Will prompt: "Are you sure? (yes/no):"
```

## What Gets Cleaned

### Resources Identified
The script automatically identifies and shows:
- **Containers**: All `ac-*` containers (running and stopped)
- **Networks**: `azerothcore` and related networks
- **Volumes**: AzerothCore data volumes (if any named volumes exist)
- **Images**: AzerothCore server images and related tools

### Cleanup Actions by Level

| Resource Type | Soft | Hard | Nuclear |
|---------------|------|------|---------|
| Containers | Stop | Remove | Remove |
| Networks | Keep | Remove | Remove |
| Volumes | Keep | Keep | **DELETE** |
| Images | Keep | Keep | **DELETE** |
| Local Data | Keep | Keep | **DELETE** |

## Recovery After Cleanup

### After Soft Cleanup
```bash
# Quick restart (containers only)
./deploy-and-check.sh --skip-deploy

# Or restart specific layer
docker compose -f ../docker-compose-azerothcore-services.yml up -d
```

### After Hard Cleanup
```bash
# Full deployment (reuses existing data)
./deploy-and-check.sh
```

### After Nuclear Cleanup
```bash
# Complete fresh deployment
./deploy-and-check.sh

# This will:
# - Download ~15GB client data again
# - Import fresh database schemas
# - Create new containers and networks
```

## Safety Features

### Confirmation Prompts
- All destructive operations require confirmation
- Clear warnings about data loss
- Use `--force` to skip prompts for automation

### Dry Run Mode
- See exactly what would be done
- No actual changes made
- Perfect for understanding impact

### Resource Detection
- Shows current resources before cleanup
- Identifies exactly what will be affected
- Prevents unnecessary operations

## Integration with Other Scripts

### Combined Usage
```bash
# Complete refresh workflow
./cleanup.sh --hard --force
./deploy-and-check.sh

# Troubleshooting workflow
./cleanup.sh --nuclear --dry-run  # See what would be removed
./cleanup.sh --nuclear --force    # If needed
./deploy-and-check.sh              # Fresh start
```

### CI/CD Usage
```bash
# Automated cleanup in pipelines
./cleanup.sh --hard --force
./deploy-and-check.sh --skip-deploy || ./deploy-and-check.sh
```

## Troubleshooting

### Common Issues

**Cleanup hangs or fails:**
```bash
# Force remove stuck containers
docker kill $(docker ps -q --filter "name=ac-")
docker rm $(docker ps -aq --filter "name=ac-")
```

**Permission errors:**
```bash
# Some local directories might need sudo
sudo ./cleanup.sh --nuclear
```

**Resources not found:**
- This is normal if no AzerothCore deployment exists
- Script will show "No resources found" and exit safely

### Manual Cleanup
If the script fails, you can manually clean up:

```bash
# Manual container removal
docker ps -a --format '{{.Names}}' | grep '^ac-' | xargs docker rm -f

# Manual network removal
docker network rm azerothcore

# Manual volume removal (DESTROYS DATA)
docker volume ls --format '{{.Name}}' | grep 'ac_' | xargs docker volume rm

# Manual image removal
docker images --format '{{.Repository}}:{{.Tag}}' | grep '^acore/' | xargs docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep '^uprightbass360/azerothcore-wotlk-playerbots' | xargs docker rmi
```

## Exit Codes

- **0**: Cleanup completed successfully
- **1**: Error occurred or user cancelled operation

Use these exit codes in scripts to handle cleanup results appropriately.
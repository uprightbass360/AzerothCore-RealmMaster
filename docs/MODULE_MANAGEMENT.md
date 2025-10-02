# AzerothCore Module Management System

This document describes the automated module management system for AzerothCore Docker deployments.

## Overview

The module management system provides:
- ✅ Automated Git-based module installation
- ✅ Automatic database script execution (SQL imports)
- ✅ Configuration file management (.conf.dist → .conf)
- ✅ Module state tracking and rebuild detection
- ✅ Comprehensive rebuild automation
- ✅ Pre-compilation configuration analysis

## Architecture

### Components

1. **Module Manager Container** (`ac-modules`)
   - Handles module downloading, SQL execution, and state tracking
   - Runs as one-time setup during stack initialization
   - Monitors module configuration changes

2. **Rebuild Detection System**
   - Tracks module enable/disable state changes
   - Automatically detects when compilation is required
   - Provides detailed rebuild instructions

3. **Automated Rebuild Script** (`scripts/rebuild-with-modules.sh`)
   - Orchestrates full compilation workflow
   - Integrates with source-based Docker builds
   - Handles module synchronization

## Module Types

### Pre-built Compatible
**None currently available** - All 28 analyzed modules require C++ compilation.

### Compilation Required
All current modules require source-based compilation:
- mod-playerbots (🚨 CRITICAL: Requires custom AzerothCore branch)
- mod-aoe-loot (⚠️ Ready for testing)
- mod-learn-spells (⚠️ Ready for testing)
- mod-fireworks-on-level (⚠️ Ready for testing)
- mod-individual-progression (🔧 Auto-configures accounts)
- mod-ahbot (❌ KNOWN ISSUE: Linking error - disabled)
- All other modules (⚠️ Ready for testing)

See `MODULE_COMPATIBILITY.md` for detailed compatibility status.

## Configuration

### Environment Variables

Modules are controlled via environment variables in `docker-compose-azerothcore-services.env`:

```bash
# Enable/disable modules (1 = enabled, 0 = disabled)
MODULE_PLAYERBOTS=1
MODULE_AOE_LOOT=1
MODULE_LEARN_SPELLS=1
# ... etc
```

### Critical Module Requirements

#### mod-playerbots
- **INCOMPATIBLE** with standard AzerothCore
- Requires custom branch: `liyunfan1223/azerothcore-wotlk/tree/Playerbot`
- Will not function with standard compilation

#### mod-individual-progression
- Auto-configures new accounts for individual progression
- Requires account creation after server setup

## Database Integration

### Automatic SQL Execution

The system automatically executes SQL scripts for enabled modules:

```bash
# SQL execution locations searched:
/modules/mod-name/data/sql/world/*.sql    → acore_world database
/modules/mod-name/data/sql/auth/*.sql     → acore_auth database
/modules/mod-name/data/sql/characters/*.sql → acore_characters database
/modules/mod-name/data/sql/*.sql          → acore_world database (fallback)
/modules/mod-name/sql/*.sql               → acore_world database (alternative)
```

### Error Handling

- ✅ Uses proper MySQL client with SSL verification disabled
- ✅ Implements exit code checking (not stderr redirection)
- ✅ Provides detailed success/failure feedback
- ✅ Continues processing if optional scripts fail

## Rebuild System

### Detection Logic

1. **Module State Tracking**
   - Creates hash of all module enable/disable states
   - Stores in `/modules/.modules_state`
   - Compares current vs previous state on each run

2. **Change Detection**
   ```bash
   # First run
   📝 First run - establishing module state baseline

   # No changes
   ✅ No module changes detected

   # Changes detected
   🔄 Module configuration has changed - rebuild required
   ```

### Rebuild Requirements

When modules are enabled, the system provides:

```bash
🚨 REBUILD REQUIRED 🚨
Module configuration has changed. To integrate C++ modules into AzerothCore:

1. Stop current services:
   docker compose -f docker-compose-azerothcore-services.yml down

2. Build with source-based compilation:
   docker compose -f /tmp/acore-dev-test/docker-compose.yml build
   docker compose -f /tmp/acore-dev-test/docker-compose.yml up -d

3. Or use the automated rebuild script (if available):
   ./scripts/rebuild-with-modules.sh
```

### Automated Rebuild Script

The `rebuild-with-modules.sh` script provides:

1. **Pre-flight Checks**
   - Verifies source repository availability
   - Counts enabled modules
   - Confirms rebuild necessity

2. **Build Process**
   - Stops current services
   - Syncs modules to source build
   - Executes `docker compose build --no-cache`
   - Starts services with compiled modules

3. **Error Handling**
   - Build failure detection
   - Service startup verification
   - Detailed status reporting

## Usage Examples

### Enable New Module

1. Edit `docker-compose-azerothcore-services.env`:
   ```bash
   MODULE_TRANSMOG=1
   ```

2. Restart module manager:
   ```bash
   docker compose -f docker-compose-azerothcore-services.yml up ac-modules
   ```

3. Follow rebuild instructions or run:
   ```bash
   ./scripts/rebuild-with-modules.sh
   ```

### Disable Module

1. Edit environment file:
   ```bash
   MODULE_TRANSMOG=0
   ```

2. Restart and rebuild (module code will be removed from compilation)

### Bulk Module Management

Enable multiple modules simultaneously:
```bash
# Edit .env file with multiple changes
MODULE_AUTOBALANCE=1
MODULE_TRANSMOG=1
MODULE_SOLO_LFG=1

# Single rebuild handles all changes
./scripts/rebuild-with-modules.sh
```

## Troubleshooting

### Common Issues

1. **SQL Execution Failures**
   - Check MySQL container health
   - Verify database credentials
   - Review specific SQL script syntax

2. **Build Failures**
   - Ensure adequate disk space (>10GB recommended)
   - Check module compatibility
   - Review Docker build logs

3. **Module Not Loading**
   - Verify module appears in compilation output
   - Check worldserver logs for load errors
   - Confirm configuration files copied correctly

### Performance Considerations

- **Build Time**: 15-45 minutes depending on system performance
- **Storage**: Source builds require ~5-10GB additional space
- **Memory**: Compilation may require 4GB+ RAM
- **CPU**: Multi-core systems significantly faster

## Technical Implementation

### Module Installation Flow

```
1. Environment Variable Check → Module Enabled?
   ↓
2. Git Clone/Pull → Download Latest Module Source
   ↓
3. SQL Script Discovery → Find Database Scripts
   ↓
4. Database Connection → Execute Scripts with Error Handling
   ↓
5. Configuration Files → Copy .conf.dist to .conf
   ↓
6. State Tracking → Update Module State Hash
   ↓
7. Rebuild Detection → Compare Previous vs Current State
   ↓
8. User Notification → Provide Rebuild Instructions
```

### Database Script Execution

```sql
-- Example execution pattern:
mysql --skip-ssl-verify -h ac-database -P 3306 -u root -p"password" acore_world < module.sql

-- Success detection via exit codes:
if [ $? -eq 0 ]; then
    echo "✅ Successfully executed $(basename $sql_file)"
else
    echo "❌ Failed to execute $sql_file"
fi
```

## Future Enhancements

- [ ] Support for pure configuration modules (no compilation)
- [ ] Module dependency resolution
- [ ] Incremental compilation for faster rebuilds
- [ ] Integration with CI/CD pipelines
- [ ] Module version management and rollback
- [ ] Health checks for module functionality

## Support

For issues with specific modules, refer to their individual GitHub repositories.
For system-level issues, check Docker Compose logs and module manager output.
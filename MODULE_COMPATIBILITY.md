# AzerothCore Module Compatibility Guide

## Overview

This document tracks the compatibility status of AzerothCore modules with the automated module management system.

## Module Status Legend

- ✅ **COMPATIBLE**: Module compiles and links successfully
- ⚠️ **TESTING**: Module requires testing for compatibility
- ❌ **INCOMPATIBLE**: Module has known compilation or linking issues
- 🔧 **REQUIRES_CONFIG**: Module needs configuration before compilation
- 🚨 **CRITICAL**: Module has special requirements or limitations

## Module Compatibility Matrix

### Core Modules (High Priority)

| Module | Status | Notes |
|--------|--------|-------|
| mod-aoe-loot | ⚠️ | Ready for testing |
| mod-learn-spells | ⚠️ | Ready for testing |
| mod-autobalance | ⚠️ | Ready for testing |
| mod-solo-lfg | ⚠️ | Ready for testing |
| mod-transmog | ⚠️ | Ready for testing |

### Quality of Life Modules

| Module | Status | Notes |
|--------|--------|-------|
| mod-ahbot | ❌ | **LINKING ERROR**: `undefined reference to 'Addmod_ahbotScripts()'` |
| mod-npc-buffer | ⚠️ | Ready for testing |
| mod-dynamic-xp | ⚠️ | Ready for testing |
| mod-breaking-news-override | ⚠️ | Ready for testing |

### Advanced Modules

| Module | Status | Notes |
|--------|--------|-------|
| mod-playerbots | 🚨 | **CRITICAL**: Requires custom AzerothCore branch (liyunfan1223/azerothcore-wotlk/tree/Playerbot) |
| mod-individual-progression | 🔧 | Auto-configures accounts for individual progression |
| mod-1v1-arena | ⚠️ | Ready for testing |
| mod-phased-duels | ⚠️ | Ready for testing |

### Server Management Modules

| Module | Status | Notes |
|--------|--------|-------|
| mod-boss-announcer | ⚠️ | Ready for testing |
| mod-account-achievements | ⚠️ | Ready for testing |
| mod-eluna | ⚠️ | Lua scripting engine integration |

### Additional Modules

| Module | Status | Notes |
|--------|--------|-------|
| mod-auto-revive | ⚠️ | Ready for testing |
| mod-gain-honor-guard | ⚠️ | Ready for testing |
| mod-time-is-time | ⚠️ | Ready for testing |
| mod-pocket-portal | ⚠️ | Ready for testing |
| mod-random-enchants | ⚠️ | Ready for testing |
| mod-solocraft | ⚠️ | Ready for testing |
| mod-pvp-titles | ⚠️ | Ready for testing |
| mod-npc-beastmaster | ⚠️ | Ready for testing |
| mod-npc-enchanter | ⚠️ | Ready for testing |
| mod-instance-reset | ⚠️ | Ready for testing |
| mod-quest-count-level | ⚠️ | Ready for testing |

## Known Issues

### mod-ahbot (AuctionHouse Bot)
- **Error**: `undefined reference to 'Addmod_ahbotScripts()'`
- **Cause**: Module script loader function not properly exported
- **Solution**:
  1. Check module version compatibility with AzerothCore
  2. Update to latest module version
  3. Report issue to module maintainer
- **Workaround**: Disable module until fixed

### mod-playerbots (Player Bots)
- **Issue**: Requires custom AzerothCore branch
- **Requirement**: `liyunfan1223/azerothcore-wotlk/tree/Playerbot`
- **Impact**: Incompatible with standard AzerothCore builds
- **Solution**: Use separate deployment for playerbot functionality

## Testing Procedure

### Safe Module Testing

1. **Enable Single Module**:
   ```bash
   # Edit docker-compose-azerothcore-services.env
   MODULE_AOE_LOOT=1  # Enable one module
   ```

2. **Test Compilation**:
   ```bash
   ./rebuild-with-modules.sh
   ```

3. **Monitor Build**:
   - Watch for compilation errors
   - Check for linking issues
   - Verify successful completion

4. **Test Functionality**:
   - Start services
   - Test module features in-game
   - Check server logs for errors

### Batch Testing (Advanced)

1. **Enable Compatible Group**:
   ```bash
   # Enable related modules together
   MODULE_AOE_LOOT=1
   MODULE_LEARN_SPELLS=1
   MODULE_AUTOBALANCE=1
   ```

2. **Document Results**:
   - Update compatibility matrix
   - Note any conflicts between modules
   - Report issues to module maintainers

## Module Management Best Practices

### 1. Incremental Testing
- Enable modules one at a time initially
- Test core functionality before enabling more
- Document compatibility results

### 2. Environment Management
- Keep baseline with all modules disabled
- Create separate environments for testing
- Use git branches for different module configurations

### 3. Compatibility Tracking
- Update this document with test results
- Track module versions that work together
- Note AzerothCore version compatibility

### 4. Performance Considerations
- Monitor server performance with modules enabled
- Test with realistic player loads
- Consider module interaction effects

## Contributing

### Reporting Issues
1. Document exact error messages
2. Include module versions and AzerothCore version
3. Provide reproduction steps
4. Submit to module maintainer and this repository

### Updating Compatibility
1. Test modules thoroughly
2. Update status in compatibility matrix
3. Document any special requirements
4. Submit pull request with findings

## Quick Reference

### Enable a Module
```bash
# 1. Edit environment file
MODULE_NAME=1

# 2. Rebuild if needed
./rebuild-with-modules.sh

# 3. Restart services
docker compose -f docker-compose-azerothcore-services.yml restart
```

### Disable All Modules (Safe State)
```bash
# All modules are currently disabled in the environment file
# This provides a stable baseline for testing
```

### Check Module Status
```bash
# View current module configuration
grep "^MODULE_" docker-compose-azerothcore-services.env
```
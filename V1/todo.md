# AzerothCore Module System Validation TODO

## Overview
Document findings from module system validation and plan for end-to-end testing to ensure proper deployment in both standard and playerbot configurations.

## Key Findings

### Container Architecture
- **Single worldserver container**: `ac-worldserver`
- **Base container selection**: Determined by `MODULE_PLAYERBOTS` flag
  - `MODULE_PLAYERBOTS=1` → `uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot`
  - `MODULE_PLAYERBOTS=0` → `acore/ac-wotlk-worldserver:14.0.0-dev`
- **Additional modules**: Compiled on top of selected base container via source compilation

### Current Module Configuration
**Enabled Modules (modules-custom.env):**
1. `MODULE_PLAYERBOTS=1` (base container selection)
2. `MODULE_AOE_LOOT=1` (requires C++ compilation)
3. `MODULE_LEARN_SPELLS=1` (requires C++ compilation)
4. `MODULE_FIREWORKS=1` (requires C++ compilation)
5. `MODULE_AHBOT=1` (requires C++ compilation)
6. `MODULE_AUTOBALANCE=1` (requires C++ compilation)
7. `MODULE_TRANSMOG=1` (requires C++ compilation)
8. `MODULE_NPC_BUFFER=1` (requires C++ compilation)
9. `MODULE_SOLO_LFG=1` (requires C++ compilation)
10. `MODULE_SOLOCRAFT=1` (requires C++ compilation)

### Rebuild Requirements
**Only ac-worldserver requires rebuild:**
- All C++ modules affect worldserver binary only
- ac-authserver remains compatible (playerbot images already include auth changes)
- No other containers need recompilation

### Module Installation Components
1. **Module Manager**: `ac-modules` container (downloads/installs modules)
2. **Build Service**: `ac-build` container (handles C++ compilation when needed)
3. **State Tracking**: `/modules/.modules_state` file prevents unnecessary rebuilds
4. **Automated Scripts**:
   - `scripts/manage-modules.sh` - Module installation and configuration
   - `scripts/rebuild-with-modules.sh` - Automated rebuild process
   - `scripts/deploy-and-check.sh` - Full stack deployment with validation

## Configuration Issues Identified
1. **Conflicting Configurations**:
   - `services-custom.env`: Only `MODULE_PLAYERBOTS=1`
   - `modules-custom.env`: 10 modules enabled
   - **Resolution needed**: Align configurations

## Testing Plan: Two End-to-End Validation Tests

### Test 1: Standard AzerothCore with Additional Modules
**Objective**: Validate deployment without Playerbots but with other C++ modules
**Configuration**:
```bash
# Base container
MODULE_PLAYERBOTS=0
AC_WORLDSERVER_IMAGE=acore/ac-wotlk-worldserver:14.0.0-dev

# Additional modules (subset for testing)
MODULE_AOE_LOOT=1
MODULE_AUTOBALANCE=1
MODULE_TRANSMOG=1
```

**Expected Results**:
- Uses standard AzerothCore base
- Compiles 3 additional modules into worldserver
- No Playerbot functionality
- Validates source compilation process

**Test Steps**:
1. Configure environment files for standard deployment
2. Run `scripts/deploy-and-check.sh`
3. Monitor `ac-modules` container output
4. Verify rebuild detection triggers
5. Execute `scripts/rebuild-with-modules.sh`
6. Validate all services are healthy
7. Test module functionality (AOE loot, autobalance, transmog)

### Test 2: Playerbot AzerothCore with Additional Modules
**Objective**: Validate deployment with Playerbots + additional C++ modules
**Configuration**:
```bash
# Base container (current configuration)
MODULE_PLAYERBOTS=1
AC_WORLDSERVER_IMAGE=uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot

# All additional modules
MODULE_AOE_LOOT=1
MODULE_LEARN_SPELLS=1
MODULE_FIREWORKS=1
MODULE_AHBOT=1
MODULE_AUTOBALANCE=1
MODULE_TRANSMOG=1
MODULE_NPC_BUFFER=1
MODULE_SOLO_LFG=1
MODULE_SOLOCRAFT=1
```

**Expected Results**:
- Uses Playerbot base container
- Compiles 9 additional modules into worldserver
- Full Playerbot functionality maintained
- All additional modules functional

**Test Steps**:
1. Use current modules-custom.env configuration
2. Run full deployment with `scripts/deploy-and-check.sh`
3. Monitor module installation and rebuild process
4. Validate Playerbot functionality
5. Test each additional module's functionality
6. Verify no conflicts between Playerbots and other modules

## Validation Criteria

### Deployment Success Criteria
- [ ] All containers start and pass health checks
- [ ] Database schemas properly created/updated
- [ ] Module configuration files properly installed
- [ ] No container restart loops
- [ ] Port connectivity tests pass

### Module Functionality Criteria
- [ ] Playerbot commands work (if enabled)
- [ ] AOE looting functions
- [ ] Auto-spell learning on level up
- [ ] Fireworks display on level up
- [ ] Auction house bot operational
- [ ] Dungeon difficulty auto-balances
- [ ] Transmog system accessible
- [ ] NPC buffer provides services
- [ ] Solo LFG allows queue
- [ ] Solocraft scaling active

### Performance Criteria
- [ ] Server startup time < 5 minutes
- [ ] Module rebuild time < 45 minutes
- [ ] No memory leaks or excessive resource usage
- [ ] Stable operation under load

## Risk Mitigation
1. **Backup current working state** before testing
2. **Test in isolated environment** first
3. **Document rollback procedures** for each test
4. **Monitor logs continuously** during testing
5. **Have restore scripts ready** in case of failures

## Next Steps
1. Create isolated test environments for both scenarios
2. Prepare configuration files for Test 1 (standard + modules)
3. Execute Test 1 and document results
4. Execute Test 2 and document results
5. Compare performance and stability between configurations
6. Document final recommendations for production deployment

## Notes
- Each test should be run multiple times to ensure consistency
- Log all outputs for analysis
- Measure build times and resource usage
- Test both fresh deployments and configuration changes
- Validate that module state tracking prevents unnecessary rebuilds

---

## Previous Deployment History (ARCHIVED)

### ✅ **Major Fixes Completed:**
1. **Database Schema Issues** ✅ **RESOLVED**
   - Added missing `emotetextsound_dbc.sql` to source project
   - Imported all DBC tables - worldserver now starts successfully
   - Worldserver status: `Up (healthy)` with Eluna scripts loaded

2. **Container Script Compatibility** ✅ **RESOLVED**
   - Fixed client-data container with multi-OS package manager detection
   - Client data downloads working (15GB extracted successfully)
   - Updated docker-compose with Alpine/Ubuntu compatibility

**Status**: **MAJOR SUCCESS** ✅ - Core server functional, ready for module validation testing.
# AzerothCore Module Configuration Requirements

This document outlines all manual configuration steps required for the enabled modules that cannot be automated through Docker container processes.

## 🚨 Critical Compatibility Issues

### MODULE_PLAYERBOTS - INCOMPATIBLE WITH STANDARD AZEROTHCORE

**❌ BREAKING ISSUE**: mod-playerbots requires a completely different AzerothCore branch:
- **Required Branch**: `liyunfan1223/azerothcore-wotlk/tree/Playerbot`
- **Current Setup**: Standard AzerothCore (INCOMPATIBLE)

**Resolution Options**:
1. **Switch to Playerbot Branch** (Recommended for bot-focused servers)
   - Fork the Playerbot branch
   - Rebuild entire server stack with Playerbot core
   - Note: May be incompatible with some other modules

2. **Disable Playerbots** (Recommended for standard servers)
   - Set `MODULE_PLAYERBOTS=0` in environment file
   - Continue with standard AzerothCore

---

## 📦 Client-Side Patch Requirements

### MODULE_INDIVIDUAL_PROGRESSION

**Required Client Patches** (stored in: `${STORAGE_PATH}/modules/mod-individual-progression/optional/`):

| Patch File | Description | Required |
|------------|-------------|----------|
| `patch-V.mpq` | Vanilla crafting and recipe restoration | ✅ Yes |
| `patch-J.mpq` | Vanilla login screen | ❌ Optional |
| `patch-U.mpq` | Vanilla loading screens | ❌ Optional |
| `patch-S.mpq` | Alternative WotLK mana costs | ❌ Don't use with patch-V |

**Installation**: Players must copy required patches to their `WoW/Data/` directory.

### MODULE_ARAC (All Races All Classes)

**Required Client Patch**:
- **File**: `Patch-A.MPQ`
- **Location**: `${STORAGE_PATH}/modules/mod-arac/patch-contents/`
- **Installation**: Players must copy to `WoW/Data/` directory

**Server-Side**: DBC files are automatically applied during module installation.

---

## ⚙️ Critical Server Configuration Changes

### MODULE_INDIVIDUAL_PROGRESSION

**Required worldserver.conf Changes**:
```ini
# CRITICAL - Required for progress saving
EnablePlayerSettings = 1

# CRITICAL - Required for item stat overrides
DBC.EnforceItemAttributes = 0
```

**File Location**: `${STORAGE_PATH}/config/worldserver.conf`

### MODULE_AOE_LOOT

**Required worldserver.conf Optimization**:
```ini
# Prevent corpse cleanup issues with AoE looting
# Default: 0.5, Required: 0.01 or lower
Rate.Corpse.Decay.Looted = 0.01
```

---

## 🤖 Manual NPC Spawning Requirements

The following modules require manual NPC spawning using GM commands:

### MODULE_TRANSMOG
```
.npc add 190010
```
**Recommended Locations**: Major cities (Stormwind, Orgrimmar, Ironforge, Undercity)

### MODULE_NPC_ENCHANTER
```
.npc add [enchanter_npc_id]
```
**Note**: Check module documentation for specific NPC ID

### MODULE_REAGENT_BANK
```
.npc add 290011
```
**Recommended Locations**: Major cities near banks

### MODULE_ASSISTANT
```
.npc add [assistant_npc_id]
```
**Note**: Check module documentation for specific NPC ID

**Requirements**:
- GM account with level 3+ permissions
- Access to worldserver console or in-game GM commands

---

## 💾 Database Backup Requirements

**CRITICAL**: The following modules modify core database tables and require backup:

- **MODULE_ARAC**: Modifies race/class restrictions
- **MODULE_INDIVIDUAL_PROGRESSION**: Adds progression tracking tables

**Backup Command**:
```bash
docker exec ac-mysql mysqldump -u root -p${MYSQL_ROOT_PASSWORD} --all-databases > backup-$(date +%Y%m%d-%H%M%S).sql
```

---

## 🖥️ Eluna Lua Scripting Setup

### MODULE_ELUNA - Complete Setup

**Automated Setup Available**:
```bash
./scripts/setup-eluna.sh
```

**Manual Configuration Requirements**:
- **Script Directory**: `${STORAGE_PATH}/lua_scripts/` (volume mounted automatically)
- **English DBC Files**: Recommended for full functionality
- **Container Integration**: Scripts loaded automatically on worldserver start

**Example Scripts Provided**:
- `welcome.lua` - Player login welcome messages
- `server_info.lua` - Custom `.info` and `.serverinfo` commands
- `level_rewards.lua` - Milestone rewards for leveling
- `init.lua` - Script documentation and loader

**Key Configuration** (`mod_LuaEngine.conf`):
```ini
Eluna.ScriptPath = "lua_scripts"
Eluna.AutoReload = false  # Enable only for development
Eluna.BytecodeCache = true  # Performance optimization
Eluna.TraceBack = false  # Enable for debugging
```

**Important Compatibility Notes**:
- ⚠️ **AzerothCore mod-eluna is NOT compatible with standard Eluna scripts**
- Scripts must be written specifically for AzerothCore's mod-eluna API
- Standard Eluna community scripts will NOT work

**Script Management Commands**:
- `.reload eluna` - Reload all Lua scripts
- `.lua [code]` - Execute Lua code directly (if enabled)

---

## 🔧 Module-Specific Configuration Files

### MODULE_PLAYERBOTS - playerbots.conf
**Key Settings**:
- `MinRandomBots = 500` (Default - reduce for performance)
- `MaxRandomBots = 500` (Default - reduce for performance)
- RandomBot account management settings

### MODULE_AOE_LOOT - mod_aoe_loot.conf
**Key Settings**:
- Loot range configuration (default: 55.0)
- Group behavior settings

### MODULE_LEARN_SPELLS - mod_learnspells.conf
**Key Settings**:
- Maximum level limits
- First login behavior

### MODULE_INDIVIDUAL_PROGRESSION - individual_progression.conf
**Key Settings**:
- Era progression rules
- Content unlock thresholds

### MODULE_TRANSMOG - transmog.conf
**Key Settings**:
- Transmogrification rules
- Cost settings
- Restriction configurations

---

## 🎯 Performance Considerations

### MODULE_PLAYERBOTS
- **Impact**: High - Can run thousands of AI bots
- **Recommendation**: Start with low bot counts (50-100)
- **Monitoring**: CPU usage, memory consumption, database load

### MODULE_ELUNA
- **Impact**: Variable - Depends on Lua script complexity
- **Requirement**: English DBC files for full functionality
- **Script Location**: `${STORAGE_PATH}/lua_scripts/` (automatically mounted)
- **Setup**: Run `./scripts/setup-eluna.sh` to create example scripts
- **Monitoring**: Script execution times
- **Reloading**: Use `.reload eluna` command in worldserver console

---

## 📋 Deployment Checklist

### Pre-Deployment
- [ ] **Critical**: Resolve Playerbots compatibility (switch branch OR disable)
- [ ] Backup database (if using ARAC or INDIVIDUAL_PROGRESSION)
- [ ] Update worldserver.conf with required settings
- [ ] Test configuration in development environment

### During Deployment
- [ ] Rebuild containers: `./scripts/rebuild-with-modules.sh`
- [ ] Verify module compilation success
- [ ] Apply any remaining SQL scripts manually
- [ ] Create GM account for NPC spawning

### Post-Deployment
- [ ] Spawn required NPCs using GM commands
- [ ] Test each module's functionality
- [ ] Distribute client patches to players
- [ ] Monitor server performance
- [ ] Adjust module configurations as needed

---

## 🚨 Known Compatibility Issues

### AzerothCore Version Dependencies
- **MODULE_TRANSMOG**: Requires minimum commit `b6cb9247ba96a862ee274c0765004e6d2e66e9e4`
- **MODULE_PLAYERBOTS**: Requires custom Playerbot branch (incompatible with standard)

### Module Conflicts
- **INDIVIDUAL_PROGRESSION + Standard AzerothCore**: patch-S.mpq conflicts with patch-V.mpq
- **ELUNA Scripts**: AzerothCore mod-eluna is NOT compatible with standard Eluna scripts

### Database Conflicts
- **MODULE_TRANSMOG**: Must delete conflicting npc_text IDs (50000, 50001) if upgrading

---

## 📞 Support and Resources

### Module Documentation
Each module's GitHub repository contains detailed configuration documentation:
- Configuration file examples (`.conf.dist` files)
- SQL requirements
- Client-side patch information

### Testing Recommendations
1. **Development Environment**: Test all modules in non-production environment first
2. **Staged Rollout**: Enable modules incrementally to identify issues
3. **Player Communication**: Provide clear client patch installation instructions
4. **Rollback Plan**: Maintain database backups for quick rollback if needed

---

## 🔄 Configuration Update Script

Run the module configuration analysis script to check your current setup:

```bash
./scripts/configure-modules.sh
```

This script will:
- Analyze your enabled modules
- Identify missing configuration requirements
- Provide step-by-step resolution guidance
- Check for compatibility issues

---

*Last Updated: $(date)*
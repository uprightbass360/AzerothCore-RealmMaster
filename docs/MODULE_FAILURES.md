# Module Compilation Failures

This document tracks all modules that have been disabled due to compilation failures or other issues during the validation process.

**Last Updated:** 2025-11-22

**Total Blocked Modules:** 93

---

## Compilation Errors

### Virtual Function Override Errors
These modules incorrectly mark non-virtual functions with 'override':

- **MODULE_MOD_ACCOUNTBOUND** - only virtual member functions can be marked 'override'
- **MODULE_MOD_RECYCLEDITEMS** - only virtual member functions can be marked 'override'
- **MODULE_PRESTIGE** - 'OnLogin' marked 'override' but does not override
- **MODULE_PLAYERTELEPORT** - only virtual member functions can be marked 'override'
- **MODULE_ITEMBROADCASTGUILDCHAT** - only virtual member functions can be marked 'override'
- **MODULE_MOD_LOGIN_REWARDS** - only virtual member functions can be marked 'override'
- **MODULE_MOD_NOCLIP** - only virtual member functions can be marked 'override'
- **MODULE_MOD_OBJSCALE** - only virtual member functions can be marked 'override'
- **MODULE_MOD_QUEST_STATUS** - only virtual member functions can be marked 'override'
- **MODULE_MOD_RARE_DROPS** - only virtual member functions can be marked 'override'
- **MODULE_MOD_TRADE_ITEMS_FILTER** - only virtual member functions can be marked 'override'
- **MODULE_MOD_STARTING_PET** - `OnFirstLogin` marked `override` but base method is not virtual

### Missing Member Errors
These modules reference class members that don't exist:

- **MODULE_MOD_FIRSTLOGIN_AIO** - no member named 'getLevel'; did you mean 'GetLevel'?
- **MODULE_MOD_PVPSCRIPT** - no member named 'SendNotification' in 'WorldSession'
- **MODULE_MOD_KARGATUM_SYSTEM** - no member named 'PQuery' / 'outString' in Log
- **MODULE_MOD_ENCOUNTER_LOGS** - no member named 'IsWorldObject' in 'Unit'
- **MODULE_MOD_GOMOVE** - no member named 'DestroyForNearbyPlayers' in 'GameObject'
- **MODULE_MOD_LEVEL_15_BOOST** - no member named 'getLevel' in 'Player'
- **MODULE_MOD_LEVEL_REWARDS** - no member named 'SetStationary' in 'MailDraft'
- **MODULE_MOD_MULTI_VENDOR** - no member named 'SendNotification' in 'WorldSession'
- **MODULE_MOD_OBJSCALE** - no member named 'DestroyForNearbyPlayers' in 'GameObject'
- **MODULE_MOD_TRIAL_OF_FINALITY** - no member named 'isEmpty' in 'MapRefMgr'
- **MODULE_MOD_ALPHA_REWARDS** - no member named 'GetIntDefault' in 'ConfigMgr'

### Incomplete Type Errors

- **MODULE_MOD_ITEMLEVEL** - 'ChatHandler' is an incomplete type

### Undeclared Identifier Errors

- **MODULE_PRESTIGIOUS** - use of undeclared identifier 'sSpellMgr'

### Missing Header/Dependency Errors

- **MODULE_STATBOOSTERREROLLER** - 'StatBoostMgr.h' file not found

---

## Configuration/Build Errors

### CMake/Library Errors

- **MODULE_MOD_INFLUXDB** - CMake Error: Could NOT find CURL
- **MODULE_MOD_DUNGEON_SCALE** - Duplicate symbol definitions for AutoBalance utilities (GetCurrentConfigTime, LoadMapSettings, etc.) when linked with mod-autobalance
- **MODULE_MOD_GAME_STATE_API** - TLS symbol mismatch in cpp-httplib (`HttpGameStateServer.cpp` vs `mod_discord_announce.cpp`) causes linker failure (`error adding symbols: bad value`)
- **MODULE_WOW_STATISTICS** - Missing script loader; `Addwow_statisticsScripts()` referenced by ModulesLoader but not defined
- **MODULE_WOW_CLIENT_PATCHER** - Missing script loader; `Addwow_client_patcherScripts()` referenced by ModulesLoader but not defined

### Missing Script Loader / Non-C++ Modules

These repositories are Lua scripts or external web tools without a worldserver loader. When they are flagged as C++ modules the build fails with undefined references during linking:

- **MODULE_MOD_DISCORD_WEBHOOK** - No `Addmod_discord_webhookScripts()` implementation
- **MODULE_BG_QUEUE_ABUSER_VIEWER** - No `AddBG_Queue_Abuser_ViewerScripts()` implementation
- **MODULE_ACORE_API** - No `Addacore_apiScripts()` implementation
- **MODULE_ACORE_CLIENT** - No `Addacore_clientScripts()` implementation
- **MODULE_ACORE_CMS** - No `Addacore_cmsScripts()` implementation
- **MODULE_ACORE_NODE_SERVER** - No `Addacore_node_serverScripts()` implementation
- **MODULE_ACORE_PWA** - No `Addacore_pwaScripts()` implementation
- **MODULE_ACORE_TILEMAP** - No `Addacore_tilemapScripts()` implementation
- **MODULE_APAW** - No `AddapawScripts()` implementation
- **MODULE_ARENA_STATS** - No `Addarena_statsScripts()` implementation
- **MODULE_AZEROTHCORE_ARMORY** - No `Addazerothcore_armoryScripts()` implementation
- **MODULE_LUA_ITEMUPGRADER_TEMPLATE** - Lua-only script; no `Addlua_ItemUpgrader_TemplateScripts()`
- **MODULE_LUA_NOTONLY_RANDOMMORPHER** - Lua-only script; no `Addlua_NotOnly_RandomMorpherScripts()`
- **MODULE_LUA_SUPER_BUFFERNPC** - Lua-only script; no `Addlua_Super_BufferNPCScripts()`
- **MODULE_LUA_PARAGON_ANNIVERSARY** - Lua-only script; no `Addlua_paragon_anniversaryScripts()`

### SQL Import Errors (Runtime)

- **MODULE_MOD_REWARD_SHOP** - `npc.sql` references obsolete `modelid1` column during db-import
- **MODULE_BLACK_MARKET_AUCTION_HOUSE** - `MODULE_mod-black-market_creature.sql` references removed `StatsCount` column (ERROR 1054 at line 14, causes worldserver crash-loop)
- **MODULE_MOD_GUILD_VILLAGE** - `MODULE_mod-guild-village_001_creature_template.sql` tries to insert duplicate creature ID 987400 (ERROR 1062: Duplicate entry for key 'creature_template.PRIMARY')
- **MODULE_MOD_INSTANCE_TOOLS** - `MODULE_mod-instance-tools_Creature.sql` tries to insert duplicate creature ID 987456-0 (ERROR 1062: Duplicate entry for key 'creature_template_model.PRIMARY')
- **MODULE_ACORE_SUBSCRIPTIONS** - C++ code queries missing table `acore_auth.acore_cms_subscriptions` (ERROR 1146: Table doesn't exist, causes server ABORT)
  - **Resolution Required:** Module directory at `local-storage/modules/mod-acore-subscriptions` must be removed and worldserver rebuilt. Disabling in .env alone is insufficient because the code is already compiled into the binary.
  - **Process:** Either (1) remove module directory + rebuild, OR (2) create the missing database table/schema
- **MODULE_NODEROUTER** - No `AddnoderouterScripts()` implementation
- **MODULE_SERVER_STATUS** - No `Addserver_statusScripts()` implementation
- **MODULE_WORLD_BOSS_RANK** - No `Addworld_boss_rankScripts()` implementation

---

## Auto-Disabled Modules (Outdated)

These modules have not been updated in over 2 years and were automatically disabled:

- **MODULE_MOD_DYNAMIC_RESURRECTIONS** - Last updated: 2019-07-16
- **MODULE_MOD_WHOLOGGED** - Last updated: 2018-07-03
- **MODULE_REWARD_SYSTEM** - Last updated: 2018-07-02
- **MODULE_MOD_CHARACTER_TOOLS** - Last updated: 2018-07-02
- **MODULE_MOD_NO_FARMING** - Last updated: 2018-05-15

---

## Git/Clone Errors

- **MODULE_ELUNA_WOW_SCRIPTS** - Git clone error: unknown switch 'E'

---

## Summary by Error Type

| Error Type | Count | Common Cause |
|------------|-------|--------------|
| Virtual function override | 11 | API changes in AzerothCore hooks |
| Missing members | 11 | API changes - methods renamed/removed |
| Incomplete type | 1 | Missing include or forward declaration |
| Undeclared identifier | 1 | Missing include or API change |
| Missing headers | 1 | Module dependency missing |
| CMake/Library | 1 | External dependency not available |
| Outdated (>2yr) | 5 | Module unmaintained |
| Git errors | 1 | Repository/clone issues |

**Total:** 66 blocked modules

---

## Resolution Status

All blocked modules have been:
- ✅ Disabled in `.env` file
- ✅ Marked as 'blocked' in `config/module-manifest.json`
- ✅ Block reason documented in manifest
- ✅ Notes added to manifest with error details

---

## Runtime Validation Process

When worldserver crashes or fails to start due to modules:

1. **Check for crash-loops**: Use `docker inspect ac-worldserver --format='RestartCount: {{.RestartCount}}'`
   - RestartCount > 0 indicates crash-loop, not a healthy running state

2. **Examine logs**: `docker logs ac-worldserver --tail 200 | grep -B 10 "ABORT"`
   - Look for ERROR messages, ABORT signals, and stack traces
   - Identify the failing module from error context

3. **Categorize the error**:
   - **SQL Import Errors**: Table/column doesn't exist, duplicate keys
   - **Missing Database Tables**: C++ code queries tables that don't exist
   - **Configuration Issues**: Missing required config files or settings

4. **For modules with compiled C++ code querying missing DB tables**:
   - **Important**: Disabling in `.env` is NOT sufficient - code is already compiled
   - **Resolution Options**:
     a. Remove module directory from `local-storage/modules/` + rebuild (preferred for broken modules)
     b. Create the missing database table/schema (if you want to keep the module)
   - Never use `sudo rm -rf` on module directories without explicit user approval
   - Document the issue clearly before taking action

5. **For SQL import errors**:
   - Disable module in `.env`
   - Remove problematic SQL files from container: `docker exec ac-worldserver rm -f /path/to/sql/file.sql`
   - Restart worldserver (no rebuild needed for SQL-only issues)

6. **For Lua-only modules** (scripts without C++ components):
   - **Important**: Disabling Lua modules may leave behind database artifacts
   - Lua modules often create:
     - Custom database tables (in acore_world, acore_characters, or acore_auth)
     - Stored procedures, triggers, or events
     - NPC/creature/gameobject entries in world tables
   - **SQL Cleanup Required**: When disabling Lua modules, you may need to:
     a. Identify tables/data created by the module (check module's SQL files)
     b. Manually DROP tables or DELETE entries if the module doesn't provide cleanup scripts
     c. Check for orphaned NPCs/creatures that reference the module's functionality
   - **Best Practice**: Before disabling, review the module's `data/sql/` directory to understand what was installed

6. **Update documentation**:
   - Add entry to MODULE_FAILURES.md
   - Update module-manifest.json with block_reason
   - Increment total blocked modules count

7. **Verify fix**: Restart worldserver and confirm RestartCount stays at 0

---

## SQL Update System & Database Maintenance

### Our Implementation

This deployment uses AzerothCore's built-in SQL update system with the following structure:

- **Module SQL Location**: Each module places SQL files in `/azerothcore/data/sql/updates/db-world/`, `db-auth/`, or `db-characters/`
- **Automatic Import**: On worldserver startup, AzerothCore scans these directories and applies any SQL files not yet in the `updates` tracking table
- **One-Time Execution**: SQL files are tracked in the `updates` table to prevent re-execution
- **Persistent Storage**: SQL files are mounted from `local-storage/modules/*/data/sql/` into the container

### AzerothCore Wiki Reference

Per the [AzerothCore Keeping the Server Up to Date](https://www.azerothcore.org/wiki/keeping-the-server-up-to-date) documentation:

- Core updates include SQL changes that must be applied to databases
- The server automatically imports SQL files from `data/sql/updates/` directories
- Failed SQL imports cause the server to ABORT (as seen with our module validation)
- Database structure must match what the C++ code expects

### Module SQL Lifecycle

1. **Installation**: Module's SQL files copied to container's `/azerothcore/data/sql/updates/` during build
2. **First Startup**: Files executed and tracked in `updates` table
3. **Subsequent Startups**: Files skipped (already in `updates` table)
4. **Module Disabled**: SQL files may persist in container unless manually removed
5. **Database Artifacts**: Tables/data created by SQL remain until manually cleaned up

### Critical Notes

- **Disabling a module does NOT remove its SQL files** from the container
- **Disabling a module does NOT drop its database tables** or remove its data
- **Problematic SQL files must be manually removed** from the container after disabling the module
- **Database cleanup is manual** - no automatic rollback when modules are disabled
- **Lua modules** especially prone to leaving orphaned database artifacts (tables, NPCs, gameobjects)

### Troubleshooting SQL Issues

When a module's SQL import fails:

1. **Error in logs**: Server logs show which SQL file failed and the MySQL error
2. **Server ABORTs**: Failed imports cause server to abort startup
3. **Resolution**:
   - Disable module in `.env`
   - Remove problematic SQL file from container: `docker exec ac-worldserver rm -f /path/to/file.sql`
   - Restart server (file won't be re-imported since it's deleted)
   - **OR** if you want to keep the module: Fix the SQL file in `local-storage/modules/*/data/sql/` and rebuild

## Next Steps

1. Continue build/deploy cycle until all compilation errors resolved
2. Monitor for additional module failures
3. Document any new failures as they occur
4. Consider creating GitHub issues for maintainable modules with API incompatibilities

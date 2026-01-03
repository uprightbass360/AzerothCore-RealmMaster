# Post-Install Hooks System

This directory contains post-install hooks for module management. Hooks are executable scripts that perform specific setup tasks after module installation.

## Architecture

### Hook Types
1. **Generic Hooks** - Reusable scripts for common patterns
2. **Module-Specific Hooks** - Custom scripts for unique requirements

### Hook Interface
All hooks receive these environment variables:
- `MODULE_KEY` - Module key (e.g., MODULE_ELUNA_SCRIPTS)
- `MODULE_DIR` - Module directory path (e.g., /modules/eluna-scripts)
- `MODULE_NAME` - Module name (e.g., eluna-scripts)
- `MODULES_ROOT` - Base modules directory (/modules)
- `LUA_SCRIPTS_TARGET` - Target lua_scripts directory (/azerothcore/lua_scripts)

### Return Codes
- `0` - Success
- `1` - Warning (logged but not fatal)
- `2` - Error (logged and fatal)

## Generic Hooks

### `copy-standard-lua`
Copies Lua scripts from standard locations to runtime directory.
Searches for:
- `lua_scripts/*.lua`
- `*.lua` (root level)
- `scripts/*.lua`
- `Server Files/lua_scripts/*.lua` (Black Market pattern)

### `copy-aio-lua`
Copies AIO-specific Lua scripts for client-server communication.
Handles both client and server scripts.

### `apply-compatibility-patch`
Applies source code patches for compatibility fixes.
Reads patch definitions from module metadata.

## Module-Specific Hooks

Module-specific hooks are named after their primary module and handle unique setup requirements.

### `mod-ale-patches`
Applies compatibility patches for mod-ale (ALE - AzerothCore Lua Engine, formerly Eluna) when building with the AzerothCore playerbots fork.

**Auto-Detection:**
The hook automatically detects if you're building with the playerbots fork by checking:
1. `STACK_SOURCE_VARIANT=playerbots` environment variable
2. `MODULES_REBUILD_SOURCE_PATH` contains "azerothcore-playerbots"

**Patches Applied:**

#### SendTrainerList Compatibility Fix
**When Applied:** Automatically for playerbots fork (or when `APPLY_SENDTRAINERLIST_PATCH=1`)
**What it fixes:** Adds missing `GetGUID()` call to fix trainer list display
**File:** `src/LuaEngine/methods/PlayerMethods.h`
**Change:**
```cpp
// Before (broken)
player->GetSession()->SendTrainerList(obj);

// After (fixed)
player->GetSession()->SendTrainerList(obj->GetGUID());
```

#### MovePath Compatibility Fix
**When Applied:** Only when explicitly enabled with `APPLY_MOVEPATH_PATCH=1` (disabled by default)
**What it fixes:** Updates deprecated waypoint movement API
**File:** `src/LuaEngine/methods/CreatureMethods.h`
**Change:**
```cpp
// Before (deprecated)
MoveWaypoint(creature->GetWaypointPath(), true);

// After (updated API)
MovePath(creature->GetWaypointPath(), FORCED_MOVEMENT_RUN);
```
**Note:** Currently disabled by default as testing shows it's not required for normal operation.

**Feature Flags:**
```bash
# Automatically set for playerbots fork
APPLY_SENDTRAINERLIST_PATCH=1

# Disabled by default - enable if needed
APPLY_MOVEPATH_PATCH=0
```

**Debug Output:**
The hook provides detailed debug information during builds:
```
🔧 mod-ale-patches: Applying playerbots fork compatibility fixes to mod-ale
   ✅ Playerbots detected via MODULES_REBUILD_SOURCE_PATH
   ✅ Applied SendTrainerList compatibility fix
   ✅ Applied 1 compatibility patch(es)
```

**Why This Exists:**
The playerbots fork has slightly different API signatures in certain WorldSession methods. These patches ensure mod-ale (Eluna) compiles and functions correctly with both standard AzerothCore and the playerbots fork.

### `black-market-setup`
Black Market specific setup tasks.

## Usage in Manifest

```json
{
  "post_install_hooks": ["copy-standard-lua", "apply-compatibility-patch"]
}
```
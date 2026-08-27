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
Applies signature-compatibility patches for mod-ale (ALE - AzerothCore Lua Engine, formerly Eluna) so a fresh mod-ale checkout compiles against whichever core is being built (upstream AzerothCore or the playerbots fork, which can lag upstream API changes).

Both patches are self-guarding: they read the signature declared by the core's actual header and only rewrite the module when the two disagree. If the core header can't be located, they skip rather than guess.

**Patches Applied:**

#### OnPlayerResurrect Signature Fix
**What it fixes:** Upstream changed `PlayerScript::OnPlayerResurrect`'s third parameter from `bool` to `bool&`; the module override must match the core being built.
**Core header consulted:** `src/server/game/Scripting/ScriptDefines/PlayerScript.h`
**File patched:** `src/ALE_SC.cpp`

#### CanPacketSend/CanPacketReceive Signature Fix
**What it fixes:** Upstream mod-ale (azerothcore/mod-ale#366) changed the packet hooks to take `WorldPacket const&`; older cores still declare non-const `WorldPacket&`.
**Core header consulted:** `src/server/game/Scripting/ScriptDefines/ServerScript.h`
**File patched:** `src/ALE_SC.cpp`

**Feature Flags:**
```bash
# Both enabled by default; set to 0 to disable
APPLY_RESURRECT_SIGNATURE_PATCH=1
APPLY_PACKET_SIGNATURE_PATCH=1
```

**History:** Earlier revisions also carried blind sed patches (SendTrainerList, override keyword, MovePath). They were removed in 2026-08 after their target patterns disappeared from mod-ale master and the playerbots fork caught up to the upstream signatures.

### `black-market-setup`
Black Market specific setup tasks.

## Usage in Manifest

```json
{
  "post_install_hooks": ["copy-standard-lua", "apply-compatibility-patch"]
}
```
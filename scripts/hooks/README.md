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
- `LUA_SCRIPTS_TARGET` - ALE script directory. Set to `/azerothcore/lua_scripts` (the
  `storage/lua_scripts` mount the worldserver reads) inside the `ac-modules` container; empty
  for host-side runs from `build.sh`, where Lua hooks skip staging.

### Return Codes
- `0` - Success
- `1` - Warning (logged, never fatal)
- `2` or higher - Error. A hook named in the manifest that doesn't exist counts as an error too.
  - Host-side runs (from `build.sh`) stop before the build, because these hooks prepare sources that are about to be compiled.
  - Runs inside `ac-modules` during a deploy record the failure in `storage/modules/.modules-meta/hook-failures.txt`. `stage-modules.sh` lists it at the end of the deploy. The container still exits 0, because the worldserver doesn't wait on it and failing it would only block `ac-post-install`.

## Generic Hooks

### Lua staging hooks
`copy-standard-lua`, `copy-aio-lua`, `copy-aio-server` and `black-market-setup` share
`lib/lua-staging.sh`. Each module's scripts are staged into their own subfolder,
`$LUA_SCRIPTS_TARGET/<module name>/`. `manage-modules.sh` clears every manifest module's folder
before the hooks run, so disabled modules (and modules whose Lua hook was removed) disappear and
enabled ones are re-staged; files not named after a module are left alone. ALE loads subfolders recursively and adds each
to the Lua `require` path. ALE refuses to load two scripts with the same file name, even from
different subfolders, and logs "File with same name already loaded".

Exit codes: `0` staged, `1` no Lua found (warning), `2` target not writable (error).
Tests: `scripts/hooks/tests/test-lua-hooks.sh`.

### `copy-standard-lua`
Stages Lua scripts from standard locations (non-recursive):
- `lua_scripts/*.lua`
- `Server Files/lua_scripts/*.lua` (Black Market pattern)
- `scripts/*.lua`
- `*.lua` (root level)

### `copy-aio-lua`
Stages server-side scripts of AIO addon modules from `Server/`, `server/`, `lua_scripts/`,
`Server Files/lua_scripts/` and the module root. Client files are not copied.

### `copy-lua-tree`
Stages every `.lua` in the module (skipping `.git`), preserving subfolders. For modules that
`require` files kept in subfolders, e.g. `azerothcore-lua-ah-bot` (`AHBot/EnchantmentModule.lua`).

### `copy-aio-server`
Stages the AIO framework itself (`MODULE_AIO`): the whole `AIO_Server/` tree, preserving
subfolders such as `Dep_Smallfolk/`. `AIO_Client/` is a client addon and is not copied.

### `apply-compatibility-patch`
Applies source code patches for compatibility fixes.
Reads patch definitions from module metadata.

## Module-Specific Hooks

Module-specific hooks are named after their primary module and handle unique setup requirements.

### `mod-ale-patches`
Applies signature-compatibility patches for mod-ale (ALE - AzerothCore Lua Engine, formerly Eluna) so a fresh mod-ale checkout compiles against whichever core is being built (upstream AzerothCore or the playerbots fork, which can lag upstream API changes).

All patches are self-guarding: they read the signature declared by the actual header being built against (the core, or the sibling mod-playerbots checkout) and only rewrite the module when the two disagree. If that header can't be located, they skip rather than guess.

**Patches Applied:**

#### OnPlayerResurrect Signature Fix
**What it fixes:** Upstream changed `PlayerScript::OnPlayerResurrect`'s third parameter from `bool` to `bool&`; the module override must match the core being built.
**Core header consulted:** `src/server/game/Scripting/ScriptDefines/PlayerScript.h`
**File patched:** `src/ALE_SC.cpp`

#### CanPacketSend/CanPacketReceive Signature Fix
**What it fixes:** Upstream mod-ale (azerothcore/mod-ale#366) changed the packet hooks to take `WorldPacket const&`; older cores still declare non-const `WorldPacket&`.
**Core header consulted:** `src/server/game/Scripting/ScriptDefines/ServerScript.h`
**File patched:** `src/ALE_SC.cpp`

#### Playerbot InterruptSpell Binding Fix
**What it fixes:** mod-playerbots #2680 removed `PlayerbotAI::InterruptSpell()` in favour of the deferred `RequestSpellInterrupt()`; mod-ale #397's Lua bindings still call the old method (azerothcore/mod-ale#398). The binding is redirected to `RequestSpellInterrupt()` only when the staged mod-playerbots checkout no longer declares `InterruptSpell()`.
**Header consulted:** `modules/mod-playerbots/src/Bot/PlayerbotAI.h` (sibling checkout)
**File patched:** `src/LuaEngine/methods/Playerbots/PlayerBotAIMethods.h`

#### Playerbot IsBot Binding Fix
**What it fixes:** mod-playerbots #2864 (commit 037c014) removed `WorldSession::IsBot()` in favour of centralized bot tracking via `sPlayerbotsMgr.GetPlayerbotAI(player)`. mod-ale's `PlayerMethods.h` calls `player->GetSession()->IsBot()`, causing compile errors against updated playerbots branches. When `WorldSession::IsBot()` is no longer declared by the core, `PlayerMethods.h` is patched to include `PlayerbotAI.h`/`PlayerbotMgr.h` and use `player && sPlayerbotsMgr.GetPlayerbotAI(player) != nullptr`.
**Core header consulted:** `src/server/game/Server/WorldSession.h`
**Module header consulted:** `modules/mod-playerbots/src/Bot/PlayerbotMgr.h` (sibling checkout)
**File patched:** `src/LuaEngine/methods/PlayerMethods.h`

**Feature Flags:**
```bash
# All enabled by default; set to 0 to disable
APPLY_RESURRECT_SIGNATURE_PATCH=1
APPLY_PACKET_SIGNATURE_PATCH=1
APPLY_PLAYERBOT_INTERRUPT_PATCH=1
APPLY_PLAYERBOT_ISBOT_PATCH=1
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
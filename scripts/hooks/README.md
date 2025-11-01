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

Module-specific hooks are named after their primary module:
- `mod-ale-patches` - Apply mod-ale compatibility fixes
- `black-market-setup` - Black Market specific setup

## Usage in Manifest

```json
{
  "post_install_hooks": ["copy-standard-lua", "apply-compatibility-patch"]
}
```
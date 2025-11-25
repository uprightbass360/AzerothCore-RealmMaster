# Disabled Modules - Build Issues

This document tracks modules that have been disabled due to compilation errors or compatibility issues.

**Last Updated:** 2025-11-14

**Note:** Historical snapshot. The current authoritative status for disabled/blocked modules is `status: "blocked"` in `config/module-manifest.json` (94 entries as of now). Align this file with the manifest during the next maintenance pass.

---

## Disabled Modules

### 1. mod-azerothshard
**Status:** ❌ DISABLED
**Reason:** Compilation error - Method name mismatch
**Error:**
```
fatal error: no member named 'getLevel' in 'Player'; did you mean 'GetLevel'?
```

**Details:**
- Module uses incorrect method name `getLevel()` instead of `GetLevel()`
- AzerothCore uses PascalCase for method names
- Module needs update to match current API

**Fix Required:** Update module source to use correct method names

---

### 2. mod-challenge-modes
**Status:** ❌ DISABLED
**Reason:** Compilation error - Override signature mismatch
**Error:**
```
fatal error: only virtual member functions can be marked 'override'
OnGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
```

**Details:**
- Method `OnGiveXP` signature doesn't match base class
- Base class may have changed signature in AzerothCore
- Override keyword used on non-virtual method

**Fix Required:** Update to match current AzerothCore PlayerScript hooks

---

### 3. mod-ahbot (C++ version)
**Status:** ❌ DISABLED
**Reason:** Linker error - Missing script function
**Error:**
```
undefined reference to `Addmod_ahbotScripts()'
```

**Details:**
- ModulesLoader expects `Addmod_ahbotScripts()` but function not defined
- Possible incomplete module or build issue
- Alternative: Use MODULE_LUA_AH_BOT instead (Lua version)

**Alternative:** `MODULE_LUA_AH_BOT=1` (Lua implementation available)

---

### 4. azerothcore-lua-multivendor
**Status:** ❌ DISABLED
**Reason:** Linker error - Missing script function
**Error:**
```
undefined reference to `Addazerothcore_lua_multivendorScripts()'
```

**Details:**
- ModulesLoader expects script function but not found
- May be Lua-only module incorrectly marked as C++ module
- Module metadata may be incorrect

**Fix Required:** Check module type in manifest or fix module loader

---

## Previously Blocked Modules (Manifest)

These modules are blocked in the manifest with known issues:

### MODULE_POCKET_PORTAL
**Reason:** Requires C++20 std::format support patch before enabling

### MODULE_STATBOOSTER
**Reason:** Override signature mismatch on OnLootItem

### MODULE_DUNGEON_RESPAWN
**Reason:** Upstream override signature mismatch (OnBeforeTeleport); awaiting fix

---

## Recommended Actions

### For Users:

1. **Leave these modules disabled** until upstream fixes are available
2. **Check alternatives** - Some modules have Lua versions (e.g., lua-ah-bot)
3. **Monitor updates** - Watch module repositories for fixes

### For Developers:

1. **mod-azerothshard**: Fix method name casing (`getLevel` → `GetLevel`)
2. **mod-challenge-modes**: Update `OnGiveXP` signature to match current API
3. **mod-ahbot**: Verify script loader function exists or switch to Lua version
4. **multivendor**: Check if module is Lua-only and update manifest type

---

## Current Working Module Count

**Total in Manifest:** ~93 modules (historical; current manifest: 348 total / 221 supported / 94 blocked)
**Enabled:** 89 modules
**Disabled (Build Issues):** 4 modules
**Blocked (Manifest):** 3 modules

---

## Clean Build After Module Changes

When enabling/disabling modules, always do a clean rebuild:

```bash
# Stop containers
docker compose down

# Clean build directory
rm -rf local-storage/source/build

# Regenerate module state
python3 scripts/python/modules.py \
  --env-path .env \
  --manifest config/module-manifest.json \
  generate --output-dir local-storage/modules

# Rebuild
./build.sh --yes
```

---

## Troubleshooting Build Errors

### Undefined Reference Errors
**Symptom:** `undefined reference to 'AddXXXScripts()'`

**Solution:**
1. Disable the problematic module in `.env`
2. Clean build directory
3. Rebuild

### Override Errors
**Symptom:** `only virtual member functions can be marked 'override'`

**Solution:**
1. Module hook signature doesn't match AzerothCore API
2. Disable module or wait for upstream fix

### Method Not Found Errors
**Symptom:** `no member named 'methodName'`

**Solution:**
1. Module uses outdated API
2. Check for case-sensitivity (e.g., `getLevel` vs `GetLevel`)
3. Disable module until updated

---

## .env Configuration

Current disabled modules in `.env`:

```bash
MODULE_AZEROTHSHARD=0          # Method name mismatch
MODULE_CHALLENGE_MODES=0       # Override signature mismatch
MODULE_AHBOT=0                 # Linker error (use lua version)
MODULE_MULTIVENDOR=0           # Linker error
MODULE_POCKET_PORTAL=0         # C++20 requirement
MODULE_STATBOOSTER=0           # Override mismatch
MODULE_DUNGEON_RESPAWN=0       # Override mismatch
```

---

**Note:** This list will be updated as modules are fixed or new issues discovered.

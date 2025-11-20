# Blocked Modules - Complete Summary

**Last Updated:** 2025-11-14
**Status:** ✅ All blocked modules properly disabled

---

## Summary

All modules with known compilation or linking issues have been:
1. ✅ **Blocked in manifest** with documented reasons
2. ✅ **Disabled in .env** (set to 0)
3. ✅ **Excluded from build** via module state generation

---

## Blocked Modules (8 Total)

### Build Failures - Compilation Errors (3)

#### 1. mod-azerothshard (MODULE_AZEROTHSHARD)
**Status:** 🔴 BLOCKED
**Category:** Compilation Error
**Issue:** Method name mismatch

**Error:**
```cpp
fatal error: no member named 'getLevel' in 'Player'; did you mean 'GetLevel'?
if (req <= pl->getLevel())
              ^~~~~~~~
              GetLevel
```

**Root Cause:** Module uses lowercase method names instead of AzerothCore's PascalCase convention

**Fix Required:** Update all method calls to use correct casing

---

#### 2. mod-challenge-modes (MODULE_CHALLENGE_MODES)
**Status:** 🔴 BLOCKED
**Category:** Compilation Error
**Issue:** Override signature mismatch

**Error:**
```cpp
fatal error: only virtual member functions can be marked 'override'
void OnGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
```

**Root Cause:** Method signature doesn't match base class - likely API change in AzerothCore

**Fix Required:** Update to match current PlayerScript hook signatures

---

#### 3. mod-quest-count-level (MODULE_LEVEL_GRANT)
**Status:** 🔴 BLOCKED
**Category:** Compilation Error
**Issue:** Uses removed API

**Details:** Uses `ConfigMgr::GetBoolDefault` which was removed from modern AzerothCore

**Fix Required:** Update to use current configuration API

---

### Build Failures - Linker Errors (2)

#### 4. mod-ahbot (MODULE_AHBOT)
**Status:** 🔴 BLOCKED
**Category:** Linker Error
**Issue:** Missing script loader function

**Error:**
```
undefined reference to 'Addmod_ahbotScripts()'
```

**Root Cause:** ModulesLoader expects `Addmod_ahbotScripts()` but function not defined

**Alternative:** ✅ Use **MODULE_LUA_AH_BOT=1** (Lua version works)

---

#### 5. azerothcore-lua-multivendor (MODULE_MULTIVENDOR)
**Status:** 🔴 BLOCKED
**Category:** Linker Error
**Issue:** Missing script loader function

**Error:**
```
undefined reference to 'Addazerothcore_lua_multivendorScripts()'
```

**Root Cause:** Module may be Lua-only but marked as C++ module

**Fix Required:** Check module type in manifest or implement C++ loader

---

### Known API Incompatibilities (3)

#### 6. mod-pocket-portal (MODULE_POCKET_PORTAL)
**Status:** 🔴 BLOCKED
**Category:** C++20 Requirement
**Issue:** Requires std::format support

**Details:** Module uses C++20 features not available in current build environment

**Fix Required:** Either upgrade compiler or refactor to use compatible C++ version

---

#### 7. StatBooster (MODULE_STATBOOSTER)
**Status:** 🔴 BLOCKED
**Category:** API Mismatch
**Issue:** Override signature mismatch on OnLootItem

**Details:** Hook signature doesn't match current AzerothCore API

**Fix Required:** Update to match current OnLootItem hook signature

---

#### 8. DungeonRespawn (MODULE_DUNGEON_RESPAWN)
**Status:** 🔴 BLOCKED
**Category:** API Mismatch
**Issue:** Override signature mismatch on OnBeforeTeleport

**Details:** Hook signature doesn't match current AzerothCore API

**Fix Required:** Update to match current OnBeforeTeleport hook signature

---

## Working Alternatives

Some blocked modules have working alternatives:

| Blocked Module | Working Alternative | Status |
|----------------|-------------------|--------|
| mod-ahbot (C++) | MODULE_LUA_AH_BOT=1 | ✅ Available |

---

## .env Configuration

All blocked modules are disabled:

```bash
# Build Failures - Compilation
MODULE_AZEROTHSHARD=0          # Method name mismatch
MODULE_CHALLENGE_MODES=0       # Override signature mismatch
MODULE_LEVEL_GRANT=0           # Removed API usage

# Build Failures - Linker
MODULE_AHBOT=0                 # Missing script function (use lua version)
MODULE_MULTIVENDOR=0           # Missing script function

# API Incompatibilities
MODULE_POCKET_PORTAL=0         # C++20 requirement
MODULE_STATBOOSTER=0           # Hook signature mismatch
MODULE_DUNGEON_RESPAWN=0       # Hook signature mismatch
```

---

## Module Statistics

**Total Modules in Manifest:** ~93
**Blocked Modules:** 8 (8.6%)
**Available Modules:** 85 (91.4%)

### Breakdown by Category:
- 🔴 Compilation Errors: 3 modules
- 🔴 Linker Errors: 2 modules
- 🔴 API Incompatibilities: 3 modules

---

## Verification Status

✅ **All checks passed:**

- ✅ All blocked modules have `status: "blocked"` in manifest
- ✅ All blocked modules have documented `block_reason`
- ✅ All blocked modules are disabled in `.env` (=0)
- ✅ Module state regenerated excluding blocked modules
- ✅ Build will not attempt to compile blocked modules

---

## Build Process

With all problematic modules blocked, the build should proceed cleanly:

```bash
# 1. Clean any previous build artifacts
docker compose down
rm -rf local-storage/source/build

# 2. Module state is already generated (excluding blocked modules)
# Verify: cat local-storage/modules/modules.env | grep MODULES_ENABLED

# 3. Build
./build.sh --yes
```

**Expected Result:** Clean build with 85 working modules

---

## For Module Developers

If you want to help fix these modules:

### Quick Fixes (1-2 hours each):

1. **mod-azerothshard**: Search/replace `getLevel()` → `GetLevel()` and similar
2. **mod-level-grant**: Replace `ConfigMgr::GetBoolDefault` with current API

### Medium Fixes (4-8 hours each):

3. **mod-challenge-modes**: Update `OnGiveXP` signature to match current API
4. **StatBooster**: Update `OnLootItem` signature
5. **DungeonRespawn**: Update `OnBeforeTeleport` signature

### Complex Fixes (16+ hours each):

6. **mod-ahbot**: Debug why script loader function is missing or use Lua version
7. **mod-multivendor**: Determine if module should be Lua-only
8. **mod-pocket-portal**: Refactor C++20 features to C++17 or update build environment

---

## Testing After Fixes

If a module is fixed upstream:

```bash
# 1. Update the module repository
cd local-storage/staging/modules/mod-name
git pull

# 2. Update manifest (remove block)
# Edit config/module-manifest.json:
# Change: "status": "blocked"
# To: "status": "active"

# 3. Enable in .env
# Change: MODULE_NAME=0
# To: MODULE_NAME=1

# 4. Clean rebuild
docker compose down
rm -rf local-storage/source/build
./build.sh --yes
```

---

## Maintenance

This document should be updated when:
- Modules are fixed and unblocked
- New problematic modules are discovered
- AzerothCore API changes affect more modules
- Workarounds or alternatives are found

---

**Last Verification:** 2025-11-14
**Next Review:** After AzerothCore major API update

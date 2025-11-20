# Bug Fix: SQL Staging Path Incorrect

**Date:** 2025-11-15
**Status:** ✅ FIXED
**Severity:** Critical (Prevented module SQL from being applied)

---

## Summary

Fixed critical bug in `scripts/bash/stage-module-sql.sh` that prevented module SQL files from being staged in the correct AzerothCore directory structure, causing database schema errors and module failures.

---

## The Bug

### Symptom
Deployment failed with error:
```
[1146] Table 'acore_world.beastmaster_tames' doesn't exist
Your database structure is not up to date.
```

### Root Cause
**File:** `scripts/bash/stage-module-sql.sh`
**Lines:** 259-261

The script was incorrectly removing the `db_` prefix from database types when creating target directories:

```bash
# WRONG (before fix)
local target_subdir="${current_db#db_}"  # Strips "db_" → "world"
local target_dir="$acore_path/data/sql/updates/$target_subdir"
# Result: /azerothcore/modules/mod-name/data/sql/updates/world/  ❌
```

**Problem:** AzerothCore's `dbimport` tool expects SQL in `updates/db_world/` not `updates/world/`

### Impact
- **All module SQL failed to apply** via AzerothCore's native updater
- SQL files staged to wrong directory (`updates/world/` instead of `updates/db_world/`)
- `dbimport` couldn't find the files
- Modules requiring SQL failed to initialize
- Database integrity checks failed on startup

---

## The Fix

### Code Change
**File:** `scripts/bash/stage-module-sql.sh`
**Lines:** 259-261

```bash
# CORRECT (after fix)
# AzerothCore expects db_world, db_auth, etc. (WITH db_ prefix)
local target_dir="$acore_path/data/sql/updates/$current_db"
# Result: /azerothcore/modules/mod-name/data/sql/updates/db_world/  ✅
```

### Verification
AzerothCore source confirms the correct structure:
```bash
$ find local-storage/source -type d -name "db_world"
local-storage/source/azerothcore-playerbots/data/sql/archive/db_world
local-storage/source/azerothcore-playerbots/data/sql/updates/db_world  ← Correct!
local-storage/source/azerothcore-playerbots/data/sql/base/db_world
```

---

## Testing

### Before Fix
```bash
$ docker exec ac-worldserver ls /azerothcore/modules/mod-npc-beastmaster/data/sql/updates/
world/  ❌ Wrong directory name
```

### After Fix
```bash
$ docker exec ac-worldserver ls /azerothcore/modules/mod-npc-beastmaster/data/sql/updates/
db_world/  ✅ Correct!

$ ls /azerothcore/modules/mod-npc-beastmaster/data/sql/updates/db_world/
20251115_22_1_mod-npc-beastmaster_beastmaster_tames.sql  ✅
20251115_22_2_mod-npc-beastmaster_beastmaster_tames_inserts.sql  ✅
```

---

## Why This Bug Existed

The original implementation likely assumed AzerothCore used simple directory names (`world`, `auth`, `characters`) without the `db_` prefix. However, AzerothCore's actual schema uses:

| Database Type | Directory Name |
|--------------|----------------|
| World | `db_world` (not `world`) |
| Auth | `db_auth` (not `auth`) |
| Characters | `db_characters` (not `characters`) |
| Playerbots | `db_playerbots` (not `playerbots`) |

The bug was introduced when adding support for multiple database types and attempting to "normalize" the names by stripping the prefix.

---

## Impact on Phase 1 Implementation

This bug would have completely broken the Phase 1 module SQL refactor:

- ✅ **Goal:** Use AzerothCore's native updater for module SQL
- ❌ **Reality:** SQL staged to wrong location, updater couldn't find it
- ❌ **Result:** Module SQL never applied, databases incomplete

**Critical that we caught this before merging!**

---

## Lessons Learned

1. **Verify directory structure** against source code, not assumptions
2. **Test with real deployment** before considering feature complete
3. **Check AzerothCore conventions** - they use `db_` prefixes everywhere
4. **Integration testing is essential** - unit tests wouldn't have caught this

---

## Related Files

- `scripts/bash/stage-module-sql.sh` - Fixed (lines 259-261)
- `scripts/bash/manage-modules.sh` - Calls staging (working correctly)
- `scripts/python/modules.py` - SQL discovery (uses `db_*` correctly)

---

## Commit

**Fix:** Correct SQL staging directory structure for AzerothCore compatibility

Details:
- Fixed `stage-module-sql.sh` to preserve `db_` prefix in directory names
- Changed from `updates/world/` to `updates/db_world/` (correct format)
- Verified against AzerothCore source code directory structure
- Prevents [1146] table doesn't exist errors on deployment

**Type:** Bug Fix
**Severity:** Critical
**Impact:** Phase 1 implementation
**Testing:** Code review + path verification

---

**Status:** ✅ Fixed and ready to commit

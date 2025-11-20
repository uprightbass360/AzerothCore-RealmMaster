# Aggressive Cleanup Plan - Remove Build-Time SQL Staging

**Date:** 2025-11-16
**Approach:** Aggressive removal with iterative enhancement

---

## Files to DELETE Completely

### 1. `scripts/bash/stage-module-sql.sh` (297 lines)
**Reason:** Only called by dead build-time code path, not used in runtime staging

### 2. Test files in `/tmp`
- `/tmp/test-discover.sh`
- `/tmp/test-sql-staging.log`

**Reason:** Temporary debugging artifacts

---

## Code to REMOVE from Existing Files

### 1. `scripts/bash/manage-modules.sh`

**Remove lines 480-557:**
```bash
stage_module_sql_files(){
  # ... 78 lines of dead code
}

execute_module_sql(){
  # Legacy function - now calls staging instead of direct execution
  SQL_EXECUTION_FAILED=0
  stage_module_sql_files || SQL_EXECUTION_FAILED=1
}
```

**Impact:** None - these functions are called during `build.sh` but the output is never used by AzerothCore

### 2. `scripts/bash/test-phase1-integration.sh`

**Remove or update SQL manifest checks:**
- Lines checking for `.sql-manifest.json`
- Lines verifying `stage_module_sql_files()` exists in `manage-modules.sh`

**Replace with:** Runtime staging verification tests

### 3. `scripts/python/modules.py` (OPTIONAL - keep for now)

SQL manifest generation could stay - it's metadata that might be useful for debugging, even if not in deployment path.

**Decision:** Keep but document as optional metadata

---

## Current Runtime Staging - What's Missing

### Current Implementation (stage-modules.sh:372-450)

**What it does:**
```bash
for db_type in db-world db-characters db-auth; do
  for module_dir in /azerothcore/modules/*/data/sql/$db_type; do
    for sql_file in "$module_dir"/*.sql; do
      # Copy file with timestamp prefix
    done
  done
done
```

**Limitations:**

1. ❌ **No SQL validation** - copies files without checking content
2. ❌ **No empty file check** - could copy 0-byte files
3. ❌ **No error handling** - silent failures if copy fails
4. ❌ **Only scans direct directories** - misses legacy `world`, `characters` naming
5. ❌ **No deduplication** - could copy same file multiple times on re-deploy
6. ❌ **Glob only** - won't find files in subdirectories

### Real-World Edge Cases Found

From our module survey:
1. Some modules still use legacy `world` directory (not `db-world`)
2. Some modules still use legacy `characters` directory (not `db-characters`)
3. One module has loose SQL in base: `Copy for Custom Race.sql`
4. Build-time created `updates/db_world/` subdirectories (will be gone after cleanup)

---

## Functionality to ADD to Runtime Staging

### Enhancement 1: SQL File Validation

**Add before copying:**
```bash
# Check if file exists and is not empty
if [ ! -f "$sql_file" ] || [ ! -s "$sql_file" ]; then
  echo "  ⚠️  Skipping empty or invalid file: $sql_file"
  continue
fi

# Security check - reject SQL with shell commands
if grep -qE '^\s*(system|exec|shell|\\!)\s*\(' "$sql_file"; then
  echo "  ❌ Security: Rejecting SQL with shell commands: $sql_file"
  continue
fi
```

**Lines:** ~10 lines
**Benefit:** Security + reliability

### Enhancement 2: Support Legacy Directory Names

**Expand scan to include old naming:**
```bash
# Scan both new and legacy directory names
for db_type_pair in "db-world:world" "db-characters:characters" "db-auth:auth"; do
  IFS=':' read -r new_name legacy_name <<< "$db_type_pair"

  # Try new naming first
  for module_dir in /azerothcore/modules/*/data/sql/$new_name; do
    # ... process files
  done

  # Fall back to legacy naming if present
  for module_dir in /azerothcore/modules/*/data/sql/$legacy_name; do
    # ... process files
  done
done
```

**Lines:** ~15 lines
**Benefit:** Backward compatibility with older modules

### Enhancement 3: Better Error Handling

**Add:**
```bash
# Track successes and failures
local success=0
local failed=0

# When copying
if cp "$sql_file" "$target_file"; then
  echo "  ✓ Staged $module_name/$db_type/$(basename $sql_file)"
  ((success++))
else
  echo "  ❌ Failed to stage: $sql_file"
  ((failed++))
fi

# Report at end
if [ $failed -gt 0 ]; then
  echo "⚠️  Warning: $failed file(s) failed to stage"
fi
```

**Lines:** ~10 lines
**Benefit:** Visibility into failures

### Enhancement 4: Deduplication Check

**Add:**
```bash
# Check if file already staged (by hash or name)
existing_hash=$(md5sum "/azerothcore/data/sql/updates/$core_dir/"*"$base_name.sql" 2>/dev/null | awk '{print $1}' | head -1)
new_hash=$(md5sum "$sql_file" | awk '{print $1}')

if [ "$existing_hash" = "$new_hash" ]; then
  echo "  ℹ️  Already staged: $base_name.sql (identical)"
  continue
fi
```

**Lines:** ~8 lines
**Benefit:** Prevent duplicate staging on re-deploy

### Enhancement 5: Better Logging

**Add:**
```bash
# Log to file for debugging
local log_file="/tmp/module-sql-staging.log"
echo "=== Module SQL Staging - $(date) ===" >> "$log_file"

# Log each operation
echo "Staged: $module_name/$db_type/$base_name.sql -> $target_name" >> "$log_file"

# Summary at end
echo "Total: $success staged, $failed failed, $skipped skipped" >> "$log_file"
```

**Lines:** ~5 lines
**Benefit:** Debugging and audit trail

---

## Total Enhancement Cost

| Enhancement | Lines | Priority | Complexity |
|-------------|-------|----------|------------|
| SQL Validation | ~10 | HIGH | Low |
| Legacy Directory Support | ~15 | MEDIUM | Low |
| Error Handling | ~10 | HIGH | Low |
| Deduplication | ~8 | LOW | Medium |
| Better Logging | ~5 | LOW | Low |
| **TOTAL** | **~48 lines** | - | - |

**Net Result:** Remove ~450 lines of dead code, add back ~50 lines of essential functionality

---

## Implementation Plan

### Phase 1: Remove Dead Code (IMMEDIATE)
1. Delete `scripts/bash/stage-module-sql.sh`
2. Delete test files from `/tmp`
3. Remove `stage_module_sql_files()` and `execute_module_sql()` from `manage-modules.sh`
4. Update `test-phase1-integration.sh` to remove dead code checks

**Risk:** ZERO - this code is not in active deployment path

### Phase 2: Add SQL Validation (HIGH PRIORITY)
1. Add empty file check
2. Add security check for shell commands
3. Add basic error handling

**Lines:** ~20 lines
**Risk:** LOW - defensive additions

### Phase 3: Add Legacy Support (MEDIUM PRIORITY)
1. Scan both `db-world` AND `world` directories
2. Scan both `db-characters` AND `characters` directories

**Lines:** ~15 lines
**Risk:** LOW - expands compatibility

### Phase 4: Add Nice-to-Haves (LOW PRIORITY)
1. Deduplication check
2. Enhanced logging
3. Better error reporting

**Lines:** ~15 lines
**Risk:** VERY LOW - quality of life improvements

---

## Testing Strategy

### After Phase 1 (Dead Code Removal)
```bash
# Should work exactly as before
./deploy.sh --yes
docker logs ac-worldserver 2>&1 | grep "Applying update" | grep MODULE
# Should show all 46 module SQL files applied
```

### After Phase 2 (Validation)
```bash
# Test with empty SQL file
touch storage/modules/mod-test/data/sql/db-world/empty.sql
./deploy.sh --yes
# Should see: "⚠️  Skipping empty or invalid file"

# Test with malicious SQL
echo "system('rm -rf /');" > storage/modules/mod-test/data/sql/db-world/bad.sql
./deploy.sh --yes
# Should see: "❌ Security: Rejecting SQL with shell commands"
```

### After Phase 3 (Legacy Support)
```bash
# Test with legacy directory
mkdir -p storage/modules/mod-test/data/sql/world
echo "SELECT 1;" > storage/modules/mod-test/data/sql/world/test.sql
./deploy.sh --yes
# Should stage the file from legacy directory
```

---

## Rollback Plan

If anything breaks:

1. **Git revert** the dead code removal commit
2. All original functionality restored
3. Zero data loss - SQL files are just copies

**Recovery time:** < 5 minutes

---

## Success Criteria

After all phases:

✅ All 46 existing module SQL files still applied correctly
✅ Empty files rejected with warning
✅ Malicious SQL rejected with error
✅ Legacy directory names supported
✅ Clear error messages on failures
✅ Audit log available for debugging
✅ ~400 lines of dead code removed
✅ ~50 lines of essential functionality added

**Net improvement:** -350 lines, better security, better compatibility

---

## Next Steps

1. **Confirm approach** - User approval to proceed
2. **Phase 1 execution** - Remove all dead code
3. **Verify deployment still works** - Run full deployment test
4. **Phase 2 execution** - Add validation
5. **Phase 3 execution** - Add legacy support
6. **Phase 4 execution** - Add nice-to-haves
7. **Final testing** - Full integration test
8. **Git commit** - Clean commit history for each phase

---

**Ready to proceed with Phase 1?**

# Phase 1: Module SQL Refactor - Implementation Context

**Created:** 2025-01-14
**Status:** Ready to Begin
**Estimated Duration:** 2-3 days
**Risk Level:** Medium-High (core functionality change)

---

## Executive Summary

Phase 1 refactors module SQL management from manual execution to leveraging AzerothCore's native update system. This is the foundation for all subsequent improvements.

**Key Goal:** Stop manually executing module SQL; let AzerothCore's built-in updater handle it.

**Impact:**
- ✅ Reduces custom code by ~200 lines
- ✅ Adds proper update tracking with hash verification
- ✅ Prevents duplicate SQL execution
- ✅ Integrates playerbots database properly
- ✅ Enables automatic post-restore verification

---

## Current State Analysis

### How Module SQL Works Now (Manual Execution)

**Flow:**
```
1. Module enabled in .env
   ↓
2. manage-modules.sh clones module repo
   ↓
3. SQL files copied to /tmp/scripts/sql/custom/
   ↓
4. manage-modules-sql.sh MANUALLY executes SQL
   ↓
5. Success/failure tracked in bash arrays
   ↓
6. No permanent record of execution
```

**Problems:**
1. **No redundancy checking** - SQL can run multiple times
2. **No update tracking** - Not in `updates` table
3. **No hash verification** - Can't detect changes
4. **Custom execution logic** - ~250 lines of bash
5. **Playerbots special handling** - Template replacement
6. **No rollback capability** - Can't undo SQL
7. **Manual state management** - Bash arrays, not DB

### Relevant Files (Current Implementation)

**1. `scripts/bash/manage-modules-sql.sh` (381 lines)**
```bash
# Key functions:
render_sql_file_for_execution()  # Lines 16-46: Playerbots template replacement
mysql_exec()                      # Lines 60-72: MySQL wrapper
playerbots_table_exists()        # Lines 74-79: Playerbots detection
run_custom_sql_group()           # Lines 81-112: Main execution loop
execute_module_sql_scripts()     # Lines 180-230: Orchestration

# SQL execution happens here:
mysql_exec "${target_db}" < "$rendered"  # Line 102
```

**2. `scripts/bash/manage-modules.sh` (616 lines)**
```bash
# SQL helper invocation:
source "$SQL_HELPER_PATH"            # Line 599
execute_module_sql_scripts           # Line 603

# Module staging location:
MODULES_HOST_DIR="$staging_modules_dir"  # Line 438
```

**3. `scripts/python/modules.py` (546 lines)**
```python
# Module metadata management
class ModuleState:
    key: str
    name: str
    repo: str
    type: str  # "cpp", "lua", "data", "tool"
    enabled: bool
    # NO SQL file tracking currently
```

**4. `scripts/bash/db-import-conditional.sh` (340 lines)**
```bash
# dbimport.conf generation:
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "..."
WorldDatabaseInfo = "..."
CharacterDatabaseInfo = "..."
Updates.EnableDatabases = 7       # Line 314: Missing playerbots
Updates.AutoSetup = 1             # Line 315
Updates.AllowedModules = "all"    # Line 318
EOF

# Runs dbimport:
./dbimport  # Line 331
```

**5. `scripts/bash/auto-post-install.sh` (190 lines)**
```bash
# Config updates:
sed -i "s|^LoginDatabaseInfo.*|..." authserver.conf    # Line 139
sed -i "s|^WorldDatabaseInfo.*|..." worldserver.conf   # Line 141
# Missing: PlayerbotsDatabaseInfo in dbimport
```

---

## Target State (After Phase 1)

### How Module SQL Will Work (AzerothCore Native)

**Flow:**
```
1. Module enabled in .env
   ↓
2. manage-modules.sh clones module repo
   ↓
3. stage-module-sql.sh copies SQL to AzerothCore structure:
   modules/<module>/data/sql/updates/db_world/YYYYMMDD_HH_<desc>.sql
   ↓
4. dbimport (or worldserver startup) detects new SQL
   ↓
5. AzerothCore's updater applies SQL automatically
   ↓
6. Updates tracked in `updates` table with hash
   ↓
7. verify-sql-updates.sh confirms application
```

**Benefits:**
1. ✅ **Hash-based redundancy** - Won't re-apply same SQL
2. ✅ **Automatic tracking** - In `updates` table with state='MODULE'
3. ✅ **Change detection** - Hash mismatch triggers re-apply
4. ✅ **Standard mechanism** - Uses AzerothCore's proven system
5. ✅ **No special cases** - Playerbots handled same way
6. ✅ **Audit trail** - timestamps, execution speed tracked
7. ✅ **Database-driven** - State in DB, not files

---

## Implementation Plan

### Step 1: Create New Helper Scripts (Low Risk)

#### 1.1 Create `scripts/bash/stage-module-sql.sh`

**Purpose:** Copy module SQL files to AzerothCore's update directory structure

**Functions:**
```bash
stage_module_sql() {
    # Input: Module name, module repo path
    # Output: SQL files in /azerothcore/modules/<name>/data/sql/

    # 1. Discover SQL files in module repo
    # 2. Generate timestamp-based filenames
    # 3. Copy to proper database subdirectory
    # 4. Validate SQL syntax
    # 5. Log staging results
}

generate_sql_timestamp() {
    # Create YYYYMMDD_HH format from current time
    # Ensures unique, sequential naming
}

validate_sql_file() {
    # Basic SQL syntax check
    # Ensure no shell commands
    # Check for playerbots references
}

discover_module_sql() {
    # Find all .sql files in module
    # Determine target database (auth/world/characters)
    # Return list of files to stage
}
```

**Target Directory Structure:**
```
/azerothcore/modules/
├── mod-aoe-loot/
│   └── data/
│       └── sql/
│           └── updates/
│               └── db_world/
│                   └── 20250114_01_aoe_loot_config.sql
├── mod-learn-spells/
│   └── data/
│       └── sql/
│           └── updates/
│               └── db_world/
│                   └── 20250114_02_learn_spells_init.sql
└── [other modules...]
```

**Estimated Lines:** ~150

---

#### 1.2 Create `scripts/bash/verify-sql-updates.sh`

**Purpose:** Verify SQL updates in `updates` table

**Functions:**
```bash
verify_module_sql() {
    # Check if module SQL appears in updates table
    # Parameters: module_name, database_name

    mysql -e "SELECT name, hash, timestamp
              FROM ${database}.updates
              WHERE name LIKE '%${module}%'
              AND state='MODULE'"
}

list_module_updates() {
    # Show all module updates across all databases
    # Group by module name
    # Show counts and timestamps
}

check_update_applied() {
    # Verify specific SQL file was applied
    # Parameters: filename, expected_hash
    # Returns: 0 if applied, 1 if missing, 2 if hash mismatch
}

verify_sql_hash() {
    # Calculate hash of SQL file
    # Compare with hash in updates table
    # Report mismatches
}

generate_verification_report() {
    # Summary of all module SQL status
    # Missing updates
    # Hash mismatches
    # Application timestamps
}
```

**Output Example:**
```
🔍 Module SQL Verification Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ mod-aoe-loot (db_world)
   - 20250114_01_aoe_loot_config.sql
     Hash: 4B17F90847D05B7EDFBDC01F86560307226110AA ✓
     Applied: 2025-01-14 14:30:22
     Speed: 45ms

✅ mod-learn-spells (db_world)
   - 20250114_02_learn_spells_init.sql
     Hash: 8356D5D01BC87D838AFBB32A6062C15B5DFBACA5 ✓
     Applied: 2025-01-14 14:30:25
     Speed: 32ms

⚠️  mod-playerbots (db_playerbots)
   - Missing: 20250114_03_playerbots_schema.sql

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total: 2 applied, 1 missing, 0 hash mismatches
```

**Estimated Lines:** ~100

---

### Step 2: Modify Python Module System (Medium Risk)

#### 2.1 Update `scripts/python/modules.py`

**Current ModuleState class:**
```python
@dataclass
class ModuleState:
    key: str
    name: str
    repo: str
    ref: str
    type: str
    status: str
    enabled: bool
    # ... other fields
```

**Add SQL discovery:**
```python
@dataclass
class ModuleState:
    # ... existing fields ...
    sql_files: List[str] = field(default_factory=list)
    sql_databases: Dict[str, List[str]] = field(default_factory=dict)

def discover_sql_files(module_path: Path) -> Dict[str, List[Path]]:
    """
    Scan module for SQL files
    Returns: {
        'db_auth': [Path('file1.sql'), ...],
        'db_world': [Path('file2.sql'), ...],
        'db_characters': [Path('file3.sql'), ...]
    }
    """
    sql_files = {}
    sql_base = module_path / 'data' / 'sql'

    for db_type in ['db_auth', 'db_world', 'db_characters', 'db_playerbots']:
        # Check base/
        base_dir = sql_base / 'base' / db_type
        if base_dir.exists():
            sql_files.setdefault(db_type, []).extend(base_dir.glob('*.sql'))

        # Check updates/
        updates_dir = sql_base / 'updates' / db_type
        if updates_dir.exists():
            sql_files.setdefault(db_type, []).extend(updates_dir.glob('*.sql'))

        # Check custom/
        custom_dir = sql_base / 'custom' / db_type
        if custom_dir.exists():
            sql_files.setdefault(db_type, []).extend(custom_dir.glob('*.sql'))

    return sql_files
```

**Generate SQL staging manifest:**
```python
def generate_sql_manifest(state: ModuleCollectionState, output_dir: Path):
    """
    Create manifest of SQL files to stage

    Output: {
        "modules": [
            {
                "name": "mod-aoe-loot",
                "sql_files": {
                    "db_world": ["path/to/file1.sql", ...]
                }
            }
        ]
    }
    """
```

**Changes:**
- Add `discover_sql_files()` function (~30 lines)
- Update `ModuleState` dataclass (+2 fields)
- Add to `build_state()` function (+10 lines)
- Generate SQL manifest in `write_outputs()` (+10 lines)

**Total: +40 lines**

---

### Step 3: Update Module Management (Medium Risk)

#### 3.1 Modify `scripts/bash/manage-modules.sh`

**Current SQL handling (lines 472-606):**
```bash
# Source SQL helper
if [ -f "$helper_path" ]; then
    SQL_HELPER_PATH="$helper_path"
fi

# Execute SQL
if [ "${MODULES_SKIP_SQL:-0}" != "1" ]; then
    source "$SQL_HELPER_PATH"
    execute_module_sql_scripts
fi
```

**New SQL handling:**
```bash
# Stage SQL files instead of executing
stage_module_sql_files() {
    local staging_dir="$1"  # Module staging directory
    local source_dir="$2"    # AzerothCore source directory

    # Read SQL manifest from modules.py output
    local manifest="$staging_dir/.sql-manifest.json"
    if [ ! -f "$manifest" ]; then
        info "No SQL files to stage"
        return 0
    fi

    # Call stage-module-sql.sh for each module
    while read -r module_name; do
        local module_repo="$staging_dir/$module_name"
        local acore_modules="$source_dir/modules/$module_name"

        info "Staging SQL for $module_name"
        "$PROJECT_ROOT/scripts/bash/stage-module-sql.sh" \
            --module-name "$module_name" \
            --module-path "$module_repo" \
            --acore-path "$acore_modules" \
            --manifest "$manifest"
    done < <(jq -r '.modules[].name' "$manifest")
}

# Replace SQL execution with staging
if [ "${MODULES_SKIP_SQL:-0}" != "1" ]; then
    stage_module_sql_files "$staging_modules_dir" "$(get_acore_source_path)"
    info "Module SQL staged for application by AzerothCore updater"
else
    info "Skipping module SQL staging (MODULES_SKIP_SQL=1)"
fi
```

**Changes:**
- Replace `source "$SQL_HELPER_PATH"` with staging call
- Add `stage_module_sql_files()` function (+30 lines)
- Remove `execute_module_sql_scripts` invocation (-10 lines)
- Add verification call (+10 lines)

**Total: +30 lines**

---

#### 3.2 Refactor `scripts/bash/manage-modules-sql.sh`

**Current size:** 381 lines

**Remove (will become obsolete):**
```bash
# Lines 16-46: render_sql_file_for_execution() - 31 lines
# Lines 60-72: mysql_exec() - 13 lines
# Lines 74-79: playerbots_table_exists() - 6 lines
# Lines 81-112: run_custom_sql_group() - 32 lines
# Lines 180-230: execute_module_sql_scripts() - 51 lines
# Total removed: ~133 lines
```

**Keep (still useful):**
```bash
# Logging functions
log_sql_success()    # Lines 48-52
log_sql_failure()    # Lines 54-58
# Module metadata loading
ensure_module_metadata()  # Lines 114-178
```

**Add (new functionality):**
```bash
# Wrapper functions for backward compatibility
stage_sql_for_module() {
    # Calls stage-module-sql.sh
    # Maintains interface for existing callers
}

verify_staged_sql() {
    # Calls verify-sql-updates.sh
    # Reports verification results
}
```

**New size:** ~181 lines (-200 lines!)

**Note:** This file may eventually be removed entirely if no longer needed

---

### Step 4: Integrate Playerbots Database (Low Risk)

#### 4.1 Update `scripts/bash/db-import-conditional.sh`

**Current dbimport.conf (lines 310-327):**
```bash
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
Updates.EnableDatabases = 7
Updates.AutoSetup = 1
TempDir = "${TEMP_DIR}"
MySQLExecutable = "${MYSQL_EXECUTABLE}"
Updates.AllowedModules = "all"
EOF
```

**New dbimport.conf:**
```bash
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
PlayerbotsDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}"
Updates.EnableDatabases = 15
Updates.AutoSetup = 1
TempDir = "${TEMP_DIR}"
MySQLExecutable = "${MYSQL_EXECUTABLE}"
Updates.AllowedModules = "all"
EOF
```

**Changes:**
- Add `PlayerbotsDatabaseInfo` line (+1 line)
- Change `Updates.EnableDatabases = 7` to `15` (1 line change)
  - 7 = 1 (auth) + 2 (char) + 4 (world)
  - 15 = 1 + 2 + 4 + 8 (playerbots)

**Note:** Requires AzerothCore source to support PlayerbotsDatabaseInfo. If not supported, this becomes a future enhancement.

---

#### 4.2 Add Post-Restore Verification

**Current restore completion (lines 283-290):**
```bash
if restore_backup "$backup_path"; then
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🎉 Backup restoration completed successfully!"
    exit 0
fi
```

**New with verification:**
```bash
if restore_backup "$backup_path"; then
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🎉 Backup restoration completed successfully!"

    # Verify and apply missing updates
    verify_and_update_restored_databases

    exit 0
fi

verify_and_update_restored_databases() {
    echo "🔍 Verifying restored database integrity..."

    # Check if dbimport is available
    if [ ! -f "/azerothcore/env/dist/bin/dbimport" ]; then
        warn "dbimport not available, skipping verification"
        return 0
    fi

    cd /azerothcore/env/dist/bin

    # Run dbimport to check state (will apply missing updates)
    echo "Running dbimport to apply any missing updates..."
    if ./dbimport; then
        ok "Database verification complete - all updates current"
    else
        warn "dbimport reported issues - check logs"
        return 1
    fi

    # Verify critical tables exist
    echo "Checking critical tables..."
    local critical_tables=("account" "characters" "creature" "quest_template")
    local missing_tables=0

    for table in "${critical_tables[@]}"; do
        # Determine database based on table
        local db_name="$DB_WORLD_NAME"
        case "$table" in
            account) db_name="$DB_AUTH_NAME" ;;
            characters) db_name="$DB_CHARACTERS_NAME" ;;
        esac

        if ! mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} \
                -e "SELECT 1 FROM ${db_name}.${table} LIMIT 1" >/dev/null 2>&1; then
            warn "Critical table missing: ${db_name}.${table}"
            missing_tables=$((missing_tables + 1))
        fi
    done

    if [ "$missing_tables" -gt 0 ]; then
        warn "${missing_tables} critical tables missing after restore"
        return 1
    fi

    ok "All critical tables verified"
    return 0
}
```

**Changes:**
- Add `verify_and_update_restored_databases()` function (+55 lines)
- Call after successful restore (+3 lines)
- Check dbimport availability (+5 lines)
- Verify critical tables (+15 lines)

**Total: +65 lines**

---

#### 4.3 Update `scripts/bash/auto-post-install.sh`

**Current config updates (lines 139-143):**
```bash
sed -i "s|^LoginDatabaseInfo.*|LoginDatabaseInfo = \"${MYSQL_HOST};...\"|" /azerothcore/config/authserver.conf
sed -i "s|^LoginDatabaseInfo.*|LoginDatabaseInfo = \"${MYSQL_HOST};...\"|" /azerothcore/config/worldserver.conf
sed -i "s|^WorldDatabaseInfo.*|WorldDatabaseInfo = \"${MYSQL_HOST};...\"|" /azerothcore/config/worldserver.conf
sed -i "s|^CharacterDatabaseInfo.*|CharacterDatabaseInfo = \"${MYSQL_HOST};...\"|" /azerothcore/config/worldserver.conf
```

**Add playerbots to worldserver.conf:**
```bash
# After existing database info updates
ensure_config_key /azerothcore/config/worldserver.conf \
    "PlayerbotsDatabaseInfo" \
    "\"${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}\""
```

**Changes:**
- Already has `ensure_config_key()` function (lines 146-158)
- Add one more call (+3 lines)
- Update comment (+2 lines)

**Total: +5 lines**

---

## File Change Summary

| File | Current Lines | Changes | New Lines | Net |
|------|--------------|---------|-----------|-----|
| `stage-module-sql.sh` | 0 (new) | +150 | 150 | +150 |
| `verify-sql-updates.sh` | 0 (new) | +100 | 100 | +100 |
| `manage-modules-sql.sh` | 381 | -200 | 181 | -200 |
| `manage-modules.sh` | 616 | +30 | 646 | +30 |
| `modules.py` | 546 | +40 | 586 | +40 |
| `db-import-conditional.sh` | 340 | +65 | 405 | +65 |
| `auto-post-install.sh` | 190 | +5 | 195 | +5 |
| **TOTAL** | **2,073** | | **2,263** | **+190** |

**Note:** While we add 190 net lines, we eliminate 200 lines of complex SQL execution logic and replace it with simple staging calls. The new code is cleaner and leverages AzerothCore's proven system.

---

## Testing Strategy

### Unit Tests (Per Component)

#### Test 1: SQL Staging (`stage-module-sql.sh`)

**Test Cases:**
1. Stage SQL from module with only db_world files
2. Stage SQL from module with multiple database types
3. Handle module with no SQL files (graceful skip)
4. Generate proper timestamp-based filenames
5. Validate SQL syntax (catch obvious errors)
6. Handle duplicate staging (idempotent)

**Test Script:**
```bash
# Create test module structure
mkdir -p /tmp/test-module/data/sql/updates/db_world
echo "CREATE TABLE test (id INT);" > /tmp/test-module/data/sql/updates/db_world/test.sql

# Run staging
./scripts/bash/stage-module-sql.sh \
    --module-name test-module \
    --module-path /tmp/test-module \
    --acore-path /tmp/acore-test

# Verify staged files exist
ls /tmp/acore-test/data/sql/updates/db_world/ | grep "test-module"

# Cleanup
rm -rf /tmp/test-module /tmp/acore-test
```

---

#### Test 2: SQL Verification (`verify-sql-updates.sh`)

**Test Cases:**
1. Verify SQL with proper hash match
2. Detect missing SQL (in files but not in updates table)
3. Detect hash mismatch (file changed after application)
4. List all module updates across databases
5. Generate verification report

**Requires:** Running MySQL with test data

---

#### Test 3: Module SQL Discovery (`modules.py`)

**Test Cases:**
```python
def test_discover_sql_files():
    # Create test module structure
    test_module = Path('/tmp/test-module')
    (test_module / 'data/sql/updates/db_world').mkdir(parents=True)
    (test_module / 'data/sql/updates/db_world/test.sql').write_text('SELECT 1;')

    # Run discovery
    sql_files = discover_sql_files(test_module)

    # Verify results
    assert 'db_world' in sql_files
    assert len(sql_files['db_world']) == 1
    assert sql_files['db_world'][0].name == 'test.sql'
```

---

### Integration Tests (Full Flow)

#### Integration Test 1: Fresh Module Install

**Scenario:** Install module with SQL for the first time

**Steps:**
1. Enable new module in .env (e.g., `MODULE_AOE_LOOT=1`)
2. Run `./scripts/bash/manage-modules.sh`
3. Verify SQL staged to `/azerothcore/modules/mod-aoe-loot/data/sql/`
4. Start worldserver
5. Check `updates` table for module SQL:
   ```sql
   SELECT * FROM acore_world.updates WHERE name LIKE '%aoe-loot%' AND state='MODULE';
   ```
6. Verify module functionality works

**Expected Result:**
- SQL staged correctly
- Updates applied on server startup
- Tracked in `updates` table
- Module functions correctly

---

#### Integration Test 2: Module Reinstall (Idempotency)

**Scenario:** Reinstall same module (should not re-apply SQL)

**Steps:**
1. Module already installed (from Test 1)
2. Run `./scripts/bash/manage-modules.sh` again
3. Start worldserver again
4. Check logs for "already applied" or "skipped" messages

**Expected Result:**
- SQL not re-applied (hash matches)
- No errors in logs
- Module still works

---

#### Integration Test 3: Playerbots Integration

**Scenario:** Install playerbots module with SQL

**Steps:**
1. Enable `MODULE_PLAYERBOTS=1`
2. Run module installation
3. Verify playerbots SQL staged
4. Check dbimport.conf has `PlayerbotsDatabaseInfo`
5. Check `Updates.EnableDatabases = 15`
6. Start worldserver
7. Query playerbots database updates:
   ```sql
   SELECT * FROM acore_playerbots.updates WHERE state='MODULE';
   ```

**Expected Result:**
- Playerbots SQL applied to playerbots database
- No template replacement needed
- Tracked in updates table

---

#### Integration Test 4: Post-Restore Verification

**Scenario:** Restore old backup, verify updates applied

**Steps:**
1. Create backup with current state
2. Add new module (e.g., `MODULE_FIREWORKS=1`)
3. Let SQL apply
4. Restore old backup (before new module)
5. System should detect missing SQL
6. dbimport should apply missing updates

**Expected Result:**
- Backup restored successfully
- Verification detects missing updates
- Updates applied automatically
- Server starts with all modules working

---

### Regression Tests

#### Regression Test 1: Existing Modules Still Work

**Modules to Test:**
- mod-aoe-loot
- mod-learn-spells
- mod-autobalance
- mod-playerbots

**Verification:**
- All modules load without errors
- SQL properly applied (check updates table)
- In-game functionality works

---

#### Regression Test 2: Backup/Restore Still Works

**Test:**
1. Create backup with new system
2. Restore backup
3. Verify all databases restored
4. Verify modules work after restore

---

### Performance Tests

#### Performance Test 1: Module Installation Time

**Measure:**
- Time to install 10 modules
- Before refactor (manual execution): X seconds
- After refactor (staging only): Y seconds

**Expected:** Faster (no SQL execution, just file copies)

---

#### Performance Test 2: Server Startup Time

**Measure:**
- Time for worldserver to become ready
- With 0 modules, 5 modules, 10 modules
- Monitor dbimport execution time

**Expected:** Slightly longer first time (applying all module SQL), then same or faster (cached in updates table)

---

## Rollback Plan

### If Phase 1 Fails

**Immediate Rollback Steps:**

1. **Revert code changes:**
   ```bash
   git checkout HEAD -- scripts/bash/manage-modules-sql.sh
   git checkout HEAD -- scripts/bash/manage-modules.sh
   git checkout HEAD -- scripts/python/modules.py
   git checkout HEAD -- scripts/bash/db-import-conditional.sh
   git checkout HEAD -- scripts/bash/auto-post-install.sh
   rm scripts/bash/stage-module-sql.sh
   rm scripts/bash/verify-sql-updates.sh
   ```

2. **Clear staged SQL:**
   ```bash
   # Remove staged SQL from AzerothCore modules
   rm -rf local-storage/source/azerothcore-*/modules/mod-*/data/sql/
   ```

3. **Restore SQL to old location:**
   ```bash
   # Re-run module installation with old code
   ./scripts/bash/manage-modules.sh
   ```

4. **Verify rollback:**
   - Check modules work
   - Verify SQL execution logs
   - Test module functionality in-game

---

### Partial Rollback (Keep Some Changes)

If only specific parts fail:

**Keep:**
- Quick win scripts (health check, backup status)
- Documentation

**Revert:**
- Module SQL staging
- dbimport.conf playerbots integration

**Selectively revert:**
```bash
# Keep post-restore verification, revert staging
git checkout HEAD -- scripts/bash/manage-modules-sql.sh
git checkout HEAD -- scripts/bash/manage-modules.sh
# Keep db-import-conditional.sh changes (verification)
```

---

## Success Criteria

### Must Have (Phase 1 Complete)

✅ **Functionality:**
1. Module SQL applied via AzerothCore updater (not manual execution)
2. SQL tracked in `updates` table with `state='MODULE'`
3. Hash verification prevents duplicate execution
4. Playerbots database integrated into dbimport
5. Post-restore verification applies missing updates
6. All existing modules still work

✅ **Code Quality:**
1. `manage-modules-sql.sh` reduced by ~200 lines
2. No regression in existing functionality
3. Tests pass (unit + integration)
4. Error handling improved
5. Logging comprehensive

✅ **Documentation:**
1. Changes documented in CHANGELOG
2. Implementation map updated
3. Migration guide for users

---

### Nice to Have (Can Defer)

🔲 Module SQL rollback capability
🔲 SQL syntax validation (beyond basic)
🔲 Automated performance benchmarks
🔲 Migration tool for existing installations

---

## Risk Mitigation

### High Risk: Module SQL Not Applied

**Mitigation:**
- Comprehensive testing with multiple modules
- Fallback to manual execution if staging fails
- Clear error messages with recovery steps
- Verification script to detect missing SQL

**Detection:**
- Health check shows missing module updates
- Modules don't work in-game
- Logs show "command not found" for module features

**Recovery:**
- Manually apply SQL from module repo
- Re-stage SQL files
- Check dbimport logs for errors

---

### Medium Risk: Playerbots Database Issues

**Mitigation:**
- Make playerbots integration optional (env var)
- Fallback to old behavior if not supported
- Test with and without playerbots enabled

**Detection:**
- dbimport fails with "unknown database" error
- Playerbots module doesn't install

**Recovery:**
- Revert playerbots integration
- Use separate SQL execution for playerbots
- Document as future enhancement

---

### Medium Risk: Performance Regression

**Mitigation:**
- Benchmark before and after
- Monitor server startup times
- Limit concurrent SQL application

**Detection:**
- Server takes longer to start
- dbimport runs slowly

**Recovery:**
- Optimize SQL file count
- Batch updates
- Use `Updates.ArchivedRedundancy = 0`

---

## Dependencies & Prerequisites

### Software Requirements

- ✅ Python 3.x with jq available
- ✅ AzerothCore source with dbimport tool
- ✅ MySQL client (docker exec or host)
- ✅ Bash 4.0+

### Environment Requirements

- ✅ `.env` file configured
- ✅ Module manifest exists
- ✅ MySQL container running
- ✅ AzerothCore source directory accessible

### Data Requirements

- ✅ At least one module with SQL to test
- ✅ Backup available for restore testing
- ✅ Test database for unit tests

---

## Timeline

### Day 1: Foundation

**Morning (4 hours):**
- Create `stage-module-sql.sh` (150 lines)
- Unit test SQL staging
- Fix any issues

**Afternoon (4 hours):**
- Create `verify-sql-updates.sh` (100 lines)
- Unit test verification
- Test with sample SQL

**Evening (2 hours):**
- Documentation
- Code review
- Commit: "Add SQL staging and verification helpers"

---

### Day 2: Integration

**Morning (4 hours):**
- Update `modules.py` SQL discovery (+40 lines)
- Test SQL discovery with real modules
- Update `manage-modules.sh` staging calls (+30 lines)

**Afternoon (4 hours):**
- Refactor `manage-modules-sql.sh` (-200 lines)
- Test with single module end-to-end
- Fix any integration issues

**Evening (2 hours):**
- Integration testing (3-5 modules)
- Document any issues
- Commit: "Integrate SQL staging into module management"

---

### Day 3: Finalization

**Morning (4 hours):**
- Update `db-import-conditional.sh` verification (+65 lines)
- Update `auto-post-install.sh` playerbots (+5 lines)
- Test backup/restore flow

**Afternoon (4 hours):**
- Full regression testing
- Performance testing
- Documentation updates

**Evening (2 hours):**
- Final review
- Create migration guide
- Commit: "Complete Phase 1 - Module SQL refactor"
- Tag: `v1.0-phase1`

---

## Next Steps After Phase 1

1. **Monitor production usage** (1 week)
2. **Collect feedback** from any issues
3. **Begin Phase 2** (Verification & Monitoring)
4. **Document lessons learned**

---

**End of Phase 1 Context**

# Implementation Map: Database & Module Management Improvements

**Created:** 2025-01-14
**Status:** Planning Phase
**Total Improvements:** 19 across 6 categories

---

## TOUCHPOINT AUDIT

### Core Files by Size and Impact

| File | Lines | Category | Impact Level |
|------|-------|----------|--------------|
| `scripts/bash/backup-merge.sh` | 1041 | Backup | Medium |
| `scripts/bash/manage-modules.sh` | 616 | Module Mgmt | **HIGH** |
| `scripts/python/modules.py` | 546 | Module Mgmt | **HIGH** |
| `scripts/bash/rebuild-with-modules.sh` | 524 | Build | Low |
| `scripts/bash/backup-import.sh` | 473 | Backup | Medium |
| `scripts/bash/migrate-stack.sh` | 416 | Deployment | Low |
| `scripts/bash/manage-modules-sql.sh` | 381 | **Module SQL** | **CRITICAL** |
| `scripts/bash/stage-modules.sh` | 375 | Module Mgmt | Medium |
| `scripts/bash/db-import-conditional.sh` | 340 | **DB Import** | **CRITICAL** |
| `scripts/python/apply-config.py` | 322 | Config | Medium |
| `scripts/bash/backup-export.sh` | 272 | Backup | Low |
| `scripts/bash/fix-item-import.sh` | 256 | Backup | Low |
| `scripts/bash/backup-scheduler.sh` | 225 | Backup | Medium |
| `scripts/bash/download-client-data.sh` | 202 | Setup | Low |
| `scripts/bash/verify-deployment.sh` | 196 | Deployment | Low |
| `scripts/bash/auto-post-install.sh` | 190 | **Config** | **HIGH** |
| `scripts/bash/configure-server.sh` | 163 | Config | Medium |
| `scripts/bash/setup-source.sh` | 154 | Setup | Low |

**CRITICAL FILES** (Will be modified in Phase 1):
1. `scripts/bash/manage-modules-sql.sh` (381 lines) - Complete refactor
2. `scripts/bash/db-import-conditional.sh` (340 lines) - Add verification
3. `scripts/bash/auto-post-install.sh` (190 lines) - Playerbots DB integration

**HIGH IMPACT FILES** (Will be modified in Phase 2-3):
1. `scripts/bash/manage-modules.sh` (616 lines) - SQL staging changes
2. `scripts/python/modules.py` (546 lines) - Minor updates

---

## DETAILED TOUCHPOINT ANALYSIS

### Category A: Module SQL Management

#### A1: Refactor Module SQL to Use AzerothCore's System

**Files to Modify:**

1. **`scripts/bash/manage-modules-sql.sh`** (381 lines)
   - **Current Function:** Manually executes SQL files via `mysql_exec`
   - **Changes Required:**
     - Remove `run_custom_sql_group()` function
     - Remove `mysql_exec()` wrapper
     - Remove `render_sql_file_for_execution()` (playerbots template)
     - Remove `playerbots_table_exists()` check
     - Add SQL staging logic to copy files to AzerothCore structure
     - Add verification via `updates` table query
   - **Lines to Remove:** ~250 lines (execution logic)
   - **Lines to Add:** ~50 lines (staging + verification)
   - **Net Change:** -200 lines

2. **`scripts/bash/manage-modules.sh`** (616 lines)
   - **Current Function:** Calls `manage-modules-sql.sh` for SQL execution
   - **Changes Required:**
     - Update SQL helper invocation (lines 472-606)
     - Add SQL file staging to proper AzerothCore directory structure
     - Add timestamp-based filename generation
     - Add SQL validation before staging
   - **Lines to Change:** ~50 lines
   - **Lines to Add:** ~80 lines (staging logic)
   - **Net Change:** +30 lines

3. **`scripts/python/modules.py`** (546 lines)
   - **Current Function:** Module manifest management
   - **Changes Required:**
     - Add SQL file discovery in module repos
     - Add SQL file metadata to module state
     - Generate SQL staging manifest
   - **Lines to Add:** ~40 lines
   - **Net Change:** +40 lines

**New Files to Create:**

4. **`scripts/bash/stage-module-sql.sh`** (NEW)
   - **Purpose:** Stage module SQL files to AzerothCore structure
   - **Functions:**
     - `copy_sql_to_acore_structure()` - Copy SQL with proper naming
     - `validate_sql_file()` - Basic SQL syntax check
     - `generate_sql_timestamp()` - Create YYYYMMDD_HH filename
   - **Estimated Lines:** ~150 lines

5. **`scripts/bash/verify-sql-updates.sh`** (NEW)
   - **Purpose:** Verify SQL updates in `updates` table
   - **Functions:**
     - `check_update_applied()` - Query updates table
     - `list_module_updates()` - Show module SQL status
     - `verify_sql_hash()` - Check hash matches
   - **Estimated Lines:** ~100 lines

**Docker/Config Files:**

6. **`docker-compose.yml`** or relevant compose file
   - Add volume mount for module SQL staging directory
   - Ensure `/azerothcore/modules/` is accessible

**SQL Directory Structure to Create:**
```
local-storage/source/azerothcore-playerbots/modules/
├── mod-aoe-loot/
│   └── data/
│       └── sql/
│           ├── base/
│           │   └── db_world/
│           └── updates/
│               └── db_world/
│                   └── 20250114_01_aoe_loot_init.sql
├── mod-learn-spells/
│   └── data/
│       └── sql/...
└── [other modules...]
```

**Total Impact:**
- Files Modified: 3
- Files Created: 2
- Net Code Change: -130 lines (significant reduction!)
- Complexity: Medium-High

---

#### A2: Add Module SQL Verification

**Files to Modify:**

1. **`scripts/bash/verify-sql-updates.sh`** (created in A1)
   - Already includes verification logic

2. **`scripts/bash/manage-modules.sh`**
   - Add post-installation verification call
   - Lines to add: ~20 lines

**Total Impact:**
- Files Modified: 1
- Code Change: +20 lines
- Complexity: Low (builds on A1)

---

#### A3: Support Module SQL Rollback

**New Files to Create:**

1. **`scripts/bash/rollback-module-sql.sh`** (NEW)
   - **Purpose:** Rollback module SQL changes
   - **Functions:**
     - `create_rollback_sql()` - Generate reverse SQL
     - `apply_rollback()` - Execute rollback
     - `track_rollback()` - Update rollback state
   - **Estimated Lines:** ~200 lines

**Module Directory Structure:**
```
modules/mod-example/
└── data/
    └── sql/
        ├── updates/
        │   └── db_world/
        │       └── 20250114_01_feature.sql
        └── rollback/
            └── db_world/
                └── 20250114_01_feature_rollback.sql
```

**Total Impact:**
- Files Created: 1
- Code Change: +200 lines
- Complexity: Medium

---

### Category B: Database Restoration & Verification

#### B1: Add Post-Restore Verification

**Files to Modify:**

1. **`scripts/bash/db-import-conditional.sh`** (340 lines) - **CRITICAL**
   - **Current Function:** Restores backups or runs dbimport
   - **Changes Required:**
     - Add verification step after restore (line ~283-290)
     - Call dbimport with --dry-run to check state
     - Apply missing updates if found
     - Log verification results
   - **Location:** After `restore_backup` function
   - **Lines to Add:** ~60 lines

**Code Insertion Point:**
```bash
# Current code (line ~283):
if restore_backup "$backup_path"; then
    echo "$(date): Backup successfully restored from $backup_path" > "$RESTORE_SUCCESS_MARKER"
    echo "🎉 Backup restoration completed successfully!"
    exit 0
fi

# ADD HERE: Verification step
verify_and_update_databases() {
    # New function to add
}
```

**New Functions to Add:**
```bash
verify_and_update_databases() {
    echo "🔍 Verifying restored database integrity..."
    cd /azerothcore/env/dist/bin

    # Check what would be applied
    local dry_run_output
    dry_run_output=$(./dbimport --dry-run 2>&1) || true

    # Parse output to see if updates are needed
    if echo "$dry_run_output" | grep -q "would be applied"; then
        warn "Missing updates detected, applying now..."
        ./dbimport || { err "Update verification failed"; return 1; }
    else
        ok "All updates are current"
    fi

    # Verify critical tables exist
    verify_core_tables
}

verify_core_tables() {
    # Check that core tables are present
    local tables=("account" "characters" "creature")
    # ... verification logic
}
```

**Total Impact:**
- Files Modified: 1
- Code Change: +60 lines
- Complexity: Medium

---

#### B2: Use updates Table for State Tracking

**Files to Modify:**

1. **`scripts/bash/db-import-conditional.sh`** (340 lines)
   - **Changes:** Replace marker file checks with SQL queries
   - **Lines to Change:** ~40 lines
   - **Lines to Add:** ~30 lines (helper functions)

**New Helper Functions:**
```bash
is_database_initialized() {
    local db_name="$1"
    mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -N -e \
        "SELECT COUNT(*) FROM ${db_name}.updates WHERE state='RELEASED'" 2>/dev/null || echo 0
}

get_last_update_timestamp() {
    local db_name="$1"
    mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -N -e \
        "SELECT MAX(timestamp) FROM ${db_name}.updates" 2>/dev/null || echo ""
}

count_module_updates() {
    local db_name="$1"
    mysql -h ${CONTAINER_MYSQL} -u${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} -N -e \
        "SELECT COUNT(*) FROM ${db_name}.updates WHERE state='MODULE'" 2>/dev/null || echo 0
}
```

**Replacement Examples:**
```bash
# OLD:
if [ -f "$RESTORE_SUCCESS_MARKER" ]; then
    echo "✅ Backup restoration completed successfully"
    exit 0
fi

# NEW:
if is_database_initialized "acore_world"; then
    local last_update
    last_update=$(get_last_update_timestamp "acore_world")
    echo "✅ Database initialized (last update: $last_update)"
    exit 0
fi
```

**Total Impact:**
- Files Modified: 1
- Code Change: +30 lines, -10 lines (marker logic)
- Complexity: Low-Medium

---

#### B3: Add Database Schema Version Checking

**New Files to Create:**

1. **`scripts/bash/check-schema-version.sh`** (NEW)
   - **Purpose:** Check and report database schema version
   - **Functions:**
     - `get_schema_version()` - Query version from DB
     - `compare_versions()` - Version comparison logic
     - `warn_version_mismatch()` - Alert on incompatibility
   - **Estimated Lines:** ~120 lines

**Files to Modify:**

2. **`scripts/bash/db-import-conditional.sh`**
   - Add version check before restore
   - Lines to add: ~15 lines

**Total Impact:**
- Files Created: 1
- Files Modified: 1
- Code Change: +135 lines
- Complexity: Medium

---

#### B4: Implement Database Health Check Script

**New Files to Create:**

1. **`scripts/bash/db-health-check.sh`** (NEW) - **Quick Win!**
   - **Purpose:** Comprehensive database health reporting
   - **Functions:**
     - `check_auth_db()` - Auth database status
     - `check_world_db()` - World database status
     - `check_characters_db()` - Characters database status
     - `check_module_updates()` - Module SQL status
     - `show_database_sizes()` - Storage usage
     - `list_pending_updates()` - Show pending SQL
     - `generate_health_report()` - Formatted output
   - **Estimated Lines:** ~250 lines

**Example Output:**
```
🏥 AZEROTHCORE DATABASE HEALTH CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Database Status
  ✅ Auth DB (acore_auth)
     - Updates: 45 applied
     - Last update: 2025-01-26 14:30:22
     - Size: 12.3 MB

  ✅ World DB (acore_world)
     - Updates: 1,234 applied (15 module)
     - Last update: 2025-01-26 14:32:15
     - Size: 2.1 GB

  ✅ Characters DB (acore_characters)
     - Updates: 89 applied
     - Last update: 2025-01-26 14:31:05
     - Characters: 145 (5 active today)
     - Size: 180.5 MB

📦 Module Updates
  ✅ mod-aoe-loot: 2 updates applied
  ✅ mod-learn-spells: 1 update applied
  ✅ mod-playerbots: 12 updates applied

⚠️  Pending Updates
  - db_world/2025_01_27_00.sql (waiting)
  - db_world/2025_01_27_01.sql (waiting)

💾 Total Storage: 2.29 GB
🔄 Last backup: 2 hours ago
```

**Total Impact:**
- Files Created: 1
- Code Change: +250 lines
- Complexity: Low-Medium
- **User Value: HIGH** (immediate utility)

---

### Category C: Playerbots Database Integration

#### C1: Integrate Playerbots into dbimport

**Files to Modify:**

1. **`scripts/bash/db-import-conditional.sh`** (340 lines)
   - **Changes:** Update dbimport.conf generation (lines 310-327)
   - **Current:** Only has Login, World, Character DBs
   - **Add:** PlayerbotsDatabaseInfo line
   - **Update:** `Updates.EnableDatabases = 15` (was 7)

**Code Change:**
```bash
# OLD (line 310-318):
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
Updates.EnableDatabases = 7
Updates.AutoSetup = 1
...
EOF

# NEW:
cat > /azerothcore/env/dist/etc/dbimport.conf <<EOF
LoginDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
PlayerbotsDatabaseInfo = "${CONTAINER_MYSQL};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}"
Updates.EnableDatabases = 15
Updates.AutoSetup = 1
...
EOF
```

2. **`scripts/bash/auto-post-install.sh`** (190 lines)
   - **Changes:** Update config file generation
   - Add PlayerbotsDatabaseInfo to worldserver.conf (if not using includes)
   - Lines to change: ~5 lines

**Total Impact:**
- Files Modified: 2
- Code Change: +5 lines
- Complexity: Low

---

#### C2: Remove Custom Playerbots SQL Handling

**Files to Modify:**

1. **`scripts/bash/manage-modules-sql.sh`** (381 lines)
   - **Remove:**
     - `playerbots_table_exists()` function (lines 74-79)
     - `render_sql_file_for_execution()` playerbots logic (lines 16-46)
     - Playerbots conditional checks in `run_custom_sql_group()` (lines 93-98)
   - **Lines to Remove:** ~35 lines

**Total Impact:**
- Files Modified: 1
- Code Change: -35 lines
- Complexity: Low
- **Depends on:** C1 must be completed first

---

### Category D: Configuration Management

#### D1: Use AzerothCore's Config Include System

**Files to Modify:**

1. **`scripts/bash/auto-post-install.sh`** (190 lines)
   - **Current:** Uses `sed` to modify config files directly
   - **Changes:**
     - Create `conf.d/` directory structure
     - Generate override files instead of modifying base configs
     - Update config references to use includes
   - **Lines to Change:** ~80 lines (config update section)
   - **Lines to Add:** ~40 lines (include generation)

**New Directory Structure:**
```
storage/config/
├── conf.d/
│   ├── database.conf (generated)
│   ├── environment.conf (generated)
│   └── overrides.conf (user edits)
├── authserver.conf (pristine, includes conf.d/*)
└── worldserver.conf (pristine, includes conf.d/*)
```

**New Functions:**
```bash
generate_database_config() {
    local conf_dir="/azerothcore/config/conf.d"
    mkdir -p "$conf_dir"

    cat > "$conf_dir/database.conf" <<EOF
# Auto-generated database configuration
# DO NOT EDIT - Generated from environment variables

LoginDatabaseInfo = "${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_AUTH_NAME}"
WorldDatabaseInfo = "${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_WORLD_NAME}"
CharacterDatabaseInfo = "${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_CHARACTERS_NAME}"
PlayerbotsDatabaseInfo = "${MYSQL_HOST};${MYSQL_PORT};${MYSQL_USER};${MYSQL_ROOT_PASSWORD};${DB_PLAYERBOTS_NAME}"
EOF
}

generate_environment_config() {
    # Similar for other environment-specific settings
}
```

**Total Impact:**
- Files Modified: 1
- Code Change: +40 lines, -20 lines (sed replacements)
- Complexity: Medium
- **Benefit:** Cleaner, more maintainable config management

---

#### D2: Environment Variable Based Configuration

**New Files to Create:**

1. **`scripts/bash/generate-config.sh`** (NEW)
   - **Purpose:** Generate all config files from environment
   - **Functions:**
     - `template_substitute()` - Replace variables in templates
     - `validate_config()` - Check required values
     - `generate_all_configs()` - Orchestrate generation
   - **Estimated Lines:** ~180 lines

**Template Files:**
```
config/templates/
├── authserver.conf.template
├── worldserver.conf.template
└── dbimport.conf.template
```

**Total Impact:**
- Files Created: 1 + templates
- Code Change: +180 lines + templates
- Complexity: Medium
- **Depends on:** D1

---

### Category E: Backup Enhancements

#### E1: Create Backup Status Dashboard

**New Files to Create:**

1. **`scripts/bash/backup-status.sh`** (NEW) - **Quick Win!**
   - **Purpose:** Display backup system status
   - **Functions:**
     - `show_last_backups()` - Recent backup times
     - `show_backup_schedule()` - Next scheduled backups
     - `show_storage_usage()` - Backup disk usage
     - `show_backup_trends()` - Size over time
     - `list_available_backups()` - All backups with ages
   - **Estimated Lines:** ~300 lines

**Total Impact:**
- Files Created: 1
- Code Change: +300 lines
- Complexity: Medium
- **User Value: HIGH**

---

#### E2: Add Backup Verification Job

**Files to Modify:**

1. **`scripts/bash/backup-scheduler.sh`** (225 lines)
   - Add verification job after backup creation
   - Lines to add: ~30 lines

**New Files:**

2. **`scripts/bash/verify-backup-integrity.sh`** (NEW)
   - Test restore to temporary database
   - Verify SQL can be parsed
   - Check for corruption
   - Estimated lines: ~200 lines

**Total Impact:**
- Files Created: 1
- Files Modified: 1
- Code Change: +230 lines
- Complexity: Medium-High

---

#### E3: Incremental Backup Support

**Files to Modify:**

1. **`scripts/bash/backup-scheduler.sh`** (225 lines)
   - Add incremental backup mode
   - Binary log management
   - Lines to add: ~150 lines

**Total Impact:**
- Files Modified: 1
- Code Change: +150 lines
- Complexity: High (requires MySQL binary log setup)

---

#### E4: Weekly/Monthly Backup Tiers

**Files to Modify:**

1. **`scripts/bash/backup-scheduler.sh`** (225 lines)
   - Add weekly/monthly scheduling
   - Extended retention logic
   - Lines to add: ~80 lines

**Total Impact:**
- Files Modified: 1
- Code Change: +80 lines
- Complexity: Medium

---

### Category F: Documentation & Tooling

#### F1: Create Database Management Guide

**New Files to Create:**

1. **`docs/DATABASE_MANAGEMENT.md`** (NEW) - **Quick Win!**
   - Backup/restore procedures
   - Module SQL installation
   - Troubleshooting guide
   - Migration scenarios
   - Estimated lines: ~500 lines (markdown)

**Total Impact:**
- Files Created: 1
- **User Value: HIGH**
- Complexity: Low (documentation)

---

#### F2: Add Migration Helper Script

**New Files to Create:**

1. **`scripts/bash/migrate-database.sh`** (NEW)
   - Schema version upgrades
   - Pre-migration backup
   - Post-migration verification
   - Estimated lines: ~250 lines

**Total Impact:**
- Files Created: 1
- Code Change: +250 lines
- Complexity: Medium
- **Depends on:** B3 (schema version checking)

---

## IMPLEMENTATION PHASES WITH FILE CHANGES

### Phase 1: Foundation (Days 1-3)

**Goal:** Refactor SQL management, add verification, integrate playerbots

**Files to Create:**
- `scripts/bash/stage-module-sql.sh` (150 lines)
- `scripts/bash/verify-sql-updates.sh` (100 lines)

**Files to Modify:**
- `scripts/bash/manage-modules-sql.sh` (381 → 181 lines, -200)
- `scripts/bash/manage-modules.sh` (616 → 646 lines, +30)
- `scripts/python/modules.py` (546 → 586 lines, +40)
- `scripts/bash/db-import-conditional.sh` (340 → 405 lines, +65)
- `scripts/bash/auto-post-install.sh` (190 → 195 lines, +5)

**Total Code Change:** +250 new, -200 removed = +50 net
**Files Created:** 2
**Files Modified:** 5

---

### Phase 2: Verification & Monitoring (Days 4-5)

**Goal:** Add health checks, state tracking, status dashboard

**Files to Create:**
- `scripts/bash/db-health-check.sh` (250 lines) ✨ Quick Win
- `scripts/bash/backup-status.sh` (300 lines) ✨ Quick Win

**Files to Modify:**
- `scripts/bash/db-import-conditional.sh` (405 → 435 lines, +30)
- `scripts/bash/manage-modules.sh` (646 → 666 lines, +20)

**Total Code Change:** +600 new, +50 modified = +650 net
**Files Created:** 2
**Files Modified:** 2

---

### Phase 3: Cleanup (Day 6)

**Goal:** Remove technical debt, simplify config management

**Files to Modify:**
- `scripts/bash/manage-modules-sql.sh` (181 → 146 lines, -35)
- `scripts/bash/auto-post-install.sh` (195 → 215 lines, +20)

**Total Code Change:** -15 net
**Files Modified:** 2

---

### Phase 4: Enhancements (Days 7-9)

**Goal:** Advanced features, version checking, rollback support

**Files to Create:**
- `scripts/bash/check-schema-version.sh` (120 lines)
- `scripts/bash/rollback-module-sql.sh` (200 lines)
- `scripts/bash/verify-backup-integrity.sh` (200 lines)
- `docs/DATABASE_MANAGEMENT.md` (500 lines markdown) ✨ Quick Win

**Files to Modify:**
- `scripts/bash/db-import-conditional.sh` (435 → 450 lines, +15)
- `scripts/bash/backup-scheduler.sh` (225 → 255 lines, +30)

**Total Code Change:** +1065 net
**Files Created:** 4
**Files Modified:** 2

---

### Phase 5: Advanced (Days 10-12)

**Goal:** Enterprise features

**Files to Create:**
- `scripts/bash/migrate-database.sh` (250 lines)
- `scripts/bash/generate-config.sh` (180 lines)
- Config templates (3 files, ~200 lines total)

**Files to Modify:**
- `scripts/bash/backup-scheduler.sh` (255 → 485 lines, +230)

**Total Code Change:** +860 net
**Files Created:** 5
**Files Modified:** 1

---

## SUMMARY STATISTICS

### Code Changes by Phase

| Phase | New Files | Modified Files | Lines Added | Lines Removed | Net Change |
|-------|-----------|----------------|-------------|---------------|------------|
| 1     | 2         | 5              | 250         | 200           | +50        |
| 2     | 2         | 2              | 650         | 0             | +650       |
| 3     | 0         | 2              | 20          | 35            | -15        |
| 4     | 4         | 2              | 1065        | 0             | +1065      |
| 5     | 5         | 1              | 860         | 0             | +860       |
| **Total** | **13** | **12** | **2845** | **235** | **+2610** |

### Impact by File

**Most Modified Files:**
1. `scripts/bash/db-import-conditional.sh` - Modified in 4 phases (+110 lines)
2. `scripts/bash/backup-scheduler.sh` - Modified in 3 phases (+260 lines)
3. `scripts/bash/manage-modules-sql.sh` - Modified in 2 phases (-235 lines!)
4. `scripts/bash/manage-modules.sh` - Modified in 2 phases (+50 lines)
5. `scripts/bash/auto-post-install.sh` - Modified in 2 phases (+25 lines)

**Largest New Files:**
1. `docs/DATABASE_MANAGEMENT.md` - 500 lines (documentation)
2. `scripts/bash/backup-status.sh` - 300 lines
3. `scripts/bash/db-health-check.sh` - 250 lines
4. `scripts/bash/migrate-database.sh` - 250 lines
5. `scripts/bash/rollback-module-sql.sh` - 200 lines

---

## RISK ASSESSMENT

### High Risk Changes
- **`manage-modules-sql.sh` refactor** - Complete rewrite of SQL execution
  - Mitigation: Comprehensive testing, rollback plan
  - Testing: Install 5+ modules, verify all SQL applied

- **dbimport.conf playerbots integration** - Could break existing setups
  - Mitigation: Conditional logic, backwards compatibility
  - Testing: Fresh install + migration from existing

### Medium Risk Changes
- **Post-restore verification** - Could slow down startup
  - Mitigation: Make verification optional via env var
  - Testing: Test with various backup sizes

- **Config include system** - Changes config structure
  - Mitigation: Keep old method as fallback
  - Testing: Verify all config values applied correctly

### Low Risk Changes
- Health check script (read-only)
- Backup status dashboard (read-only)
- Documentation (no code impact)

---

## TESTING STRATEGY

### Phase 1 Testing
1. **Module SQL Refactor:**
   - [ ] Fresh install with 0 modules
   - [ ] Install single module with SQL
   - [ ] Install 5+ modules simultaneously
   - [ ] Verify SQL in `updates` table
   - [ ] Check for duplicate executions
   - [ ] Test module with playerbots SQL

2. **Post-Restore Verification:**
   - [ ] Restore from fresh backup
   - [ ] Restore from 1-week-old backup
   - [ ] Restore from 1-month-old backup
   - [ ] Test with missing SQL updates
   - [ ] Verify auto-update applies correctly

3. **Playerbots Integration:**
   - [ ] Fresh install with playerbots enabled
   - [ ] Migration with existing playerbots DB
   - [ ] Verify playerbots updates tracked separately

### Phase 2 Testing
1. **Health Check:**
   - [ ] Run on healthy database
   - [ ] Run on database with missing updates
   - [ ] Run on database with zero updates
   - [ ] Test all output formatting

2. **Backup Status:**
   - [ ] Check with no backups
   - [ ] Check with only hourly backups
   - [ ] Check with full backup history
   - [ ] Verify size calculations

### Integration Testing
- [ ] Complete deployment flow (fresh install)
- [ ] Migration from previous version
- [ ] Module add/remove cycle
- [ ] Backup/restore cycle
- [ ] Performance testing (large databases)

---

## ROLLBACK PROCEDURES

### Phase 1 Rollback
If module SQL refactor fails:
1. Revert `manage-modules-sql.sh` to original
2. Revert `manage-modules.sh` SQL sections
3. Remove staged SQL files from AzerothCore structure
4. Restore module SQL to `/tmp/scripts/sql/custom/`
5. Re-run module installation

### Phase 2 Rollback
If verification causes issues:
1. Set `SKIP_DB_VERIFICATION=1` env var
2. Revert db-import-conditional.sh changes
3. Restore original marker file logic

### Emergency Rollback (All Phases)
1. Git revert to tag before changes
2. Restore database from backup
3. Re-run deployment without new features
4. Document failure scenario

---

## SUCCESS CRITERIA

### Phase 1 Success
- ✅ All module SQL applied via AzerothCore's updater
- ✅ Zero manual SQL execution in module installation
- ✅ All SQL tracked in `updates` table with correct hashes
- ✅ Playerbots database in dbimport configuration
- ✅ Post-restore verification catches missing updates
- ✅ No regression in existing functionality
- ✅ Code reduction: -150+ lines

### Phase 2 Success
- ✅ Health check script provides accurate status
- ✅ Backup dashboard shows useful information
- ✅ State tracking via database (not files)
- ✅ User value: Quick troubleshooting tools available

### Phase 3 Success
- ✅ Playerbots SQL handling simplified
- ✅ Config management cleaner (no sed hacks)
- ✅ Code quality improved
- ✅ Maintenance burden reduced

### Overall Success
- ✅ Database management leverages AzerothCore features
- ✅ Less custom code to maintain
- ✅ Better observability and debugging
- ✅ Improved reliability and consistency
- ✅ Clear upgrade path for users
- ✅ Comprehensive documentation

---

## NEXT STEPS

1. **Review this implementation map** with stakeholders
2. **Set up test environment** for Phase 1
3. **Create feature branch** for development
4. **Begin Phase 1 implementation:**
   - Start with `stage-module-sql.sh` (new file, low risk)
   - Then modify `manage-modules.sh` (add staging calls)
   - Finally refactor `manage-modules-sql.sh` (high impact)
5. **Test thoroughly** before moving to Phase 2
6. **Document changes** in CHANGELOG
7. **Create migration guide** for existing users

---

**End of Implementation Map**

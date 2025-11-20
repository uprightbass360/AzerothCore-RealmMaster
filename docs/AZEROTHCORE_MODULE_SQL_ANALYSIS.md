# AzerothCore Module SQL Integration - Official Documentation Analysis

**Date:** 2025-11-16
**Purpose:** Compare official AzerothCore module documentation with our implementation

---

## Official AzerothCore Module Installation Process

### According to https://www.azerothcore.org/wiki/installing-a-module

**Standard Installation Steps:**

1. **Find Module** - Browse AzerothCore Catalogue
2. **Clone/Download** - Add module to `/modules/` directory
   - ⚠️ **Critical:** Remove `-master` suffix from directory name
3. **Reconfigure CMake** - Regenerate build files
   - Verify module appears in CMake logs under "Modules configuration (static)"
4. **Recompile Core** - Build with module included
5. **Automatic SQL Processing** - "Your Worldserver will automatically run any SQL Queries provided by the Modules"
6. **Check README** - Review for manual configuration steps

---

## SQL Directory Structure Standards

### Official Structure (from AzerothCore core)

```
data/sql/
├── create/      # Database create/drop files
├── base/        # Latest squashed update files
├── updates/     # Incremental update files
│   ├── db_world/
│   ├── db_characters/
│   └── db_auth/
└── custom/      # Custom user modifications
```

### Module SQL Structure

According to documentation:
- Modules "can create base, updates and custom sql that will be automatically loaded in our db_assembler"
- **Status:** Documentation marked as "work in progress..."
- **Reference:** Check skeleton-module template for examples

---

## Directory Naming Conventions

### Research Findings

From GitHub PR #16157 (closed without merge):

**Two competing conventions exist:**

1. **`data/sql/db-world`** - Official standard (hyphen naming)
   - Used by: skeleton-module (recommended template)
   - AzerothCore core uses: `data/sql/updates/db_world` (underscore in core, hyphen in modules)

2. **`sql/world`** - Legacy convention (no db- prefix)
   - Used by: mod-eluna, mod-ah-bot, many older modules
   - **Not officially supported** - PR to support this was closed

**Community Decision:** Favor standardization on `data/sql/db-world` over backward compatibility

---

## DBUpdater Behavior

### Automatic Updates

**Configuration:** `worldserver.conf`
```conf
AC_UPDATES_ENABLE_DATABASES = 7  # Enable all database autoupdates
```

**How it works:**
1. Each database (auth, characters, world) has `version_db_xxxx` table
2. Tracks last applied update in format `YYYY_MM_DD_XX`
3. Worldserver scans for new updates on startup
4. Automatically applies SQL files in chronological order

### File Naming Convention

**Required format:** `YYYY_MM_DD_XX.sql`

**Examples:**
- `2025_11_16_00.sql`
- `2025_11_16_01_module_name_description.sql`

---

## Critical Discovery: Module SQL Scanning

### From our testing and official docs research:

**AzerothCore's DBUpdater DOES NOT scan module directories automatically!**

| What Official Docs Say | Reality |
|------------------------|---------|
| "Worldserver will automatically run any SQL Queries provided by the Modules" | ✅ TRUE - but only from CORE updates directory |
| SQL files in modules are "automatically loaded" | ❌ FALSE - modules must stage SQL to core directory |

**The Truth:**
- DBUpdater scans: `/azerothcore/data/sql/updates/db_world/` (core directory)
- DBUpdater does NOT scan: `/azerothcore/modules/*/data/sql/` (module directories)
- Modules compiled into the core have their SQL "baked in" during build
- **Pre-built images require runtime staging** (our discovery!)

---

## Our Implementation vs. Official Process

### Official Process (Build from Source)

```
1. Clone module to /modules/
2. Run CMake (detects module)
3. Compile core (module SQL gets integrated into build)
4. Deploy compiled binary
5. DBUpdater processes SQL from core updates directory
```

**Result:** Module SQL files get copied into core directory structure during build

### Our Process (Pre-built Docker Images)

```
1. Download pre-built image (modules already compiled in)
2. Mount module repositories at runtime
3. ❌ Module SQL NOT in core updates directory
4. ✅ Runtime staging copies SQL to core updates directory
5. DBUpdater processes SQL from core updates directory
```

**Result:** Runtime staging replicates what build-time would have done

---

## Gap Analysis

### What We're Missing (vs. Standard Installation)

| Feature | Official Process | Our Implementation | Status |
|---------|------------------|-------------------|--------|
| Module C++ code | Compiled into binary | ✅ Pre-compiled in image | ✅ COMPLETE |
| Module SQL discovery | CMake build process | ✅ Runtime scanning | ✅ COMPLETE |
| SQL file validation | Build warnings | ✅ Empty + security checks | ✅ ENHANCED |
| SQL naming format | Developer responsibility | ✅ Automatic timestamping | ✅ ENHANCED |
| SQL to core directory | Build-time copy | ✅ Runtime staging | ✅ COMPLETE |
| DBUpdater processing | Worldserver autoupdate | ✅ Worldserver autoupdate | ✅ COMPLETE |
| README instructions | Manual review needed | ⚠️ Not automated | ⚠️ GAP |
| Module .conf files | Manual deployment | ✅ Automated sync | ✅ COMPLETE |

### Identified Gaps

#### 1. README Processing
**Official:** "Always check the README file of the module to see if any manual steps are needed"
**Our Status:** Manual - users must check README themselves
**Impact:** LOW - Most modules don't require manual steps beyond SQL
**Recommendation:** Document in user guide

#### 2. Module Verification Command
**Official:** "Use `.server debug` command to verify all loaded modules"
**Our Status:** Not documented in deployment
**Impact:** LOW - Informational only
**Recommendation:** Add to post-deployment checklist

#### 3. CMake Module Detection
**Official:** Check CMake logs for "Modules configuration (static)"
**Our Status:** Not applicable - using pre-built images
**Impact:** NONE - Only relevant for custom builds
**Recommendation:** N/A

---

## SQL Directory Scanning - Current vs. Potential

### What We Currently Scan

```bash
for db_type in db-world db-characters db-auth; do
  # Scans: /azerothcore/modules/*/data/sql/db-world/*.sql
  # Direct directory only
done
```

**Coverage:**
- ✅ Standard location: `data/sql/db-world/`
- ✅ Hyphen naming convention
- ❌ Underscore variant: `data/sql/db_world/`
- ❌ Legacy locations: `sql/world/`
- ❌ Subdirectories: `data/sql/base/`, `data/sql/updates/`
- ❌ Custom directory: `data/sql/custom/`

### Should We Expand?

**Arguments FOR expanding scan:**
- Some modules use legacy `sql/world/` structure
- Some modules organize SQL in `base/` and `updates/` subdirectories
- Better compatibility with diverse module authors

**Arguments AGAINST expanding:**
- Official AzerothCore rejected multi-path support (PR #16157 closed)
- Community prefers standardization over compatibility
- Adds complexity for edge cases
- May encourage non-standard module structure

**Recommendation:** **Stay with current implementation**
- Official standard is `data/sql/db-world/`
- Non-compliant modules should be updated by authors
- Our implementation matches official recommendation
- Document expected structure in user guide

---

## Module Configuration Files

### Standard Module Configuration

Modules can include:
- **Source:** `conf/*.conf.dist` files
- **Deployment:** Copied to worldserver config directory
- **Our Implementation:** ✅ `manage-modules.sh` handles this

---

## Comparison with db_assembler

### What is db_assembler?

**Official tool** for database setup during installation
- Runs during initial setup
- Processes base/ and updates/ directories
- Creates fresh database structure

### Our Runtime Staging vs. db_assembler

| Feature | db_assembler | Our Runtime Staging |
|---------|--------------|-------------------|
| When runs | Installation time | Every deployment |
| Purpose | Initial DB setup | Module SQL updates |
| Processes | base/ + updates/ | Direct SQL files |
| Target | Fresh databases | Existing databases |
| Module awareness | Build-time | Runtime |

**Key Difference:** We handle the "module SQL updates" part that db_assembler doesn't cover for pre-built images

---

## Validation Against Official Standards

### ✅ What We Do Correctly

1. **SQL File Naming:** Automatic timestamp prefixing matches AzerothCore format
2. **Directory Structure:** Scanning `data/sql/db-world/` matches official standard
3. **Database Types:** Support db-world, db-characters, db-auth (official set)
4. **Autoupdate Integration:** Files staged to location DBUpdater expects
5. **Module Prefix:** Adding `MODULE_` prefix prevents conflicts with core updates

### ✅ What We Do Better Than Standard

1. **SQL Validation:** Empty file check + security scanning (not in standard process)
2. **Error Reporting:** Detailed success/skip/fail counts
3. **Automatic Timestamping:** No manual naming required
4. **Conflict Prevention:** MODULE_ prefix ensures safe identification

### ⚠️ Potential Concerns

1. **Multiple Deployments:**
   **Issue:** Re-running deployment could create duplicate SQL files
   **Mitigation:** DBUpdater tracks applied updates in `version_db_xxxx` table
   **Result:** Duplicates are harmless - already-applied updates skipped

2. **Manual SQL Files:**
   **Issue:** If user manually adds SQL to module directory
   **Behavior:** Will be staged on next deployment
   **Result:** Expected behavior - matches official "custom SQL" workflow

3. **Module Updates:**
   **Issue:** Git pull adds new SQL to module
   **Behavior:** New files staged on next deployment
   **Result:** Expected behavior - updates applied automatically

---

## Missing Official Features

### Not Implemented (Intentional)

1. **db_assembler integration** - Not needed for pre-built images
2. **CMake module detection** - Not applicable to Docker deployment
3. **Build-time SQL staging** - Replaced by runtime staging
4. **Manual SQL execution** - Replaced by DBUpdater autoupdate

### Not Implemented (Gaps)

1. **README parsing** - Manual review still required
2. **Module dependency checking** - Not validated automatically
3. **SQL rollback support** - No automatic downgrade path
4. **Version conflict detection** - Relies on DBUpdater

---

## Recommendations

### Keep As-Is ✅

1. **Current directory scanning** - Matches official standard
2. **Runtime staging approach** - Necessary for pre-built images
3. **SQL validation** - Better than standard
4. **Automatic timestamping** - Convenience improvement

### Document for Users 📝

1. **Expected module structure** - Explain `data/sql/db-world/` requirement
2. **Deployment behavior** - Clarify when SQL is staged and applied
3. **README review** - Remind users to check module documentation
4. **Verification steps** - Add `.server debug` command to post-deploy checklist

### Future Enhancements (Optional) 🔮

1. **README scanner** - Parse common instruction formats
2. **SQL dependency detection** - Warn about missing prerequisites
3. **Module health check** - Verify SQL was applied successfully
4. **Staging log** - Persistent record of staged files

---

## Conclusion

### Our Implementation is Sound ✅

**Alignment with Official Process:**
- ✅ Matches official SQL directory structure
- ✅ Integrates with official DBUpdater
- ✅ Follows official naming conventions
- ✅ Supports official database types

**Advantages Over Standard Build Process:**
- ✅ Works with pre-built Docker images
- ✅ Better SQL validation and security
- ✅ Automatic file naming
- ✅ Clear error reporting

**No Critical Gaps Identified:**
- All essential functionality present
- Missing features are either:
  - Not applicable to Docker deployment
  - Manual steps (README review)
  - Nice-to-have enhancements

### Validation Complete

Our runtime SQL staging implementation successfully replicates what the official build process does, while adding improvements for Docker-based deployments. No changes required to match official standards.

---

## References

1. [Installing a Module - Official Docs](https://www.azerothcore.org/wiki/installing-a-module)
2. [Create a Module - Official Docs](https://www.azerothcore.org/wiki/create-a-module)
3. [SQL Directory Structure](https://www.azerothcore.org/wiki/sql-directory)
4. [Database Updates](https://www.azerothcore.org/wiki/database-keeping-the-server-up-to-date)
5. [Skeleton Module Template](https://github.com/azerothcore/skeleton-module)
6. [PR #16157 - SQL Path Support](https://github.com/azerothcore/azerothcore-wotlk/pull/16157)
7. [Issue #2592 - db_assembler Auto-discovery](https://github.com/azerothcore/azerothcore-wotlk/issues/2592)

# AzerothCore Deployment Issues - Todo List

## Deployment Summary & Status

### ✅ **Completed:**
- [x] Find and execute wizard deployment script
- [x] Configure deployment for 13 module version (suggested preset: 8 modules)
- [x] Monitor deployment process for warnings/errors
- [x] Report any issues found for bug fixing

### ✅ **Critical Issues RESOLVED:**

#### 1. **Database Schema Missing** ✅ **FIXED**
- **Issue**: `[1146] Table 'acore_world.charsections_dbc' doesn't exist`
- **Resolution**:
  - [x] Added missing `emotetextsound_dbc.sql` to source project
  - [x] Imported all DBC tables to database (111 tables)
  - [x] Worldserver now starts successfully
  - [x] Created fix in playerbot source repository

#### 2. **Container Image Compatibility Issues** ✅ **FIXED**
- **Issue**: Multiple containers failing with exit code 127
- **Resolution**:
  - [x] Fixed client-data container with multi-OS package manager detection
  - [x] Client data now downloads successfully (15GB)
  - [x] Modules container working correctly
  - [x] Created backward-compatible Alpine/Ubuntu scripts

#### 3. **Environment Variable Configuration** ✅ **FIXED**
- **Issue**: Multiple undefined variables in modules deployment
- **Resolution**:
  - [x] Wizard generates proper custom environment files
  - [x] All 8 suggested modules configured correctly
  - [x] Variable substitution working properly

#### 4. **Network/Script Download Failures** ✅ **FIXED**
- **Issue**: Module management scripts failing to download
- **Resolution**:
  - [x] Network connectivity working
  - [x] Scripts download successfully
  - [x] Multi-OS compatibility implemented

### ⚠️ **Remaining Issues:**

#### 5. **Backup Container Restart Loop** (ACTIVE)
- **Issue**: `ac-backup` container restarting with exit code 127
- **Status**: Under investigation
- **Action**:
  - [ ] Check backup container logs
  - [ ] Verify backup script compatibility
  - [ ] Fix container startup issues

### 📋 **Next Steps:**
1. **Immediate**: Check `ac-db-import` container completion status
2. **Priority**: Fix database schema issues to enable worldserver startup
3. **Follow-up**: Address container image compatibility for full deployment
4. **Testing**: Verify all services start and communicate properly

### 🛠️ **Commands Used:**
```bash
# Wizard execution
echo -e "1\n8215\n3784\n7778\n64306\nazerothcore123\n3\n6\n09\nUTC\n1\ny" | ./scripts/setup-server.sh

# Database deployment
docker compose --env-file docker-compose-azerothcore-database-custom.env -f docker-compose-azerothcore-database.yml up -d

# Services deployment
docker compose --env-file docker-compose-azerothcore-services-custom.env -f docker-compose-azerothcore-services.yml up -d

# Modules deployment
docker compose --env-file docker-compose-azerothcore-modules-custom.env -f docker-compose-azerothcore-modules.yml up -d
```

### 🔍 **Diagnostic Commands:**
```bash
# Check container status
docker ps -a

# Check specific logs
docker logs ac-worldserver
docker logs ac-db-import
docker logs ac-client-data
docker logs ac-modules

# Check database connectivity
docker exec ac-mysql mysql -u root -p -e "SHOW DATABASES;"
```

## 🔍 **Root Cause Analysis Found:**

### **Database Schema Version Mismatch**
- Database has 298 tables imported successfully
- Missing specific table: `charsections_dbc` (and possibly other DBC tables)
- Playerbot database schema appears incomplete or outdated
- Worldserver expects newer/different schema than what was imported

### **Container Image Issues Identified**
1. **client-data container**: Ubuntu-based but script tries to use Alpine `apk` package manager
2. **modules container**: curl download failures - network/permission issues
3. **Base images**: uprightbass360 images use Ubuntu 22.04 base, scripts expect Alpine

### **Immediate Fixes Needed**
- [ ] Update database schema to include missing DBC tables
- [ ] Fix client-data container to use `apt` instead of `apk`
- [ ] Resolve module script download issues
- [ ] Verify schema compatibility between playerbot build and database

## 🆕 **UPDATES - Issues Resolved:**

### ✅ **Major Fixes Completed:**
1. **Database Schema Issues** ✅ **RESOLVED**
   - Added missing `emotetextsound_dbc.sql` to source project
   - Imported all DBC tables - worldserver now starts successfully
   - Worldserver status: `Up (healthy)` with Eluna scripts loaded

2. **Container Script Compatibility** ✅ **RESOLVED**
   - Fixed client-data container with multi-OS package manager detection
   - Client data downloads working (15GB extracted successfully)
   - Updated docker-compose with Alpine/Ubuntu compatibility

3. **Source Project Improvements** ✅ **COMPLETED**
   - Updated cleanup script for current deployment structure
   - Ready to push fixes back to azerothcore-wotlk-playerbots repository

### ⚠️ **Active Issue Identified:**
- **Backup Container**: `ac-backup` in restart loop with exit code 127 - **INVESTIGATING**

---
**Status**: **MAJOR SUCCESS** ✅ - Core server functional, investigating remaining backup issue.
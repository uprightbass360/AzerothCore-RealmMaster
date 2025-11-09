# Changelog

## [2025-11-09] - Recent Changes

### ✨ Features

#### Backup System Enhancements
- **Manual Backup Support**: Added `manual-backup.sh` script (92 lines) enabling on-demand database backups through the ac-backup container
- **Backup Permission Fixes**: Resolved Docker volume permission issues with backup operations
- **Container User Configuration**: Backup operations now run as proper container user to avoid permission conflicts

#### Remote Deployment
- **Auto Deploy Option**: Added remote auto-deployment functionality to `deploy.sh` (36 additional lines) for automated server provisioning

#### Configuration Management System
- **Database/Config Import**: Major new feature with 1,405+ lines of code across 15 files
  - Added `apply-config.py` (323 lines) for dynamic server configuration
  - Created `configure-server.sh` (162 lines) for server setup automation
  - Implemented `import-database-files.sh` (68 lines) for database initialization
  - Added `parse-config-presets.py` (92 lines) for configuration templating
- **Configuration Presets**: 5 new server preset configurations
  - `blizzlike.conf` - Authentic Blizzard-like experience
  - `casual-pve.conf` - Relaxed PvE gameplay
  - `fast-leveling.conf` - Accelerated character progression
  - `hardcore-pvp.conf` - Competitive PvP settings
  - `none.conf` - Minimal configuration baseline
- **Dynamic Server Overrides**: `server-overrides.conf` (134 lines) for customizable server parameters
- **Comprehensive Config Documentation**: `CONFIG_MANAGEMENT.md` (279 lines) detailing the entire configuration system

#### Infrastructure Improvements
- **MySQL Exposure Toggle**: Optional MySQL port exposure for external database access
- **Client Data Management**: Automatic client data detection, download, and binding with version detection
- **Dynamic Docker Overrides**: Flexible compose override system for modular container configurations
- **Module Profile System**: Structured module management with preset profiles

### 🏗️ Refactoring

#### Script Organization
- **Directory Restructure**: Reorganized all scripts into `scripts/bash/` and `scripts/python/` directories (40 files moved/modified)
- **Project Naming**: Added centralized project name management with `project_name.sh`
- **Module Manifest Rename**: Moved `modules.json` → `module-manifest.json` for clarity

### 🐛 Bug Fixes

#### Container Improvements
- **Client Data Container**: Enhanced with 7zip support, root access during extraction, and ownership fixes
- **Permission Resolution**: Fixed file ownership issues in client data extraction process
- **Path Updates**: Corrected deployment paths and script references after reorganization

### 📚 Documentation

#### Major Documentation Overhaul
- **Modular Documentation**: Split massive README into focused documents (1,500+ lines reorganized)
  - `docs/GETTING_STARTED.md` (467 lines) - Setup and initial configuration
  - `docs/MODULES.md` (264 lines) - Module management and customization
  - `docs/SCRIPTS.md` (404 lines) - Script reference and automation
  - `docs/ADVANCED.md` (207 lines) - Advanced configuration topics
  - `docs/TROUBLESHOOTING.md` (127 lines) - Common issues and solutions
- **README Streamlining**: Reduced main README from 1,200+ to focused overview
- **Script Documentation**: Updated script references and usage examples throughout

### 🔧 Technical Changes

#### Development Experience
- **Setup Enhancements**: Improved `setup.sh` with better error handling and configuration options (66 lines added)
- **Status Monitoring**: Enhanced `status.sh` with better container and service monitoring
- **Build Process**: Updated build scripts with new directory structure and module handling
- **Cleanup Operations**: Improved cleanup scripts with proper path handling

#### DevOps & Deployment
- **Remote Cleanup**: Enhanced remote server cleanup and temporary file management
- **Network Binding**: Improved container networking and port management
- **Import Folder**: Added dedicated import directory structure
- **Development Onboarding**: Streamlined developer setup process

---

### Migration Notes
- Scripts have moved from `scripts/` to `scripts/bash/` and `scripts/python/`
- Module configuration is now in `config/module-manifest.json`
- New environment variables added for MySQL exposure and client data management
- Configuration presets are available in `config/presets/`

### Breaking Changes
- Script paths have changed due to reorganization
- Module manifest file has been renamed
- Some environment variables have been added/modified

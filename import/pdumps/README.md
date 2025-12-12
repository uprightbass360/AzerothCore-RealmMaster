# Character PDump Import

This directory allows you to easily import character pdump files into your AzerothCore server.

## 📁 Directory Structure

```
import/pdumps/
├── README.md           # This file
├── *.pdump            # Place your character dump files here
├── *.sql              # SQL dump files also supported
├── configs/           # Optional per-file configuration
│   ├── character1.conf
│   └── character2.conf
├── examples/          # Example files and configurations
└── processed/         # Successfully imported files are moved here
```

## 🎮 Character Dump Import

### Quick Start

1. **Place your pdump files** in this directory:
   ```bash
   cp /path/to/mycharacter.pdump import/pdumps/
   ```

2. **Run the import script**:
   ```bash
   ./scripts/bash/import-pdumps.sh --password your_mysql_password --account target_account
   ```

3. **Login and play** - your characters are now available!

### Supported File Formats

- **`.pdump`** - Character dump files from AzerothCore `.pdump write` command
- **`.sql`** - SQL character dump files

### Configuration Options

#### Environment Variables (`.env`)
```bash
# Set default account for all imports
DEFAULT_IMPORT_ACCOUNT=testuser

# Database credentials (usually already set)
MYSQL_ROOT_PASSWORD=your_mysql_password
ACORE_DB_AUTH_NAME=acore_auth
ACORE_DB_CHARACTERS_NAME=acore_characters
```

#### Per-Character Configuration (`configs/filename.conf`)
Create a `.conf` file with the same name as your pdump file to specify custom import options:

**Example: `configs/mycharacter.conf`**
```ini
# Target account (required if not set globally)
account=testuser

# Rename character during import (optional)
name=NewCharacterName

# Force specific GUID (optional, auto-assigned if not specified)
guid=5000
```

### Command Line Usage

#### Import All Files
```bash
# Use environment settings
./scripts/bash/import-pdumps.sh

# Override settings
./scripts/bash/import-pdumps.sh --password mypass --account testuser
```

#### Import Single File
```bash
# Direct import with pdump-import.sh
./scripts/bash/pdump-import.sh --file character.pdump --account testuser --password mypass

# With character rename
./scripts/bash/pdump-import.sh --file oldchar.pdump --account newuser --name "NewName" --password mypass

# Validate before import (dry run)
./scripts/bash/pdump-import.sh --file character.pdump --account testuser --password mypass --dry-run
```

## 🛠️ Advanced Features

### Account Management
- **Account Validation**: Scripts automatically verify that target accounts exist
- **Account ID or Name**: You can use either account names or numeric IDs
- **Interactive Mode**: If no account is specified, you'll be prompted to enter one

### GUID Handling
- **Auto-Assignment**: Next available GUID is automatically assigned
- **Force GUID**: Use `--guid` parameter or config file to force specific GUID
- **Conflict Detection**: Import fails safely if GUID already exists

### Character Names
- **Validation**: Character names must follow WoW naming rules (2-12 letters)
- **Uniqueness**: Import fails if character name already exists on server
- **Renaming**: Use `--name` parameter or config file to rename during import

### Safety Features
- **Automatic Backup**: Characters database is backed up before each import
- **Server Management**: World server is safely stopped/restarted during import
- **Rollback Ready**: Backups are stored in `manual-backups/` directory
- **Dry Run**: Validate imports without actually importing

## 📋 Import Workflow

1. **Validation Phase**
   - Check file format and readability
   - Validate target account exists
   - Verify character name availability (if specified)
   - Check GUID conflicts

2. **Pre-Import Phase**
   - Create automatic database backup
   - Stop world server for safe import

3. **Processing Phase**
   - Process SQL file (update account references, GUID, name)
   - Import character data into database

4. **Post-Import Phase**
   - Restart world server
   - Verify import success
   - Move processed files to `processed/` directory

## 🚨 Important Notes

### Before You Import
- **Backup Your Database**: Always backup before importing characters
- **Account Required**: Target account must exist in your auth database
- **Unique Names**: Character names must be unique across the entire server
- **Server Downtime**: World server is briefly restarted during import

### PDump Limitations
The AzerothCore pdump system has some known limitations:
- **Guild Data**: Guild information is not included in pdump files
- **Module Data**: Some module-specific data (transmog, reagent bank) may not transfer
- **Version Compatibility**: Pdump files from different database versions may have issues

### Troubleshooting
- **"Account not found"**: Verify account exists in auth database
- **"Character name exists"**: Use `--name` to rename or choose different name
- **"GUID conflicts"**: Use `--guid` to force different GUID or let system auto-assign
- **"Database errors"**: Check that pdump file is compatible with your database version

## 📚 Examples

### Basic Import
```bash
# Place file and import
cp character.pdump import/pdumps/
./scripts/bash/import-pdumps.sh --password mypass --account testuser
```

### Batch Import with Configuration
```bash
# Set up multiple characters
cp char1.pdump import/pdumps/
cp char2.pdump import/pdumps/

# Configure individual characters
echo "account=user1" > import/pdumps/configs/char1.conf
echo "account=user2
name=RenamedChar" > import/pdumps/configs/char2.conf

# Import all
./scripts/bash/import-pdumps.sh --password mypass
```

### Single Character Import
```bash
./scripts/bash/pdump-import.sh \
  --file character.pdump \
  --account testuser \
  --name "MyNewCharacter" \
  --password mypass
```

## 🔗 Related Documentation

- [Database Management](../../docs/DATABASE_MANAGEMENT.md)
- [Backup System](../../docs/TROUBLESHOOTING.md#backup-system)
- [Getting Started Guide](../../docs/GETTING_STARTED.md)
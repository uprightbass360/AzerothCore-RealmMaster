# Database Import

Place your database backup files here for automatic import during deployment.

## Supported Imports
- `.sql` files (uncompressed SQL dumps)
- `.sql.gz` files (gzip compressed SQL dumps)
- **Full backup directories** (e.g., `ExportBackup_YYYYMMDD_HHMMSS/` containing multiple dumps)
- **Full backup archives** (`.tar`, `.tar.gz`, `.tgz`, `.zip`) that contain the files above

## How to Use

1. **Copy your backup files here:**
   ```bash
   cp my_auth_backup.sql.gz ./database-import/
   cp my_world_backup.sql.gz ./database-import/
   cp my_characters_backup.sql.gz ./database-import/
   # or drop an entire ExportBackup folder / archive
   cp -r ExportBackup_20241029_120000 ./database-import/
   cp ExportBackup_20241029_120000.tar.gz ./database-import/
   ```

2. **Run deployment:**
   ```bash
   ./deploy.sh
   ```

3. **Files are automatically copied to backup system** and imported during deployment

## File Naming
- Any filename works - the system will auto-detect database type by content
- Recommended naming: `auth.sql.gz`, `world.sql.gz`, `characters.sql.gz`
- Full backups keep their original directory/archive name so you can track multiple copies

## What Happens
- Individual `.sql`/`.sql.gz` files are copied to `storage/backups/daily/` with a timestamped name
- Full backup directories or archives are staged in `storage/backups/ImportBackup/`
- Database import system automatically restores the most recent matching backup
- Original files remain here for reference (archives are left untouched)

## Notes
- Only processed on first deployment (when databases don't exist)
- Files/directories are copied once; existing restored databases will skip import
- Empty folder is ignored - no files, no import

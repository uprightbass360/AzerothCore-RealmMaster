# Database Import

Place your database backup files here for automatic import during deployment.

## Supported Files
- `.sql` files (uncompressed SQL dumps)
- `.sql.gz` files (gzip compressed SQL dumps)

## How to Use

1. **Copy your backup files here:**
   ```bash
   cp my_auth_backup.sql.gz ./database-import/
   cp my_world_backup.sql.gz ./database-import/
   cp my_characters_backup.sql.gz ./database-import/
   ```

2. **Run deployment:**
   ```bash
   ./deploy.sh
   ```

3. **Files are automatically copied to backup system** and imported during deployment

## File Naming
- Any filename works - the system will auto-detect database type by content
- Recommended naming: `auth.sql.gz`, `world.sql.gz`, `characters.sql.gz`

## What Happens
- Files from this folder are copied to `local-storage/backups/daily/`
- Database import system automatically restores them
- Original files remain here for reference

## Notes
- Only processed on first deployment (when databases don't exist)
- Files are copied with timestamp to backup directory
- Empty folder is ignored - no files, no import
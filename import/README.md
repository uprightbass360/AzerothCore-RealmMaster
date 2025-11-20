# Import Directory

This directory allows you to easily import custom database files and configuration overrides into your AzerothCore server.

## 📁 Directory Structure

```
import/
├── db/          # Database SQL files to import
└── conf/        # Configuration file overrides
```

## 🗄️ Database Import (`import/db/`)

Place your custom SQL files here to import them into the database on server startup or deployment.

### Supported Files

- `auth.sql` - Authentication database updates
- `characters.sql` - Character database updates  
- `world.sql` - World database updates
- `*.sql` - Any other SQL files will be imported automatically

### Usage

1. Place your SQL files in `import/db/`:
   ```bash
   cp my_custom_npcs.sql import/db/world.sql
   cp my_accounts.sql import/db/auth.sql
   ```

2. Deploy or restart your server:
   ```bash
   ./scripts/bash/import-database-files.sh
   ```

### Example Files

See `import/db/examples/` for sample SQL files.

## ⚙️ Configuration Import (`import/conf/`)

Place module configuration files here to override default settings.

### Supported Files

Any `.conf` file placed here will be copied to the server's config directory, overriding the default settings.

### Common Configuration Files

- `worldserver.conf` - Core world server settings
- `authserver.conf` - Authentication server settings
- `playerbots.conf` - Playerbot module settings
- `AutoBalance.conf` - AutoBalance module settings
- Any other module `.conf` file

### Usage

1. Create or copy a configuration file:
   ```bash
   cp storage/config/playerbots.conf.dist import/conf/playerbots.conf
   ```

2. Edit the file with your custom settings:
   ```ini
   AiPlayerbot.MinRandomBots = 100
   AiPlayerbot.MaxRandomBots = 200
   ```

3. Apply the configuration:
   ```bash
   ./scripts/bash/configure-server.sh
   ```

   Or use the Python config tool for advanced merging:
   ```bash
   python3 scripts/python/apply-config.py
   ```

### Configuration Presets

Instead of manual configuration, you can use presets from `config/server-overrides.conf`:

```ini
[worldserver.conf]
Rate.XP.Kill = 2.0
Rate.XP.Quest = 2.0

[playerbots.conf]
AiPlayerbot.MinRandomBots = 100
AiPlayerbot.MaxRandomBots = 200
```

See `config/CONFIG_MANAGEMENT.md` for detailed preset documentation.

## 🔄 Automated Import

Both database and configuration imports are automatically handled during:

- **Initial Setup**: `./setup.sh`
- **Deployment**: `./deploy.sh`  
- **Module Staging**: `./scripts/bash/stage-modules.sh`

## 📝 Notes

- Files in `import/` are preserved across deployments
- SQL files are only imported once (tracked by filename hash)
- Configuration files override defaults but don't replace them
- Use `.gitignore` to keep sensitive files out of version control

## 🚨 Best Practices

1. **Backup First**: Always backup your database before importing SQL
2. **Test Locally**: Test imports on a dev server first
3. **Document Changes**: Add comments to your SQL files explaining what they do
4. **Use Transactions**: Wrap large imports in transactions for safety
5. **Version Control**: Keep track of what you've imported

## 📚 Related Documentation

- [Database Management](../docs/DATABASE_MANAGEMENT.md)
- [Configuration Management](../config/CONFIG_MANAGEMENT.md)
- [Module Management](../docs/ADVANCED.md#module-management)

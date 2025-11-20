# Module DBC File Handling

## Overview

Some AzerothCore modules include binary `.dbc` (Database Client) files that modify game data. These files serve two purposes:

1. **Server-side DBC files**: Override base game data on the server
2. **Client-side DBC files**: Packaged in MPQ patches for player clients

## Server DBC Staging

### How It Works

The module staging system (`scripts/bash/stage-modules.sh`) automatically deploys server-side DBC files to `/azerothcore/data/dbc/` in the worldserver container.

### Enabling DBC Staging for a Module

Add the `server_dbc_path` field to the module's entry in `config/module-manifest.json`:

```json
{
  "key": "MODULE_WORGOBLIN",
  "name": "mod-worgoblin",
  "repo": "https://github.com/heyitsbench/mod-worgoblin.git",
  "type": "cpp",
  "server_dbc_path": "data/patch/DBFilesClient",
  "description": "Enables Worgen and Goblin characters with DB/DBC adjustments",
  "category": "customization"
}
```

### Manifest Fields

| Field | Required | Description |
|-------|----------|-------------|
| `server_dbc_path` | Optional | Relative path within module to server-side DBC files |
| `notes` | Optional | Additional installation notes (e.g., client patch requirements) |

### Example Directory Structures

**mod-worgoblin:**
```
mod-worgoblin/
└── data/
    └── patch/
        └── DBFilesClient/          ← server_dbc_path: "data/patch/DBFilesClient"
            ├── CreatureModelData.dbc
            ├── CharSections.dbc
            └── ...
```

**mod-arac:**
```
mod-arac/
└── patch-contents/
    └── DBFilesContent/             ← server_dbc_path: "patch-contents/DBFilesContent"
        ├── CharBaseInfo.dbc
        ├── CharStartOutfit.dbc
        └── SkillRaceClassInfo.dbc
```

## Important Distinctions

### Server-Side vs Client-Side DBC Files

**Server-Side DBC Files:**
- Loaded by worldserver at startup
- Must have valid data matching AzerothCore's expectations
- Copied to `/azerothcore/data/dbc/`
- Specified via `server_dbc_path` in manifest

**Client-Side DBC Files:**
- Packaged in MPQ patches for WoW clients
- May contain empty/stub data for UI display only
- **NOT** deployed by the staging system
- Must be distributed to players separately

### Example: mod-bg-slaveryvalley

The mod-bg-slaveryvalley module contains DBC files in `client-side/DBFilesClient/`, but these are **CLIENT-ONLY** files (empty stubs). The actual server data must be downloaded separately from the module's releases.

**Manifest entry:**
```json
{
  "key": "MODULE_BG_SLAVERYVALLEY",
  "name": "mod-bg-slaveryvalley",
  "notes": "DBC files in client-side/DBFilesClient are CLIENT-ONLY. Server data must be downloaded separately from releases."
}
```

## Workflow

1. **Module enabled** → `.env` has `MODULE_NAME=1`
2. **Staging runs** → `./scripts/bash/stage-modules.sh`
3. **Manifest check** → Reads `server_dbc_path` from `config/module-manifest.json`
4. **DBC copy** → Copies `*.dbc` files to worldserver container
5. **Server restart** → `docker restart ac-worldserver` to load new DBC data

## Current Modules with Server DBC Files

| Module | Status | server_dbc_path | Notes |
|--------|--------|----------------|-------|
| mod-worgoblin | Disabled | `data/patch/DBFilesClient` | Requires client patch |
| mod-arac | Enabled | `patch-contents/DBFilesContent` | Race/class combinations |
| mod-bg-slaveryvalley | Enabled | *Not set* | DBC files are client-only |
| prestige-and-draft-mode | Enabled | *Not set* | Manual server DBC setup required |

## Troubleshooting

### DBC Field Count Mismatch

**Error:**
```
/azerothcore/data/dbc/AreaTable.dbc exists, and has 0 field(s) (expected 36).
```

**Cause:** Client-only DBC file was incorrectly deployed to server

**Solution:** Remove `server_dbc_path` from manifest or verify DBC files contain valid server data

### DBC Files Not Loading

**Check:**
1. Module is enabled in `.env`
2. `server_dbc_path` is set in `config/module-manifest.json`
3. DBC directory exists at specified path
4. Worldserver was restarted after staging

## Best Practices

1. **Only set `server_dbc_path` for modules with valid server-side DBC files**
2. **Test DBC deployments carefully** - invalid DBC data causes worldserver crashes
3. **Document client patch requirements** in the `notes` field
4. **Verify DBC field counts** match AzerothCore expectations
5. **Keep client-only DBC files separate** from server DBC staging

## Related Documentation

- [Module Management](./ADVANCED.md#module-management)
- [Database Management](./DATABASE_MANAGEMENT.md)
- [Troubleshooting](./TROUBLESHOOTING.md)

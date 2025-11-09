# Configuration Management System

This system allows easy management of AzerothCore server settings using familiar INI/conf file syntax.

## 📁 File Structure

```
config/
├── server-overrides.conf          # Main configuration overrides
└── presets/                       # Pre-configured server types
    ├── blizzlike.conf             # Authentic WotLK experience
    ├── fast-leveling.conf         # 3x XP rates
    ├── hardcore-pvp.conf          # Competitive PvP server
    └── casual-pve.conf            # Relaxed PvE experience
```

## 🚀 Quick Start

### 1. Edit Configuration Settings

Edit `config/server-overrides.conf` with your desired settings:

```ini
[worldserver.conf]
Rate.XP.Kill = 2.0
Rate.XP.Quest = 2.0
GM.InGMList.Level = 3

[playerbots.conf]
AiPlayerbot.MinRandomBots = 100
AiPlayerbot.MaxRandomBots = 300
```

### 2. Apply Configuration

```bash
# Apply your custom overrides
./scripts/apply-config.py

# Or apply a preset
./scripts/apply-config.py --preset fast-leveling

# Preview changes without applying
./scripts/apply-config.py --dry-run
```

### 3. Restart Server

Restart your AzerothCore containers to apply the changes:

```bash
docker compose down && docker compose up -d
```

## 🤖 Automated Integration

The configuration system is fully integrated into the setup and deployment workflow for seamless automation.

### **Setup Integration**
During `./setup.sh`, you can choose a server configuration preset:
```
SERVER CONFIGURATION PRESET
Choose a server configuration preset:
1) Default (No Preset)
   Use default AzerothCore settings without any modifications
2) Blizzlike Server
   Authentic WotLK experience with 1x rates and original mechanics
3) Fast Leveling Server
   3x XP rates with quality of life improvements and cross-faction features
4) Hardcore PvP Server
   Competitive PvP environment with 1.5x leveling and minimal bots
5) Casual PvE Server
   Relaxed PvE experience with 2x rates and social features
```

The chosen preset is stored in `.env`:
```bash
SERVER_CONFIG_PRESET=fast-leveling
```

### **Deploy Integration**
During `./deploy.sh`, the configuration is automatically applied:
```
Step 5/6: Applying server configuration
✅ Applying server configuration preset: fast-leveling
✅ Server configuration preset 'fast-leveling' applied successfully
ℹ️  Restarting worldserver to apply configuration changes
```

### **Automated Usage Examples**

**Interactive Setup:**
```bash
./setup.sh
# Choose preset during interactive configuration
./deploy.sh
# Configuration automatically applied
```

**Non-Interactive Setup:**
```bash
./setup.sh --server-config fast-leveling --non-interactive
./deploy.sh
# Configuration automatically applied
```

**Skip Configuration:**
```bash
./deploy.sh --skip-config
# Deploys without applying any configuration changes
```

## 📋 Available Commands

### Apply Custom Overrides
```bash
./scripts/apply-config.py
```

### Apply a Preset
```bash
# List available presets
./scripts/apply-config.py --list-presets

# Apply specific preset
./scripts/apply-config.py --preset blizzlike
./scripts/apply-config.py --preset fast-leveling
./scripts/apply-config.py --preset hardcore-pvp
./scripts/apply-config.py --preset casual-pve
```

### Advanced Usage
```bash
# Apply only specific conf files
./scripts/apply-config.py --files "worldserver.conf,playerbots.conf"

# Preview changes without applying
./scripts/apply-config.py --dry-run

# Use different storage path
./scripts/apply-config.py --storage-path /custom/storage

# Use different overrides file
./scripts/apply-config.py --overrides-file /path/to/custom.conf
```

## ⚙️ Configuration Format

### Section Headers
Each section corresponds to a `.conf` file:
```ini
[worldserver.conf]        # Settings for worldserver.conf
[authserver.conf]         # Settings for authserver.conf
[playerbots.conf]         # Settings for playerbots.conf
[mod_transmog.conf]       # Settings for mod_transmog.conf
```

### Data Types
```ini
# Boolean values (0 = disabled, 1 = enabled)
SomeFeature.Enable = 1

# Numeric values
Rate.XP.Kill = 2.5
MaxPlayerLevel = 80

# String values (can be quoted or unquoted)
ServerMessage = "Welcome to our server!"
DatabaseInfo = "127.0.0.1;3306;user;pass;db"
```

### Comments
Lines starting with `#` are comments and are ignored:
```ini
# This is a comment
# Rate.XP.Kill = 1.0  # This setting is disabled
Rate.XP.Quest = 2.0    # Active setting with comment
```

## 🎯 Available Presets

### blizzlike.conf
- **Description**: Authentic WotLK experience
- **XP Rates**: 1x (Blizzlike)
- **Features**: No cross-faction interaction, standard death penalties

### fast-leveling.conf
- **Description**: 3x XP with quality of life improvements
- **XP Rates**: 3x Kill/Quest, 2.5x Money
- **Features**: Cross-faction interaction, faster corpse decay, autobalance

### hardcore-pvp.conf
- **Description**: Competitive PvP environment
- **XP Rates**: 1.5x (to reach endgame faster)
- **Features**: No cross-faction interaction, minimal bots, expensive transmog

### casual-pve.conf
- **Description**: Relaxed PvE with social features
- **XP Rates**: 2x XP, 2.5x Rest bonus
- **Features**: Full cross-faction interaction, high bot population, solo LFG

## 🔧 How It Works

1. **Preservation**: The system reads your existing `.conf` files and preserves all comments and structure
2. **Override**: Only the settings you specify are updated
3. **Fallback**: If a `.conf` file doesn't exist, it's created from the corresponding `.dist` file
4. **Safety**: Use `--dry-run` to preview changes before applying

## 📝 Common Settings Reference

### XP and Progression
```ini
[worldserver.conf]
Rate.XP.Kill = 2.0                    # XP from killing monsters
Rate.XP.Quest = 2.0                   # XP from completing quests
Rate.XP.Explore = 1.5                 # XP from exploring new areas
Rate.Rest.InGame = 2.0                # Rest bonus while logged in
Rate.Rest.Offline.InTavernOrCity = 2.0 # Rest bonus while offline in safe zones
```

### Drop Rates
```ini
[worldserver.conf]
Rate.Drop.Money = 1.5                 # Money drop rate
Rate.Drop.Items = 1.2                 # Item drop rate
```

### Cross-Faction Settings
```ini
[worldserver.conf]
AllowTwoSide.Interaction.Chat = 1     # Cross-faction chat
AllowTwoSide.Interaction.Group = 1    # Cross-faction groups
AllowTwoSide.Interaction.Guild = 1    # Cross-faction guilds
AllowTwoSide.Interaction.Auction = 1  # Shared auction house
AllowTwoSide.Interaction.Mail = 1     # Cross-faction mail
```

### Playerbot Settings
```ini
[playerbots.conf]
AiPlayerbot.RandomBotMinLevel = 15     # Minimum bot level
AiPlayerbot.RandomBotMaxLevel = 80     # Maximum bot level
AiPlayerbot.MinRandomBots = 50         # Minimum number of bots
AiPlayerbot.MaxRandomBots = 200        # Maximum number of bots
AiPlayerbot.RandomBotJoinLfg = 1       # Bots join LFG
AiPlayerbot.RandomBotJoinBG = 1        # Bots join battlegrounds
```

### Module Settings
```ini
[mod_transmog.conf]
Transmogrification.Enable = 1         # Enable transmogrification
Transmogrification.Cost = 100000      # Cost in copper

[mod_autobalance.conf]
AutoBalance.enable = 1                 # Enable dungeon scaling
AutoBalance.MinPlayerReward = 1        # Scale rewards for solo play
```

## 🆘 Troubleshooting

### Configuration Not Applied
- Ensure you restart the server after applying changes
- Check that the `.conf` files exist in your `storage/config/` directory
- Use `--dry-run` to verify what changes would be made

### Permission Errors
```bash
# Make sure the script is executable
chmod +x scripts/apply-config.py

# Check file permissions in storage/config/
ls -la storage/config/
```

### Finding Available Settings
- Look in your `storage/config/` directory for `.conf` files
- Each module's available settings are documented in their `.conf` files
- Use `--dry-run` to see which files would be affected
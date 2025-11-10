# AzerothCore Custom NPCs Guide

This guide provides comprehensive documentation for all spawnable custom NPCs available through enabled modules on your AzerothCore server.

## Table of Contents
- [Overview](#overview)
- [Quick Spawn Reference](#quick-spawn-reference)
- [NPC Categories](#npc-categories)
- [Detailed NPC Information](#detailed-npc-information)
- [Spawn Commands](#spawn-commands)
- [Recommended Locations](#recommended-locations)
- [Admin Commands](#admin-commands)

## Overview

The AzerothCore server includes 14 custom NPCs through various enabled modules. These NPCs provide enhanced functionality including profession training, enchantments, pet management, arena services, and more.

**All NPCs are designed to:**
- Be level 80 with neutral faction (35) for universal access
- Remain permanent when spawned (deletion-protected)
- Provide user-friendly gossip interfaces
- Maintain thematic consistency with appropriate models and equipment

## Quick Spawn Reference

| NPC Name | Entry ID | Function | Spawn Command |
|----------|----------|----------|---------------|
| Kaylub | 199999 | Professions | `.npc add 199999` |
| Ling | 290011 | Reagent Banking | `.npc add 290011` |
| Cromi | 300000 | Instance Reset | `.npc add 300000` |
| Talamortis | 500030 | Guild House Seller | `.npc add 500030` |
| Xrispins | 500031 | Guild House Butler | `.npc add 500031` |
| Innkeeper Monica | 500032 | Guild House Innkeeper | `.npc add 500032` |
| Beauregard Boneglitter | 601015 | Enchanter | `.npc add 601015` |
| Buffmaster Hasselhoof | 601016 | Buffer | `.npc add 601016` |
| White Fang | 601026 | BeastMaster | `.npc add 601026` |
| Cet Keres | 601072 | Polymorphologist | `.npc add 601072` |
| Warpweaver | 190010 | Transmog | `.npc add 190010` |
| Ethereal Warpweaver | 190011 | Transmog | `.npc add 190011` |
| Arena Battlemaster 1v1 | 999991 | 1v1 Arena | `.npc add 999991` |
| Gabriella | 9000000 | Assistant | `.npc add 9000000` |

## NPC Categories

### 🔧 Core Service NPCs
Essential utility NPCs for everyday server functions.

### 🏰 Guild House NPCs
NPCs related to guild house functionality and management.

### ⚡ Enhancement & Utility NPCs
NPCs providing character enhancement services.

### ⚔️ PvP & Arena NPCs
NPCs for player vs player content and arena management.

### 👤 Assistant NPCs
General assistance and administrative NPCs.

## Detailed NPC Information

### Core Service NPCs

#### Kaylub (Entry: 199999)
- **Title:** Professions NPC
- **Function:** Provides free profession training and spells
- **Model:** High-quality character model (ID: 31833)
- **Features:**
  - Purple-colored subname for easy identification
  - Comprehensive profession training without cost
  - Spell learning capabilities
- **Module:** mod-npc-free-professions
- **Script:** npc_free_professions

#### Ling (Entry: 290011)
- **Title:** Reagent Banker
- **Function:** Specialized banking for reagents and crafting materials
- **Model:** Ethereal-style model (ID: 15965)
- **Features:**
  - Separate storage for crafting reagents
  - Enhanced inventory management
  - Quick access to frequently used materials
- **Module:** mod-reagent-bank
- **Script:** npc_reagent_banker

#### Cromi (Entry: 300000)
- **Title:** Instance Reset
- **Function:** Allows players to reset dungeon and raid instances
- **Features:**
  - Reset individual instances
  - Manage lockout timers
  - Bypass normal reset restrictions
- **Module:** mod-instance-reset

### Guild House NPCs

#### Talamortis (Entry: 500030)
- **Title:** Guild House Seller
- **Function:** Manages guild house purchases and sales
- **Features:**
  - Guild house acquisition
  - Property management
  - Pricing and availability information
- **Module:** mod-guildhouse

#### Xrispins (Entry: 500031)
- **Title:** Guild House Butler
- **Function:** Provides guild house services and management
- **Features:**
  - House maintenance services
  - Utility management
  - Guild house customization
- **Module:** mod-guildhouse

#### Innkeeper Monica (Entry: 500032)
- **Title:** Guild House Innkeeper
- **Function:** Sets hearthstone locations within guild houses
- **Features:**
  - Hearthstone binding within guild properties
  - Rest area designation
  - Inn services within guild houses
- **Module:** mod-guildhouse

### Enhancement & Utility NPCs

#### Beauregard Boneglitter (Entry: 601015)
- **Title:** Enchanter
- **Function:** Provides gear enchantments
- **Model:** Undead Necromancer (ID: 9353)
- **Equipment:** Black/Purple Staff (ID: 11343)
- **Features:**
  - Comprehensive enchantment services
  - All expansion enchantments available
  - Professional necromancer appearance
- **Module:** mod-npc-enchanter
- **Script:** npc_enchantment

#### Buffmaster Hasselhoof (Entry: 601016)
- **Title:** Buffer
- **Function:** Provides player buffs and blessings
- **Model:** Tauren Warmaster (ID: 14612)
- **Equipment:** Torch (ID: 1906)
- **Features:**
  - Comprehensive buff packages
  - Long-duration buffs
  - Class-specific enhancements
- **Module:** mod-npc-buffer
- **Script:** buff_npc

#### White Fang (Entry: 601026)
- **Title:** BeastMaster
- **Function:** Hunter pet management and taming services
- **Model:** Northrend Worgen White (ID: 26314)
- **Equipment:** Haunch of Meat (ID: 2196), Torch (ID: 1906)
- **Features:**
  - Exotic pet taming
  - Pet food vendor (35+ different food items)
  - Pet stable services
  - Rare pet acquisition
- **Module:** mod-npc-beastmaster
- **Script:** BeastMaster
- **Vendor Items:** Includes all pet food types from bread to exotic meats

#### Cet Keres (Entry: 601072)
- **Title:** Polymorphologist
- **Function:** Summon appearance modification
- **Model:** Custom ethereal model (ID: 15665)
- **Features:**
  - Warlock pet morphing
  - Summoned creature appearance changes
  - Felguard weapon customization
  - Multiple polymorph options
- **Module:** mod-morphsummon
- **Script:** npc_morphsummon

### PvP & Arena NPCs

#### Arena Battlemaster 1v1 (Entry: 999991)
- **Title:** Arena Battlemaster
- **Function:** 1v1 arena matches and team management
- **Model:** Arena Battlemaster (ID: 7110)
- **Features:**
  - Rated 1v1 arena matches
  - Unrated 1v1 practice matches
  - Automatic team creation
  - Arena statistics tracking
- **Module:** mod-1v1-arena
- **Script:** npc_1v1arena
- **Commands Available:**
  - `.q1v1 rated` - Join rated 1v1 arena
  - `.q1v1 unrated` - Join unrated 1v1 arena

### Transmog NPCs

#### Warpweaver (Entry: 190010)
- **Title:** Transmogrifier
- **Function:** Standard transmogrification services
- **Features:**
  - Equipment appearance modification
  - Transmog collection management
  - Standard WotLK transmog functionality
- **Module:** mod-transmog

#### Ethereal Warpweaver (Entry: 190011)
- **Title:** Transmogrifier
- **Function:** Alternative transmog NPC with ethereal appearance
- **Features:**
  - Same functionality as standard Warpweaver
  - Ethereal-themed appearance
  - Alternative location option
- **Module:** mod-transmog

### Assistant NPCs

#### Gabriella (Entry: 9000000)
- **Title:** The Assistant
- **Function:** General assistance and utility functions
- **Features:**
  - General server information
  - Player assistance services
  - Administrative support functions
- **Module:** mod-assistant

## Spawn Commands

### Basic Spawning
To spawn any NPC, use the following command format:
```
.npc add [entry_id]
```

### Advanced Spawning Options
```bash
# Spawn NPC facing specific direction
.npc add [entry_id] [orientation]

# Spawn NPC with specific spawn time
.npc add [entry_id] [spawntime_in_seconds]

# Get your current coordinates for documentation
.gps
```

### Example Commands
```bash
# Spawn the BeastMaster at current location
.npc add 601026

# Spawn Enchanter facing north (0 orientation)
.npc add 601015 0

# Spawn Professions NPC with 1-hour spawn time
.npc add 199999 3600
```

## Recommended Locations

### Major Cities - Central Services
**Stormwind City:**
- **Coordinates:** 83.2, 68.4, 18.4 (Trade District)
- **Recommended NPCs:** Kaylub (Professions), Beauregard (Enchanter), Buffmaster
- **Reason:** High traffic area with easy access

**Orgrimmar:**
- **Coordinates:** 54.2, 73.4, 18.2 (Valley of Strength)
- **Recommended NPCs:** Kaylub (Professions), Beauregard (Enchanter), Buffmaster
- **Reason:** Central location with bank proximity

### Specialized Areas

**Dalaran:**
- **Coordinates:** 40.8, 62.1, 504.2 (Runeweaver Square)
- **Recommended NPCs:** All Transmog NPCs, Cet Keres (Polymorphologist)
- **Reason:** Neutral city, thematic fit for magical services

**Shattrath City:**
- **Coordinates:** 64.0, 41.4, -0.5 (Lower City)
- **Recommended NPCs:** Arena Battlemaster, Ethereal Warpweaver
- **Reason:** Neutral territory, appropriate for PvP services

**Guild House Locations:**
- **Recommended NPCs:** Talamortis, Xrispins, Innkeeper Monica
- **Coordinates:** Within purchased guild houses only

### Hunter Outposts
**Recommended for White Fang (BeastMaster):**
- **Un'Goro Crater:** 41.9, 2.6, 116.8 (Marshal's Refuge)
- **Winterspring:** 31.3, 45.2, 1.4 (Everlook)
- **Reason:** Thematic locations with nearby rare pets

## Admin Commands

### NPC Management
```bash
# Delete specific NPC (use GUID from .npc near)
.npc delete [guid]

# Move NPC to your location
.npc move [guid]

# Get information about nearby NPCs
.npc near

# Make NPC face you
.npc set face

# Set NPC movement type
.npc set movetype [0=idle, 1=random, 2=waypoint]
```

### Database Operations
```bash
# Save NPC spawn to database
.npc add [entry] [spawntime] [save_to_db]

# Reload NPC data from database
.reload creature_template

# Check NPC entry information
.lookup creature [name_or_entry]
```

### Troubleshooting Commands
```bash
# If NPC appears but doesn't function:
.reload creature_template
.reload gossip_menu
.reload npc_vendor

# If NPC model is wrong:
.reload creature_template_model

# If scripts don't work:
.reload scripts
```

## Module Dependencies

| NPC | Required Module | Configuration File |
|-----|----------------|--------------------|
| Kaylub | mod-npc-free-professions | [Module Config] |
| Ling | mod-reagent-bank | [Module Config] |
| Cromi | mod-instance-reset | [Module Config] |
| Guild House NPCs | mod-guildhouse | [Module Config] |
| Beauregard | mod-npc-enchanter | [Module Config] |
| Buffmaster | mod-npc-buffer | [Module Config] |
| White Fang | mod-npc-beastmaster | [Module Config] |
| Cet Keres | mod-morphsummon | [Module Config] |
| Arena Battlemaster | mod-1v1-arena | [Module Config] |
| Transmog NPCs | mod-transmog | [Module Config] |
| Gabriella | mod-assistant | [Module Config] |

## Notes

- **All NPCs require GM access level 1 or higher to spawn**
- **NPCs will persist through server restarts once saved to database**
- **Some NPCs may require specific client-side files for full functionality**
- **Module configurations can be found in the respective module directories**
- **Always test NPC functionality after spawning**

## Support

For issues with specific NPCs:
1. Check that the corresponding module is enabled
2. Verify the NPC was saved to the database
3. Reload relevant database tables
4. Check server logs for script errors
5. Consult module-specific documentation

---

*Last updated: November 2024*
*AzerothCore Version: 3.3.5a*
*Module versions may vary - check individual module documentation for specific features*
# AzerothCore RealmMaster - Module Catalog

This document provides a comprehensive overview of all available modules in the AzerothCore RealmMaster project. These modules enhance gameplay, provide quality-of-life improvements, add new features, and extend server functionality.

## Overview

AzerothCore RealmMaster currently ships a manifest of **348 modules** (221 marked supported/active). The default RealmMaster preset enables 33 of these for day-to-day testing. All modules are automatically downloaded, configured, and SQL scripts executed when enabled. Modules are organized into logical categories for easy browsing and selection.

## How Modules Work

- **Automatic Integration**: All enabled modules are automatically downloaded and configured during deployment
- **SQL Automation**: Database scripts are executed automatically for enabled modules
- **Configuration Management**: Module configuration files are automatically created and managed
- **Profile-Based Deployment**: Different deployment profiles support various module combinations

## Module Categories

The module collection is organized into the following categories:

- [Automation](#automation) - Bot management and AI-driven features
- [Quality of Life](#quality-of-life) - Convenience features and improvements
- [Gameplay Enhancement](#gameplay-enhancement) - Core gameplay modifications
- [NPC Services](#npc-services) - Service NPCs and vendors
- [PvP](#pvp) - Player vs Player enhancements
- [Progression](#progression) - Character advancement systems
- [Economy](#economy) - Economic and trading systems
- [Social](#social) - Communication and community features
- [Account-Wide](#account-wide) - Cross-character account features
- [Customization](#customization) - Appearance and character customization
- [Scripting](#scripting) - Scripting engines and development tools
- [Admin Tools](#admin-tools) - Server administration utilities
- [Premium/VIP](#premiumvip) - Subscription and premium features
- [Mini-Games](#mini-games) - Entertainment and gaming features
- [Content](#content) - Additional game content
- [Rewards](#rewards) - Reward and achievement systems
- [Developer Tools](#developer-tools) - Development and debugging tools

---

## Automation

| Module | Description |
|--------|-------------|
| **[mod-ollama-chat](https://github.com/DustinHendrickson/mod-ollama-chat.git)** | Connects playerbots to an Ollama LLM so they can chat with humans organically |
| **[mod-player-bot-level-brackets](https://github.com/DustinHendrickson/mod-player-bot-level-brackets.git)** | Keeps bot levels spread evenly across configured brackets |
| **[mod-playerbots](https://github.com/mod-playerbots/mod-playerbots.git)** | Adds scriptable playerbot characters that can form dungeon parties, raid, and PvP with humans |
| **[npcbot-extended-commands](https://github.com/Day36512/Npcbot_Extended_Commands.git)** | Provides gear templates, transmog clearing, and chat features for NPC bots |

## Quality of Life

| Module | Description |
|--------|-------------|
| **[mod-aoe-loot](https://github.com/azerothcore/mod-aoe-loot.git)** | Lets characters loot multiple corpses with one click for faster farming |
| **[mod-auto-revive](https://github.com/azerothcore/mod-auto-revive.git)** | Automatically resurrects characters on death—handy for casual PvE or testing realms |
| **[mod-fireworks-on-level](https://github.com/azerothcore/mod-fireworks-on-level.git)** | Spawns celebratory fireworks whenever a player dings a new level |
| **[mod-instance-reset](https://github.com/azerothcore/mod-instance-reset.git)** | Adds commands to reset instances quickly—useful for testing or events |
| **[mod-learn-spells](https://github.com/azerothcore/mod-learn-spells.git)** | Teaches class spells automatically at the correct level to streamline leveling |
| **[mod-solo-lfg](https://github.com/azerothcore/mod-solo-lfg.git)** | A solo-friendly queue that lets every player run dungeons without needing a premade group |

## Gameplay Enhancement

| Module | Description |
|--------|-------------|
| **[DungeonRespawn](https://github.com/AnchyDev/DungeonRespawn.git)** | Teleports dead players back to the dungeon entrance instead of a distant graveyard |
| **[StatBooster](https://github.com/AnchyDev/StatBooster.git)** | Lets players refine gear stats by rerolling random enchantments with special materials |
| **[horadric-cube-for-world-of-warcraft](https://github.com/TITIaio/Horadric-Cube-for-World-of-Warcraft.git)** | Diablo II-inspired crafting system with item synthesis and transmutation |
| **[lua-hardcoremode](https://github.com/HellionOP/Lua-HardcoreMode.git)** | Implements hardcore mode system allowing activation via NPC token |
| **[mod-TimeIsTime](https://github.com/dunjeon/mod-TimeIsTime.git)** | Adds experimental time-twisting mechanics suited for custom events |
| **[mod-autobalance](https://github.com/azerothcore/mod-autobalance.git)** | Adjusts creature health and damage in real time to keep fights tuned for the current party size |
| **[mod-challenge-modes](https://github.com/ZhengPeiRu21/mod-challenge-modes.git)** | Implements keystone-style timed runs with leaderboards and scaling modifiers |
| **[mod-duel-reset](https://github.com/azerothcore/mod-duel-reset.git)** | Adds some duel reset features |
| **[mod-solocraft](https://github.com/azerothcore/mod-solocraft.git)** | Automatically scales dungeon and raid encounters for solo players or small teams |

## NPC Services

| Module | Description |
|--------|-------------|
| **[azerothcore-lua-multivendor](https://github.com/Shadowveil-WotLK/AzerothCore-lua-MultiVendor.git)** | Enables multiple NPC merchants with database integration |
| **[mod-assistant](https://github.com/noisiver/mod-assistant.git)** | Spawns an all-purpose assistant NPC with heirlooms, professions, and convenience commands |
| **[mod-npc-beastmaster](https://github.com/azerothcore/mod-npc-beastmaster.git)** | Adds an NPC who can teach, reset, and manage hunter pets for convenience |
| **[mod-npc-buffer](https://github.com/azerothcore/mod-npc-buffer.git)** | Provides a ready-to-use buff NPC who hands out class buffs, food, and utility spells |
| **[mod-npc-enchanter](https://github.com/azerothcore/mod-npc-enchanter.git)** | Introduces an enchanting vendor who applies enchants directly for a fee |
| **[mod-npc-free-professions](https://github.com/azerothcore/mod-npc-free-professions.git)** | Makes a ProfessionsNPC who gives 2 free professions (full with recipes) to player |
| **[mod-npc-talent-template](https://github.com/azerothcore/mod-npc-talent-template.git)** | An NPC that allows players to instantly apply pre-configured character templates that gear up, gem, set talents, and apply glyphs for any class |
| **[mod-reagent-bank](https://github.com/ZhengPeiRu21/mod-reagent-bank.git)** | Lets players stash crafting reagents with a dedicated banker NPC |
| **[mod-transmog](https://github.com/azerothcore/mod-transmog.git)** | Adds a transmogrification vendor so players can restyle gear without changing stats |

## PvP

| Module | Description |
|--------|-------------|
| **[mod-1v1-arena](https://github.com/azerothcore/mod-1v1-arena.git)** | Creates a structured 1v1 ranked arena ladder for duel enthusiasts |
| **[mod-arena-replay](https://github.com/azerothcore/mod-arena-replay.git)** | Allows you to watch a replay of rated arena games |
| **[mod-gain-honor-guard](https://github.com/azerothcore/mod-gain-honor-guard.git)** | Awards honor when players kill city guards, spicing up world PvP raids |
| **[mod-phased-duels](https://github.com/azerothcore/mod-phased-duels.git)** | Moves duelers into their own phase to block interference and griefing |
| **[mod-pvp-titles](https://github.com/azerothcore/mod-pvp-titles.git)** | Restores classic honor titles with a configurable ranking ladder |
| **[ultimate-full-loot-pvp](https://github.com/Youpeoples/Ultimate-Full-Loot-Pvp.git)** | Spawns loot chests containing gear and gold when players die in PvP |

## Progression

| Module | Description |
|--------|-------------|
| **[mod-dynamic-xp](https://github.com/azerothcore/mod-dynamic-xp.git)** | Tweaks XP gain based on population or custom rules to keep leveling flexible |
| **[mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression.git)** | Tracks each character through Vanilla → TBC → WotLK progression, unlocking content sequentially |
| **[mod-item-level-up](https://github.com/azerothcore/mod-item-level-up.git)** | Creates an item that allows you to level up (id = 701001) |
| **[mod-progression-system](https://github.com/azerothcore/mod-progression-system.git)** | Allows for the automatic loading of scripts and SQL files based on level brackets |
| **[mod-promotion-azerothcore](https://github.com/azerothcore/mod-promotion-azerothcore.git)** | Allows player to receive a promotion consisting of a level 90 character, backpacks, gold, armor, and a mount |
| **[mod-quest-count-level](https://github.com/michaeldelago/mod-quest-count-level.git)** | Enables leveling exclusively through questing by awarding tokens after quest completion |
| **[mod-weekend-xp](https://github.com/azerothcore/mod-weekend-xp.git)** | XP module that allows server owner to select how much XP players can receive on the weekend via config file |
| **[mod-zone-difficulty](https://github.com/azerothcore/mod-zone-difficulty.git)** | Support module for mod-progression-system, handles nerfs and debuffs per zone |

## Economy

| Module | Description |
|--------|-------------|
| **[acore-exchangenpc](https://github.com/55Honey/Acore_ExchangeNpc.git)** | Spawns a customizable NPC vendor that exchanges materials based on settings |
| **[azerothcore-global-mail-banking-auctions](https://github.com/Aldori15/azerothcore-global-mail_banking_auctions.git)** | Allows access to bank, mailbox, and auction house from anywhere via chat commands |
| **[azerothcore-lua-ah-bot](https://github.com/mostlynick3/azerothcore-lua-ah-bot.git)** | Automated auction house bot for buying and selling items |
| **[dynamic-trader](https://github.com/Day36512/Dynamic-Trader.git)** | Provides auction house alternative with dynamic pricing |
| **[lottery-lua](https://github.com/zyggy123/lottery-lua.git)** | Implements customizable lottery system where players can win prizes |
| **[mod-ahbot](https://github.com/azerothcore/mod-ahbot.git)** | Populates the auction house with configurable buying/selling behavior to keep markets active |
| **[mod-black-market](https://github.com/Youpeoples/Black-Market-Auction-House.git)** | Backports the Mists-era Black Market Auction House via Eluna scripts |
| **[mod-random-enchants](https://github.com/azerothcore/mod-random-enchants.git)** | Rolls randomized stat bonuses on loot to add Diablo-style gear chasing |

## Social

| Module | Description |
|--------|-------------|
| **[acore-discordnotifier](https://github.com/0xCiBeR/Acore_DiscordNotifier.git)** | Relays in-game chat events to Discord channels |
| **[acore-tempannouncements](https://github.com/55Honey/Acore_TempAnnouncements.git)** | Allows GMs to create temporary server announcements that repeat at intervals |
| **[activechat](https://github.com/Day36512/ActiveChat.git)** | Populates artificial world and guild chat to make servers feel more lively |
| **[mod-boss-announcer](https://github.com/azerothcore/mod-boss-announcer.git)** | Broadcasts dramatic messages when raid bosses fall to your players |
| **[mod-breaking-news-override](https://github.com/azerothcore/mod-breaking-news-override.git)** | Replaces the client breaking-news panel with server-managed announcements |
| **[mod-global-chat](https://github.com/azerothcore/mod-global-chat.git)** | Simple global chat for AzerothCore enabling worldserver-wide messaging functionality |

## Account-Wide

| Module | Description |
|--------|-------------|
| **[azerothcore-eluna-accountwide](https://github.com/Aldori15/azerothcore-eluna-accountwide.git)** | Shares achievements, currency, mounts, and reputation across account characters |
| **[mod-account-achievements](https://github.com/azerothcore/mod-account-achievements.git)** | Shares achievements across characters on the same account for persistent milestones |
| **[mod-account-mounts](https://github.com/azerothcore/mod-account-mounts.git)** | Goes through the list of characters on an account to obtain playerGuids and store mount spells that all characters know |

## Customization

| Module | Description |
|--------|-------------|
| **[azerothcore-transmog-3.3.5a](https://github.com/DanieltheDeveloper/azerothcore-transmog-3.3.5a.git)** | Transmogrification system built with AIO and Eluna for changing equipment appearance |
| **[mod-arac](https://github.com/heyitsbench/mod-arac.git)** | Unlocks every race/class pairing so players can roll any combination |
| **[mod-morphsummon](https://github.com/azerothcore/mod-morphsummon.git)** | Change appearance of summoned permanent creatures |
| **[mod-worgoblin](https://github.com/heyitsbench/mod-worgoblin.git)** | Enables Worgen and Goblin characters with DB/DBC adjustments |

## Scripting

| Module | Description |
|--------|-------------|
| **[acore-eventscripts](https://github.com/55Honey/Acore_eventScripts.git)** | Lua scripts that spawn custom NPCs with scripted combat and community events |
| **[eluna-scripts](https://github.com/Isidorsson/Eluna-scripts.git)** | Collection of Lua scripts for creating custom gameplay mechanics and features |
| **[eluna-ts](https://github.com/azerothcore/eluna-ts.git)** | Adds a TS-to-Lua workflow so Eluna scripts can be authored with modern tooling |
| **[mod-aio](https://github.com/Rochet2/AIO.git)** | Pure Lua server-client communication system for bidirectional data transmission |
| **[mod-ale](https://github.com/azerothcore/mod-ale.git)** | ALE (AzerothCore Lua Engine) - Lua scripting engine for custom gameplay mechanics (formerly Eluna) |

## Admin Tools

| Module | Description |
|--------|-------------|
| **[acore-carboncopy](https://github.com/55Honey/Acore_CarbonCopy.git)** | Enables creating character copies at specific progression points for twinking |
| **[acore-sendandbind](https://github.com/55Honey/Acore_SendAndBind.git)** | Allows admins to send soulbound items to players via command |
| **[acore-zonecheck](https://github.com/55Honey/Acore_Zonecheck.git)** | Checks player zones and automatically removes players from restricted areas |
| **[mod-antifarming](https://github.com/azerothcore/mod-antifarming.git)** | Port of the AntiFarming Script from SymbolixDEV's repo to AzerothCore |
| **[mod-keep-out](https://github.com/azerothcore/mod-keep-out.git)** | Keeps players who are non-GM from entering a zone/map |
| **[mod-server-auto-shutdown](https://github.com/azerothcore/mod-server-auto-shutdown.git)** | Establishes a daily restart with configurable time, notification period, and custom messages |
| **[mod-spell-regulator](https://github.com/azerothcore/mod-spell-regulator.git)** | Modify the percentage of the spells by regulating in the best way |
| **[mod-who-logged](https://github.com/azerothcore/mod-who-logged.git)** | Outputs to the console when a player logs into the world |

## Premium/VIP

| Module | Description |
|--------|-------------|
| **[mod-acore-subscriptions](https://github.com/azerothcore/mod-acore-subscriptions.git)** | Handles the subscription logic, no longer requires modules or services to have subscription logic in their code |
| **[mod-premium](https://github.com/azerothcore/mod-premium.git)** | Adds Premium account features to players |
| **[mod-system-vip](https://github.com/azerothcore/mod-system-vip.git)** | System offering VIP features and benefits to players |

## Mini-Games

| Module | Description |
|--------|-------------|
| **[aio-blackjack](https://github.com/Manmadedrummer/AIO-Blackjack.git)** | Implements a Blackjack game for players to gamble against an NPC dealer |
| **[mod-pocket-portal](https://github.com/azerothcore/mod-pocket-portal.git)** | Gives players a portal gadget for quick travel to configured destinations |
| **[mod-tic-tac-toe](https://github.com/azerothcore/mod-tic-tac-toe.git)** | Allows players to play Tic Tac Toe between players and against different AI |

## Content

| Module | Description |
|--------|-------------|
| **[mod-azerothshard](https://github.com/azerothcore/mod-azerothshard.git)** | Bundles AzerothShard tweaks: utility NPCs, scripted events, and gameplay improvements |
| **[mod-bg-slaveryvalley](https://github.com/Helias/mod-bg-slaveryvalley.git)** | Adds the Slavery Valley battleground complete with objectives and queue hooks |
| **[mod-guildhouse](https://github.com/azerothcore/mod-guildhouse.git)** | Phased guild house system allowing guild members to visit their private guild house |
| **[mod-war-effort](https://github.com/azerothcore/mod-war-effort.git)** | Brings back the war effort of the two factions for the opening of the gates of Ahn'Qiraj |
| **[treasure-chest-system](https://github.com/zyggy123/Treasure-Chest-System.git)** | Allows GMs to create and manage treasure chests with custom loot |

## Rewards

| Module | Description |
|--------|-------------|
| **[acore-levelupreward](https://github.com/55Honey/Acore_LevelUpReward.git)** | Rewards players with in-game mail when reaching certain levels |
| **[acore-recruitafriend](https://github.com/55Honey/Acore_RecruitAFriend.git)** | Implements Recruit-a-Friend system with rewards for reaching level milestones |
| **[mod-resurrection-scroll](https://github.com/azerothcore/mod-resurrection-scroll.git)** | Allows users to grant rested XP bonuses to players who have not logged in X days |
| **[mod-reward-played-time](https://github.com/azerothcore/mod-reward-played-time.git)** | Adds items for players that have stayed logged in for x amount of time |
| **[prestige-and-draft-mode](https://github.com/Youpeoples/Prestige-and-Draft-Mode.git)** | Enables characters to reset to level one for prestige rewards with optional spell selection |

## Developer Tools

| Module | Description |
|--------|-------------|
| **[skeleton-module](https://github.com/azerothcore/skeleton-module.git)** | Provides a minimal AzerothCore module scaffold for building new features |

---

## Module Selection and Configuration

### Using Setup Script

The interactive setup script allows you to easily select modules:

```bash
./setup.sh
```

This will present a menu for selecting individual modules or choosing from predefined module profiles.

### Module Profiles

Pre-configured module combinations are available in `config/module-profiles/`:

- `RealmMaster` - 33-module baseline used for day-to-day testing
- `suggested-modules` - Light AzerothCore QoL stack without playerbots
- `playerbots-suggested-modules` - Suggested QoL stack plus playerbots
- `azerothcore-vanilla` - Pure AzerothCore with no optional modules
- `playerbots-only` - Playerbot prerequisites only
- `all-modules` - Everything in the manifest (not recommended)
- Custom profiles - Drop new JSON files to add your own combinations

### Manual Configuration

You can also enable modules by setting environment variables in your `.env` file:

```bash
MODULE_SOLO_LFG=1
MODULE_TRANSMOG=1
MODULE_PLAYERBOTS=1
# ... additional modules
```

### Module Types

Modules are categorized by type:

- **C++ Modules** - Require source compilation and rebuild
- **Lua Modules** - Script-based, no compilation needed
- **Data Modules** - Database and configuration only

## Further Information

For detailed setup and deployment instructions, see the main [README.md](../README.md) file.

For technical details about module management and the build system, refer to the [Architecture Overview](../README.md#architecture-overview) section.

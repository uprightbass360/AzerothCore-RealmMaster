#!/bin/bash
# ac-compose
set -e

echo 'Setting up git user'
git config --global user.name "${GIT_USERNAME:-ac-compose}"
git config --global user.email "${GIT_EMAIL:-noreply@azerothcore.org}"
# PAT not needed for public repositories

echo 'Initializing module management...'
if [ "$MODULES_LOCAL_RUN" != "1" ]; then
  cd /modules
fi

echo 'Cleaning up disabled modules...'

# Playerbots are integrated into the source - no separate module to remove

if [ "$MODULE_AOE_LOOT" != "1" ] && [ -d "mod-aoe-loot" ]; then
  echo 'Removing mod-aoe-loot (disabled)...'
  rm -rf mod-aoe-loot
fi

if [ "$MODULE_LEARN_SPELLS" != "1" ] && [ -d "mod-learn-spells" ]; then
  echo 'Removing mod-learn-spells (disabled)...'
  rm -rf mod-learn-spells
fi

if [ "$MODULE_FIREWORKS" != "1" ] && [ -d "mod-fireworks-on-level" ]; then
  echo 'Removing mod-fireworks-on-level (disabled)...'
  rm -rf mod-fireworks-on-level
fi

if [ "$MODULE_INDIVIDUAL_PROGRESSION" != "1" ] && [ -d "mod-individual-progression" ]; then
  echo 'Removing mod-individual-progression (disabled)...'
  rm -rf mod-individual-progression
fi

if [ "$MODULE_AHBOT" != "1" ] && [ -d "mod-ahbot" ]; then
  echo 'Removing mod-ahbot (disabled)...'
  rm -rf mod-ahbot
fi

if [ "$MODULE_AUTOBALANCE" != "1" ] && [ -d "mod-autobalance" ]; then
  echo 'Removing mod-autobalance (disabled)...'
  rm -rf mod-autobalance
fi

if [ "$MODULE_TRANSMOG" != "1" ] && [ -d "mod-transmog" ]; then
  echo 'Removing mod-transmog (disabled)...'
  rm -rf mod-transmog
fi

if [ "$MODULE_NPC_BUFFER" != "1" ] && [ -d "mod-npc-buffer" ]; then
  echo 'Removing mod-npc-buffer (disabled)...'
  rm -rf mod-npc-buffer
fi

if [ "$MODULE_DYNAMIC_XP" != "1" ] && [ -d "mod-dynamic-xp" ]; then
  echo 'Removing mod-dynamic-xp (disabled)...'
  rm -rf mod-dynamic-xp
fi

if [ "$MODULE_SOLO_LFG" != "1" ] && [ -d "mod-solo-lfg" ]; then
  echo 'Removing mod-solo-lfg (disabled)...'
  rm -rf mod-solo-lfg
fi

if [ "$MODULE_1V1_ARENA" != "1" ] && [ -d "mod-1v1-arena" ]; then
  echo 'Removing mod-1v1-arena (disabled)...'
  rm -rf mod-1v1-arena
fi

if [ "$MODULE_PHASED_DUELS" != "1" ] && [ -d "mod-phased-duels" ]; then
  echo 'Removing mod-phased-duels (disabled)...'
  rm -rf mod-phased-duels
fi

if [ "$MODULE_BREAKING_NEWS" != "1" ] && [ -d "mod-breaking-news-override" ]; then
  echo 'Removing mod-breaking-news-override (disabled)...'
  rm -rf mod-breaking-news-override
fi

if [ "$MODULE_BOSS_ANNOUNCER" != "1" ] && [ -d "mod-boss-announcer" ]; then
  echo 'Removing mod-boss-announcer (disabled)...'
  rm -rf mod-boss-announcer
fi

if [ "$MODULE_ACCOUNT_ACHIEVEMENTS" != "1" ] && [ -d "mod-account-achievements" ]; then
  echo 'Removing mod-account-achievements (disabled)...'
  rm -rf mod-account-achievements
fi

if [ "$MODULE_AUTO_REVIVE" != "1" ] && [ -d "mod-auto-revive" ]; then
  echo 'Removing mod-auto-revive (disabled)...'
  rm -rf mod-auto-revive
fi

if [ "$MODULE_GAIN_HONOR_GUARD" != "1" ] && [ -d "mod-gain-honor-guard" ]; then
  echo 'Removing mod-gain-honor-guard (disabled)...'
  rm -rf mod-gain-honor-guard
fi

if [ "$MODULE_ELUNA" != "1" ] && [ -d "mod-eluna" ]; then
  echo 'Removing mod-eluna (disabled)...'
  rm -rf mod-eluna
fi
if [ "$MODULE_ARAC" != "1" ] && [ -d "mod-arac" ]; then
  echo 'Removing mod-arac (disabled)...'
  rm -rf mod-arac
fi

if [ "$MODULE_TIME_IS_TIME" != "1" ] && [ -d "mod-TimeIsTime" ]; then
  echo 'Removing mod-TimeIsTime (disabled)...'
  rm -rf mod-TimeIsTime
fi

if [ "$MODULE_POCKET_PORTAL" = "1" ]; then
  echo '⚠️  mod-pocket-portal is temporarily disabled (requires C++20 <format>). Skipping until patched.'
  echo '   Apply the std::format -> SendSystemMessage fix before re-enabling this module.'
  MODULE_POCKET_PORTAL=0
fi

if [ "$MODULE_POCKET_PORTAL" != "1" ] && [ -d "mod-pocket-portal" ]; then
  echo 'Removing mod-pocket-portal (disabled)...'
  rm -rf mod-pocket-portal
fi

if [ "$MODULE_RANDOM_ENCHANTS" != "1" ] && [ -d "mod-random-enchants" ]; then
  echo 'Removing mod-random-enchants (disabled)...'
  rm -rf mod-random-enchants
fi

if [ "$MODULE_SOLOCRAFT" != "1" ] && [ -d "mod-solocraft" ]; then
  echo 'Removing mod-solocraft (disabled)...'
  rm -rf mod-solocraft
fi

if [ "$MODULE_PVP_TITLES" != "1" ] && [ -d "mod-pvp-titles" ]; then
  echo 'Removing mod-pvp-titles (disabled)...'
  rm -rf mod-pvp-titles
fi

if [ "$MODULE_NPC_BEASTMASTER" != "1" ] && [ -d "mod-npc-beastmaster" ]; then
  echo 'Removing mod-npc-beastmaster (disabled)...'
  rm -rf mod-npc-beastmaster
fi

if [ "$MODULE_NPC_ENCHANTER" != "1" ] && [ -d "mod-npc-enchanter" ]; then
  echo 'Removing mod-npc-enchanter (disabled)...'
  rm -rf mod-npc-enchanter
fi

if [ "$MODULE_INSTANCE_RESET" != "1" ] && [ -d "mod-instance-reset" ]; then
  echo 'Removing mod-instance-reset (disabled)...'
  rm -rf mod-instance-reset
fi

if [ "$MODULE_LEVEL_GRANT" != "1" ] && [ -d "mod-quest-count-level" ]; then
  echo 'Removing mod-quest-count-level (disabled)...'
  rm -rf mod-quest-count-level
fi
if [ "$MODULE_ASSISTANT" != "1" ] && [ -d "mod-assistant" ]; then
  echo 'Removing mod-assistant (disabled)...'
  rm -rf mod-assistant
fi
if [ "$MODULE_REAGENT_BANK" != "1" ] && [ -d "mod-reagent-bank" ]; then
  echo 'Removing mod-reagent-bank (disabled)...'
  rm -rf mod-reagent-bank
fi
if [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" != "1" ] && [ -d "mod-black-market" ]; then
  echo 'Removing mod-black-market (disabled)...'
  rm -rf mod-black-market
fi

if [ "$MODULE_CHALLENGE_MODES" != "1" ] && [ -d "mod-challenge-modes" ]; then
  echo 'Removing mod-challenge-modes (disabled)...'
  rm -rf mod-challenge-modes
fi

if [ "$MODULE_OLLAMA_CHAT" != "1" ] && [ -d "mod-ollama-chat" ]; then
  echo 'Removing mod-ollama-chat (disabled)...'
  rm -rf mod-ollama-chat
fi

if [ "$MODULE_PLAYER_BOT_LEVEL_BRACKETS" != "1" ] && [ -d "mod-player-bot-level-brackets" ]; then
  echo 'Removing mod-player-bot-level-brackets (disabled)...'
  rm -rf mod-player-bot-level-brackets
fi

if [ "$MODULE_STATBOOSTER" != "1" ] && [ -d "StatBooster" ]; then
  echo 'Removing StatBooster (disabled)...'
  rm -rf StatBooster
fi

if [ "$MODULE_DUNGEON_RESPAWN" != "1" ] && [ -d "DungeonRespawn" ]; then
  echo 'Removing DungeonRespawn (disabled)...'
  rm -rf DungeonRespawn
fi

if [ "$MODULE_SKELETON_MODULE" != "1" ] && [ -d "skeleton-module" ]; then
  echo 'Removing skeleton-module (disabled)...'
  rm -rf skeleton-module
fi

if [ "$MODULE_BG_SLAVERYVALLEY" != "1" ] && [ -d "mod-bg-slaveryvalley" ]; then
  echo 'Removing mod-bg-slaveryvalley (disabled)...'
  rm -rf mod-bg-slaveryvalley
fi

if [ "$MODULE_AZEROTHSHARD" != "1" ] && [ -d "mod-azerothshard" ]; then
  echo 'Removing mod-azerothshard (disabled)...'
  rm -rf mod-azerothshard
fi

if [ "$MODULE_WORGOBLIN" != "1" ] && [ -d "mod-worgoblin" ]; then
  echo 'Removing mod-worgoblin (disabled)...'
  rm -rf mod-worgoblin
fi

if [ "$MODULE_ELUNA_TS" != "1" ] && [ -d "eluna-ts" ]; then
  echo 'Removing eluna-ts (disabled)...'
  rm -rf eluna-ts
fi

echo 'Installing enabled modules...'

# Playerbots handling - integrated into custom AzerothCore branch
if [ "$MODULE_PLAYERBOTS" = "1" ]; then
  echo '🤖 Playerbots module enabled...'
  echo '   📖 Playerbots are integrated into the uprightbass360/azerothcore-wotlk-playerbots source'
  echo '   ℹ️  No separate module repository needed - functionality built into core'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with playerbots source'
  echo '   📋 POST-INSTALL: Requires manual account/character configuration'
  # No git clone needed - playerbots are integrated into the source tree
fi

# Install AOE Loot if enabled
if [ "$MODULE_AOE_LOOT" = "1" ] && [ ! -d "mod-aoe-loot" ]; then
  echo '💰 Installing mod-aoe-loot...'
  echo '   📖 Project: https://github.com/azerothcore/mod-aoe-loot'
  echo '   ℹ️  Allows looting multiple corpses with one action'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-aoe-loot.git mod-aoe-loot
fi

# Install Learn Spells if enabled
if [ "$MODULE_LEARN_SPELLS" = "1" ] && [ ! -d "mod-learn-spells" ]; then
  echo '📚 Installing mod-learn-spells...'
  echo '   📖 Project: https://github.com/azerothcore/mod-learn-spells'
  echo '   ℹ️  Automatically teaches class spells on level up'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-learn-spells.git mod-learn-spells
fi

# Install Fireworks on Level if enabled
if [ "$MODULE_FIREWORKS" = "1" ] && [ ! -d "mod-fireworks-on-level" ]; then
  echo '🎆 Installing mod-fireworks-on-level...'
  echo '   📖 Project: https://github.com/azerothcore/mod-fireworks-on-level'
  echo '   ℹ️  Displays fireworks when players level up'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-fireworks-on-level.git mod-fireworks-on-level
fi

# Install Individual Progression if enabled
if [ "$MODULE_INDIVIDUAL_PROGRESSION" = "1" ] && [ ! -d "mod-individual-progression" ]; then
  echo '⏳ Installing mod-individual-progression...'
  echo '   📖 Project: https://github.com/ZhengPeiRu21/mod-individual-progression'
  echo '   ℹ️  Simulates authentic Vanilla→TBC→WotLK progression per player'
  echo '   ✅ AUTO-CONFIG: Automatically sets EnablePlayerSettings=1 and DBC.EnforceItemAttributes=0'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   📁 Optional client files available in optional/ directory'
  git clone https://github.com/ZhengPeiRu21/mod-individual-progression.git mod-individual-progression
fi

# Quality of Life Modules
if [ "$MODULE_AHBOT" = "1" ] && [ ! -d "mod-ahbot" ]; then
  echo '🏪 Installing mod-ahbot...'
  echo '   📖 Project: https://github.com/azerothcore/mod-ahbot'
  echo '   ℹ️  Auction house bot that buys and sells items automatically'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   📋 POST-INSTALL: Requires manual account/character setup in mod_ahbot.conf'
  git clone https://github.com/azerothcore/mod-ahbot.git mod-ahbot
fi

if [ "$MODULE_AUTOBALANCE" = "1" ] && [ ! -d "mod-autobalance" ]; then
  echo '⚖️  Installing mod-autobalance...'
  echo '   📖 Project: https://github.com/azerothcore/mod-autobalance'
  echo '   ℹ️  Automatically adjusts dungeon difficulty based on party size'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-autobalance.git mod-autobalance
fi

if [ "$MODULE_TRANSMOG" = "1" ] && [ ! -d "mod-transmog" ]; then
  echo '🎭 Installing mod-transmog...'
  echo '   📖 Project: https://github.com/azerothcore/mod-transmog'
  echo '   ℹ️  Allows appearance customization of equipment'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-transmog.git mod-transmog
fi

if [ "$MODULE_NPC_BUFFER" = "1" ] && [ ! -d "mod-npc-buffer" ]; then
  echo 'Installing mod-npc-buffer...'
  git clone https://github.com/azerothcore/mod-npc-buffer.git mod-npc-buffer
fi

# Gameplay Enhancement Modules
if [ "$MODULE_DYNAMIC_XP" = "1" ] && [ ! -d "mod-dynamic-xp" ]; then
  echo 'Installing mod-dynamic-xp...'
  git clone https://github.com/azerothcore/mod-dynamic-xp.git mod-dynamic-xp
fi

if [ "$MODULE_SOLO_LFG" = "1" ] && [ ! -d "mod-solo-lfg" ]; then
  echo '🔍 Installing mod-solo-lfg...'
  echo '   📖 Project: https://github.com/azerothcore/mod-solo-lfg'
  echo '   ℹ️  Allows dungeon finder for solo players and small groups'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   💡 Pairs perfectly with mod-solocraft and mod-autobalance'
  git clone https://github.com/azerothcore/mod-solo-lfg.git mod-solo-lfg
fi

if [ "$MODULE_1V1_ARENA" = "1" ] && [ ! -d "mod-1v1-arena" ]; then
  echo 'Installing mod-1v1-arena...'
  git clone https://github.com/azerothcore/mod-1v1-arena.git mod-1v1-arena
fi

if [ "$MODULE_PHASED_DUELS" = "1" ] && [ ! -d "mod-phased-duels" ]; then
  echo 'Installing mod-phased-duels...'
  git clone https://github.com/azerothcore/mod-phased-duels.git mod-phased-duels
fi

# Server Management Modules
if [ "$MODULE_BREAKING_NEWS" = "1" ] && [ ! -d "mod-breaking-news-override" ]; then
  echo '📰 Installing mod-breaking-news-override...'
  echo '   📖 Project: https://github.com/azerothcore/mod-breaking-news-override'
  echo '   ℹ️  Displays custom breaking news on character selection screen'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   📋 POST-INSTALL: Requires custom HTML file creation and path configuration'
  git clone https://github.com/azerothcore/mod-breaking-news-override.git mod-breaking-news-override
fi

if [ "$MODULE_BOSS_ANNOUNCER" = "1" ] && [ ! -d "mod-boss-announcer" ]; then
  echo 'Installing mod-boss-announcer...'
  git clone https://github.com/azerothcore/mod-boss-announcer.git mod-boss-announcer
fi

if [ "$MODULE_ACCOUNT_ACHIEVEMENTS" = "1" ] && [ ! -d "mod-account-achievements" ]; then
  echo 'Installing mod-account-achievements...'
  git clone https://github.com/azerothcore/mod-account-achievements.git mod-account-achievements
fi

# Additional Modules Found in Config
if [ "$MODULE_AUTO_REVIVE" = "1" ] && [ ! -d "mod-auto-revive" ]; then
  echo 'Installing mod-auto-revive...'
  git clone https://github.com/azerothcore/mod-auto-revive.git mod-auto-revive
fi

if [ "$MODULE_GAIN_HONOR_GUARD" = "1" ] && [ ! -d "mod-gain-honor-guard" ]; then
  echo 'Installing mod-gain-honor-guard...'
  git clone https://github.com/azerothcore/mod-gain-honor-guard.git mod-gain-honor-guard
fi

if [ "$MODULE_ELUNA" = "1" ] && [ ! -d "mod-eluna" ]; then
  echo '🖥️ Installing mod-eluna...'
  echo '   📖 Project: https://github.com/azerothcore/mod-eluna'
  echo '   ℹ️  Lua scripting engine for custom server functionality'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-eluna.git mod-eluna
fi
if [ "$MODULE_ARAC" = "1" ] && [ ! -d "mod-arac" ]; then
  echo '🌈 Installing mod-arac...'
  echo '   📖 Project: https://github.com/heyitsbench/mod-arac'
  echo '   ℹ️  All Races All Classes - Removes class restrictions'
  echo '   🚨 CRITICAL: Requires DBC file updates and client patch!'
  echo '   📋 POST-INSTALL: Apply Patch-A.MPQ to client WoW/Data/ directory'
  git clone https://github.com/heyitsbench/mod-arac.git mod-arac
fi

if [ "$MODULE_TIME_IS_TIME" = "1" ] && [ ! -d "mod-TimeIsTime" ]; then
  echo 'Installing mod-TimeIsTime...'
  git clone https://github.com/dunjeon/mod-TimeIsTime.git mod-TimeIsTime
fi

if [ "$MODULE_RANDOM_ENCHANTS" = "1" ] && [ ! -d "mod-random-enchants" ]; then
  echo 'Installing mod-random-enchants...'
  git clone https://github.com/azerothcore/mod-random-enchants.git mod-random-enchants
fi

if [ "$MODULE_SOLOCRAFT" = "1" ] && [ ! -d "mod-solocraft" ]; then
  echo '🎯 Installing mod-solocraft...'
  echo '   📖 Project: https://github.com/azerothcore/mod-solocraft'
  echo '   ℹ️  Scales dungeon/raid difficulty for solo players'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   💡 Works well with mod-autobalance and mod-solo-lfg'
  git clone https://github.com/azerothcore/mod-solocraft.git mod-solocraft
fi

if [ "$MODULE_PVP_TITLES" = "1" ] && [ ! -d "mod-pvp-titles" ]; then
  echo 'Installing mod-pvp-titles...'
  git clone https://github.com/azerothcore/mod-pvp-titles.git mod-pvp-titles
fi

if [ "$MODULE_NPC_BEASTMASTER" = "1" ] && [ ! -d "mod-npc-beastmaster" ]; then
  echo 'Installing mod-npc-beastmaster...'
  git clone https://github.com/azerothcore/mod-npc-beastmaster.git mod-npc-beastmaster
fi

if [ "$MODULE_NPC_ENCHANTER" = "1" ] && [ ! -d "mod-npc-enchanter" ]; then
  echo '✨ Installing mod-npc-enchanter...'
  echo '   📖 Project: https://github.com/azerothcore/mod-npc-enchanter'
  echo '   ℹ️  NPC that provides enchanting services'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-npc-enchanter.git mod-npc-enchanter
fi

if [ "$MODULE_INSTANCE_RESET" = "1" ] && [ ! -d "mod-instance-reset" ]; then
  echo 'Installing mod-instance-reset...'
  git clone https://github.com/azerothcore/mod-instance-reset.git mod-instance-reset
fi

if [ "$MODULE_LEVEL_GRANT" = "1" ] && [ ! -d "mod-quest-count-level" ]; then
  echo 'Installing mod-quest-count-level...'
  git clone https://github.com/michaeldelago/mod-quest-count-level.git mod-quest-count-level
fi
if [ "$MODULE_ASSISTANT" = "1" ] && [ ! -d "mod-assistant" ]; then
  echo '🤖 Installing mod-assistant...'
  echo '   📖 Project: https://github.com/noisiver/mod-assistant'
  echo '   ℹ️  NPC (ID: 9000000) providing heirlooms, glyphs, gems, profession services'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/noisiver/mod-assistant.git mod-assistant
fi
if [ "$MODULE_REAGENT_BANK" = "1" ] && [ ! -d "mod-reagent-bank" ]; then
  echo '🏦 Installing mod-reagent-bank...'
  echo '   📖 Project: https://github.com/ZhengPeiRu21/mod-reagent-bank'
  echo '   ℹ️  Reagent banker NPC for storing crafting materials, frees bag space'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/ZhengPeiRu21/mod-reagent-bank.git mod-reagent-bank
fi
if [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" = "1" ] && [ ! -d "mod-black-market" ]; then
  echo '🏴‍☠️ Installing mod-black-market...'
  echo '   📖 Project: https://github.com/Youpeoples/Black-Market-Auction-House'
  echo '   ℹ️  MoP Black Market Auction House backported using Eluna Lua engine'
  echo '   ⚠️  SPECIAL MODULE: Uses Lua scripts, not C++ compilation'
  echo '   🔧 REQUIRES: mod-eluna must be enabled and functional'
  git clone https://github.com/Youpeoples/Black-Market-Auction-House.git mod-black-market

  # Special handling: Copy Lua scripts to lua_scripts directory
  if [ "$MODULE_ELUNA" = "1" ] && [ -d "mod-black-market/Server Files/lua_scripts" ]; then
    echo '   🔧 Integrating Black Market Lua scripts with mod-eluna...'
    mkdir -p /azerothcore/lua_scripts
    cp -r mod-black-market/Server\ Files/lua_scripts/* /azerothcore/lua_scripts/ 2>/dev/null || true
    echo '   ✅ Black Market Lua scripts copied to /azerothcore/lua_scripts directory'
    ls -la /azerothcore/lua_scripts/ | grep -E "\.lua$" || echo "   ℹ️  No .lua files found after copy"
  else
    echo '   ⚠️  WARNING: mod-eluna not enabled - Black Market will not function'
  fi
fi

# Featured catalogue additions
if [ "$MODULE_CHALLENGE_MODES" = "1" ] && [ ! -d "mod-challenge-modes" ]; then
  echo '🏁 Installing mod-challenge-modes...'
  echo '   📖 Project: https://github.com/ZhengPeiRu21/mod-challenge-modes'
  echo '   ℹ️  Adds timed dungeon challenge runs with scaling modifiers'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/ZhengPeiRu21/mod-challenge-modes.git mod-challenge-modes
fi

if [ "$MODULE_OLLAMA_CHAT" = "1" ] && [ ! -d "mod-ollama-chat" ]; then
  echo '🗣️ Installing mod-ollama-chat...'
  echo '   📖 Project: https://github.com/DustinHendrickson/mod-ollama-chat'
  echo '   ℹ️  Integrates playerbots with external LLM dialogue via the Ollama API'
  echo '   ⚠️  Requires MODULE_PLAYERBOTS=1 and OLLAMA service configuration'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/DustinHendrickson/mod-ollama-chat.git mod-ollama-chat
  if [ "$MODULE_PLAYERBOTS" != "1" ]; then
    echo '   ⚠️  WARNING: Playerbots are disabled; enable MODULE_PLAYERBOTS for mod-ollama-chat to function.'
  fi
fi

if [ "$MODULE_PLAYER_BOT_LEVEL_BRACKETS" = "1" ] && [ ! -d "mod-player-bot-level-brackets" ]; then
  echo '📊 Installing mod-player-bot-level-brackets...'
  echo '   📖 Project: https://github.com/DustinHendrickson/mod-player-bot-level-brackets'
  echo '   ℹ️  Keeps playerbot populations balanced across configurable level ranges'
  echo '   ⚠️  Requires MODULE_PLAYERBOTS=1'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/DustinHendrickson/mod-player-bot-level-brackets.git mod-player-bot-level-brackets
  if [ "$MODULE_PLAYERBOTS" != "1" ]; then
    echo '   ⚠️  WARNING: Playerbots are disabled; Level Brackets will be inert until MODULE_PLAYERBOTS=1.'
  fi
fi

if [ "$MODULE_BG_SLAVERYVALLEY" = "1" ] && [ ! -d "mod-bg-slaveryvalley" ]; then
  echo '⚔️  Installing mod-bg-slaveryvalley...'
  echo '   📖 Project: https://github.com/Helias/mod-bg-slaveryvalley'
  echo '   ℹ️  Introduces the custom Slavery Valley battleground'
  echo '   ⚠️  Requires custom DBC/client patch assets for battleground entries'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/Helias/mod-bg-slaveryvalley.git mod-bg-slaveryvalley
fi

if [ "$MODULE_AZEROTHSHARD" = "1" ] && [ ! -d "mod-azerothshard" ]; then
  echo '🧩 Installing mod-azerothshard...'
  echo '   📖 Project: https://github.com/azerothcore/mod-azerothshard'
  echo '   ℹ️  Bundle of AzerothShard quality-of-life tweaks and scripts'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/mod-azerothshard.git mod-azerothshard
fi

if [ "$MODULE_WORGOBLIN" = "1" ] && [ ! -d "mod-worgoblin" ]; then
  echo '🐺 Installing mod-worgoblin...'
  echo '   📖 Project: https://github.com/heyitsbench/mod-worgoblin'
  echo '   ℹ️  Enables Worgen and Goblin as playable races'
  echo '   ⚠️  Requires Patch-W.MPQ (or equivalent) and DBC/DB updates'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/heyitsbench/mod-worgoblin.git mod-worgoblin
fi

if [ "$MODULE_STATBOOSTER" = "1" ] && [ ! -d "StatBooster" ]; then
  echo '📈 Installing StatBooster...'
  echo '   📖 Project: https://github.com/AnchyDev/StatBooster'
  echo '   ℹ️  Random enchant upgrade system for AzerothCore'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/AnchyDev/StatBooster.git StatBooster
fi

if [ "$MODULE_DUNGEON_RESPAWN" = "1" ]; then
  echo '⚠️  DungeonRespawn is temporarily disabled (compilation incompatibility). Skipping until patched.'
  echo '   📖 Project: https://github.com/AnchyDev/DungeonRespawn'
  echo '   ❌ Issue: OnBeforeTeleport function incorrectly marked as override'
  echo '   🔧 Apply compilation fix before re-enabling this module.'
  MODULE_DUNGEON_RESPAWN=0
fi

if [ "$MODULE_DUNGEON_RESPAWN" = "1" ] && [ ! -d "DungeonRespawn" ]; then
  echo '🚪 Installing DungeonRespawn...'
  echo '   📖 Project: https://github.com/AnchyDev/DungeonRespawn'
  echo '   ℹ️  Teleports players back to the dungeon entrance after death'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/AnchyDev/DungeonRespawn.git DungeonRespawn
fi

if [ "$MODULE_SKELETON_MODULE" = "1" ] && [ ! -d "skeleton-module" ]; then
  echo '🦴 Installing skeleton-module...'
  echo '   📖 Project: https://github.com/azerothcore/skeleton-module'
  echo '   ℹ️  Blank starter module for rapid prototyping'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  git clone https://github.com/azerothcore/skeleton-module.git skeleton-module
fi

if [ "$MODULE_ELUNA_TS" = "1" ] && [ ! -d "eluna-ts" ]; then
  echo '🧪 Installing eluna-ts...'
  echo '   📖 Project: https://github.com/azerothcore/eluna-ts'
  echo '   ℹ️  Provides a TypeScript toolchain that transpiles to Eluna Lua scripts'
  echo '   🔧 OPTIONAL: Run npm install && npm run build inside eluna-ts for transpilation features'
  git clone https://github.com/azerothcore/eluna-ts.git eluna-ts
fi

echo 'Managing configuration files...'

# Remove configuration files for disabled modules
if [ "$MODULE_PLAYERBOTS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/playerbots.conf*
fi

if [ "$MODULE_AOE_LOOT" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_aoe_loot.conf*
fi

if [ "$MODULE_LEARN_SPELLS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_learnspells.conf*
fi

if [ "$MODULE_FIREWORKS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_fireworks.conf*
fi

if [ "$MODULE_INDIVIDUAL_PROGRESSION" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/individual_progression.conf*
fi

if [ "$MODULE_AHBOT" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_ahbot.conf*
fi

if [ "$MODULE_AUTOBALANCE" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/AutoBalance.conf*
fi

if [ "$MODULE_TRANSMOG" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/transmog.conf*
fi

if [ "$MODULE_NPC_BUFFER" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/npc_buffer.conf*
fi

if [ "$MODULE_DYNAMIC_XP" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/Individual-XP.conf*
fi

if [ "$MODULE_SOLO_LFG" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/SoloLfg.conf*
fi

if [ "$MODULE_1V1_ARENA" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/1v1arena.conf*
fi

if [ "$MODULE_PHASED_DUELS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/phasedduels.conf*
fi

if [ "$MODULE_BREAKING_NEWS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/breaking_news.conf*
fi

if [ "$MODULE_BOSS_ANNOUNCER" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/boss_announcer.conf*
fi

if [ "$MODULE_ACCOUNT_ACHIEVEMENTS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/account_achievements.conf*
fi

if [ "$MODULE_AUTO_REVIVE" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/AutoRevive.conf*
fi

if [ "$MODULE_GAIN_HONOR_GUARD" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/GainHonorGuard.conf*
fi

if [ "$MODULE_ELUNA" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_eluna.conf*
fi
if [ "$MODULE_ARAC" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/arac.conf*
fi

if [ "$MODULE_TIME_IS_TIME" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod-time_is_time.conf*
fi

if [ "$MODULE_POCKET_PORTAL" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/pocketportal.conf*
fi

if [ "$MODULE_RANDOM_ENCHANTS" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/RandomEnchants.conf*
fi

if [ "$MODULE_SOLOCRAFT" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/Solocraft.conf*
fi

if [ "$MODULE_PVP_TITLES" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_pvptitles.conf*
fi

if [ "$MODULE_NPC_BEASTMASTER" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/npc_beastmaster.conf*
fi

if [ "$MODULE_NPC_ENCHANTER" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/npc_enchanter.conf*
fi

if [ "$MODULE_INSTANCE_RESET" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/instance-reset.conf*
fi

if [ "$MODULE_LEVEL_GRANT" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/levelGrant.conf*
fi

# Install configuration files for enabled modules
for module_dir in mod-*; do
  if [ -d "$module_dir" ]; then
    echo "Installing config files for $module_dir..."
    find "$module_dir" -name "*.conf.dist" -exec cp {} /azerothcore/env/dist/etc/ \; 2>/dev/null || true
  fi
done

if [ "$MODULE_AUTOBALANCE" = "1" ]; then
  if [ -f "/azerothcore/env/dist/etc/AutoBalance.conf.dist" ]; then
    sed -i 's/^AutoBalance\.LevelScaling\.EndGameBoost.*/AutoBalance.LevelScaling.EndGameBoost = false    # disabled pending proper implementation/' \
      /azerothcore/env/dist/etc/AutoBalance.conf.dist || true
  fi
fi

# Load SQL runner if present
if [ -f "/scripts/manage-modules-sql.sh" ]; then
  . /scripts/manage-modules-sql.sh
elif [ -f "/tmp/scripts/manage-modules-sql.sh" ]; then
  . /tmp/scripts/manage-modules-sql.sh
else
  echo "⚠️  SQL helper not found, skipping module SQL execution"
fi

# Execute SQLs for enabled modules (via helper)
SQL_EXECUTION_FAILED=0
if declare -f execute_module_sql_scripts >/dev/null 2>&1; then
  echo 'Executing module SQL scripts...'
  if execute_module_sql_scripts; then
    echo 'SQL execution complete.'
  else
    echo '⚠️  Module SQL scripts reported errors'
    SQL_EXECUTION_FAILED=1
  fi
fi

# Module state tracking and rebuild logic
echo 'Checking for module changes that require rebuild...'

if [ "$MODULES_LOCAL_RUN" = "1" ]; then
  MODULES_STATE_FILE="./.modules_state"
else
  MODULES_STATE_FILE="/modules/.modules_state"
fi
CURRENT_STATE=""
REBUILD_REQUIRED=0

# Create current module state hash
for module_var in MODULE_PLAYERBOTS MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD MODULE_ELUNA MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT MODULE_ARAC MODULE_ASSISTANT MODULE_REAGENT_BANK MODULE_BLACK_MARKET_AUCTION_HOUSE MODULE_CHALLENGE_MODES MODULE_OLLAMA_CHAT MODULE_PLAYER_BOT_LEVEL_BRACKETS MODULE_STATBOOSTER MODULE_DUNGEON_RESPAWN MODULE_SKELETON_MODULE MODULE_BG_SLAVERYVALLEY MODULE_AZEROTHSHARD MODULE_WORGOBLIN MODULE_ELUNA_TS; do
  eval "value=\$$module_var"
  CURRENT_STATE="$CURRENT_STATE$module_var=$value|"
done

# Check if state has changed
if [ -f "$MODULES_STATE_FILE" ]; then
  PREVIOUS_STATE=$(cat "$MODULES_STATE_FILE")
  if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
    echo "🔄 Module configuration has changed - rebuild required"
    REBUILD_REQUIRED=1
  else
    echo "✅ No module changes detected"
  fi
else
  echo "📝 First run - establishing module state baseline"
  REBUILD_REQUIRED=1
fi

# Save current state
echo "$CURRENT_STATE" > "$MODULES_STATE_FILE"

# Check if any C++ modules are enabled (modules requiring source compilation)
# NOTE: mod-playerbots uses pre-built images and doesn't require rebuild
ENABLED_MODULES=""
[ "$MODULE_AOE_LOOT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-aoe-loot"
[ "$MODULE_LEARN_SPELLS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-learn-spells"
[ "$MODULE_FIREWORKS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-fireworks-on-level"
[ "$MODULE_INDIVIDUAL_PROGRESSION" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-individual-progression"
[ "$MODULE_AHBOT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-ahbot"
[ "$MODULE_AUTOBALANCE" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-autobalance"
[ "$MODULE_TRANSMOG" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-transmog"
[ "$MODULE_NPC_BUFFER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-npc-buffer"
[ "$MODULE_DYNAMIC_XP" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-dynamic-xp"
[ "$MODULE_SOLO_LFG" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-solo-lfg"
[ "$MODULE_1V1_ARENA" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-1v1-arena"
[ "$MODULE_PHASED_DUELS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-phased-duels"
[ "$MODULE_BREAKING_NEWS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-breaking-news-override"
[ "$MODULE_BOSS_ANNOUNCER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-boss-announcer"
[ "$MODULE_ACCOUNT_ACHIEVEMENTS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-account-achievements"
[ "$MODULE_AUTO_REVIVE" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-auto-revive"
[ "$MODULE_GAIN_HONOR_GUARD" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-gain-honor-guard"
[ "$MODULE_ELUNA" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-eluna"
[ "$MODULE_TIME_IS_TIME" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-time-is-time"
[ "$MODULE_RANDOM_ENCHANTS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-random-enchants"
[ "$MODULE_SOLOCRAFT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-solocraft"
[ "$MODULE_PVP_TITLES" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-pvp-titles"
[ "$MODULE_NPC_BEASTMASTER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-npc-beastmaster"
[ "$MODULE_NPC_ENCHANTER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-npc-enchanter"
[ "$MODULE_INSTANCE_RESET" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-instance-reset"
[ "$MODULE_LEVEL_GRANT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-quest-count-level"
[ "$MODULE_ARAC" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-arac"
[ "$MODULE_ASSISTANT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-assistant"
[ "$MODULE_REAGENT_BANK" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-reagent-bank"
[ "$MODULE_CHALLENGE_MODES" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-challenge-modes"
[ "$MODULE_OLLAMA_CHAT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-ollama-chat"
[ "$MODULE_PLAYER_BOT_LEVEL_BRACKETS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-player-bot-level-brackets"
[ "$MODULE_STATBOOSTER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES StatBooster"
[ "$MODULE_DUNGEON_RESPAWN" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES DungeonRespawn"
[ "$MODULE_SKELETON_MODULE" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES skeleton-module"
[ "$MODULE_BG_SLAVERYVALLEY" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-bg-slaveryvalley"
[ "$MODULE_AZEROTHSHARD" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-azerothshard"
[ "$MODULE_WORGOBLIN" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-worgoblin"

if [ -n "$ENABLED_MODULES" ]; then
  ENABLED_COUNT=$(echo $ENABLED_MODULES | wc -w)
  echo "🔧 Detected $ENABLED_COUNT enabled C++ modules requiring compilation:"
  for mod in $ENABLED_MODULES; do
    echo "   • $mod"
  done

  if [ "$REBUILD_REQUIRED" = "1" ]; then
    if [ "$RUN_REBUILD_NOW" = "0" ]; then
      echo ""
      echo "🚨 REBUILD REQUIRED 🚨"
      echo "Module configuration has changed. To integrate C++ modules into AzerothCore:"
      echo ""
      echo "1. Stop current services:"
      echo "   docker compose down"
      echo ""
      echo "2. Build with source-based compilation (external process)"
      echo "   ./scripts/rebuild-with-modules.sh (if available)"
      echo ""
      echo "📋 NOTE: Source-based build will compile AzerothCore with all enabled modules"
      echo "⏱️  Expected build time: 15-45 minutes depending on system performance"
      echo ""
    else
      echo "✅ Ready to compile modules"
    fi
  fi
else
  echo "✅ No C++ modules enabled - pre-built containers can be used"
fi

echo 'Module management complete.'

if [ "$MODULES_LOCAL_RUN" = "1" ]; then
  REBUILD_SENTINEL="./.requires_rebuild"
else
  REBUILD_SENTINEL="/modules/.requires_rebuild"
fi
HOST_REBUILD_SENTINEL="${MODULES_HOST_DIR:-}"
if [ -n "$HOST_REBUILD_SENTINEL" ]; then
  HOST_REBUILD_SENTINEL="${HOST_REBUILD_SENTINEL%/}/.requires_rebuild"
fi
if [ "$SQL_EXECUTION_FAILED" = "1" ]; then
  echo "⚠️  SQL execution encountered issues; review logs above."
fi

if [ "$REBUILD_REQUIRED" = "1" ] && [ -n "$ENABLED_MODULES" ]; then
  echo "$ENABLED_MODULES" > "$REBUILD_SENTINEL"
  if [ -n "$HOST_REBUILD_SENTINEL" ]; then
    echo "$ENABLED_MODULES" > "$HOST_REBUILD_SENTINEL" 2>/dev/null || true
  fi
else
  rm -f "$REBUILD_SENTINEL" 2>/dev/null || true
  if [ -n "$HOST_REBUILD_SENTINEL" ]; then
    rm -f "$HOST_REBUILD_SENTINEL" 2>/dev/null || true
  fi
fi

# Optional: keep container alive for inspection in CI/debug contexts
if [ "${MODULES_DEBUG_KEEPALIVE:-0}" = "1" ]; then
  tail -f /dev/null
fi

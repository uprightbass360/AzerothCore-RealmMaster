#!/bin/bash
set -e

echo 'Setting up git user'
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"
git config --global url.https://$GIT_PAT@github.com/.insteadOf https://github.com/

echo 'Initializing module management...'
cd /modules

echo 'Cleaning up disabled modules...'

# Remove modules if disabled
if [ "$MODULE_PLAYERBOTS" != "1" ] && [ -d "mod-playerbots" ]; then
  echo 'Removing mod-playerbots (disabled)...'
  rm -rf mod-playerbots
fi

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

echo 'Installing enabled modules...'

# Install Playerbots if enabled
if [ "$MODULE_PLAYERBOTS" = "1" ] && [ ! -d "mod-playerbots" ]; then
  echo '🤖 Installing mod-playerbots...'
  echo '   📖 Project: https://github.com/liyunfan1223/mod-playerbots'
  echo '   🚨 CRITICAL: REQUIRES Custom AzerothCore branch (liyunfan1223/azerothcore-wotlk/tree/Playerbot)'
  echo '   🚨 INCOMPATIBLE with standard AzerothCore - module will not function properly'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   📋 POST-INSTALL: Requires manual account/character configuration'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/liyunfan1223/mod-playerbots.git mod-playerbots
fi

# Install AOE Loot if enabled
if [ "$MODULE_AOE_LOOT" = "1" ] && [ ! -d "mod-aoe-loot" ]; then
  echo '💰 Installing mod-aoe-loot...'
  echo '   📖 Project: https://github.com/azerothcore/mod-aoe-loot'
  echo '   ℹ️  Allows looting multiple corpses with one action'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/azerothcore/mod-aoe-loot.git mod-aoe-loot
fi

# Install Learn Spells if enabled
if [ "$MODULE_LEARN_SPELLS" = "1" ] && [ ! -d "mod-learn-spells" ]; then
  echo '📚 Installing mod-learn-spells...'
  echo '   📖 Project: https://github.com/azerothcore/mod-learn-spells'
  echo '   ℹ️  Automatically teaches class spells on level up'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/azerothcore/mod-learn-spells.git mod-learn-spells
fi

# Install Fireworks on Level if enabled
if [ "$MODULE_FIREWORKS" = "1" ] && [ ! -d "mod-fireworks-on-level" ]; then
  echo '🎆 Installing mod-fireworks-on-level...'
  echo '   📖 Project: https://github.com/azerothcore/mod-fireworks-on-level'
  echo '   ℹ️  Displays fireworks when players level up'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/azerothcore/mod-eluna.git mod-eluna
fi
if [ "$MODULE_ARAC" = "1" ] && [ ! -d "mod-arac" ]; then
  echo '🌈 Installing mod-arac...'
  echo '   📖 Project: https://github.com/heyitsbench/mod-arac'
  echo '   ℹ️  All Races All Classes - Removes class restrictions'
  echo '   🚨 CRITICAL: Requires DBC file updates and client patch!'
  echo '   📋 POST-INSTALL: Apply Patch-A.MPQ to client WoW/Data/ directory'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/heyitsbench/mod-arac.git mod-arac
fi

if [ "$MODULE_TIME_IS_TIME" = "1" ] && [ ! -d "mod-TimeIsTime" ]; then
  echo 'Installing mod-TimeIsTime...'
  git clone https://github.com/dunjeon/mod-TimeIsTime.git mod-TimeIsTime
fi

if [ "$MODULE_POCKET_PORTAL" = "1" ] && [ ! -d "mod-pocket-portal" ]; then
  echo 'Installing mod-pocket-portal...'
  git clone https://github.com/azerothcore/mod-pocket-portal.git mod-pocket-portal
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/noisiver/mod-assistant.git mod-assistant
fi
if [ "$MODULE_REAGENT_BANK" = "1" ] && [ ! -d "mod-reagent-bank" ]; then
  echo '🏦 Installing mod-reagent-bank...'
  echo '   📖 Project: https://github.com/ZhengPeiRu21/mod-reagent-bank'
  echo '   ℹ️  Reagent banker NPC for storing crafting materials, frees bag space'
  echo '   🔧 REBUILD REQUIRED: Container must be rebuilt with source-based compilation'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
  git clone https://github.com/ZhengPeiRu21/mod-reagent-bank.git mod-reagent-bank
fi
if [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" = "1" ] && [ ! -d "mod-black-market" ]; then
  echo '🏴‍☠️ Installing mod-black-market...'
  echo '   📖 Project: https://github.com/Youpeoples/Black-Market-Auction-House'
  echo '   ℹ️  MoP Black Market Auction House backported using Eluna Lua engine'
  echo '   ⚠️  SPECIAL MODULE: Uses Lua scripts, not C++ compilation'
  echo '   🔧 REQUIRES: mod-eluna must be enabled and functional'
  echo '   🔬 STATUS: IN TESTING - Currently under verification'
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

if [ "$MODULE_ASSISTANT" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_assistant.conf*
fi

if [ "$MODULE_REAGENT_BANK" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_reagent_bank.conf*
fi

if [ "$MODULE_BLACK_MARKET_AUCTION_HOUSE" != "1" ]; then
  rm -f /azerothcore/env/dist/etc/mod_black_market.conf*
fi

# Install configuration files for enabled modules
for module_dir in mod-*; do
  if [ -d "$module_dir" ]; then
    echo "Installing config files for $module_dir..."
    find "$module_dir" -name "*.conf.dist" -exec cp {} /azerothcore/env/dist/etc/ \; 2>/dev/null || true
  fi
done

echo 'Configuration file management complete.'

# Source the SQL module management functions
source /scripts/manage-modules-sql.sh

echo 'Executing module SQL scripts...'
execute_module_sql_scripts

echo 'SQL execution complete.'

# Module state tracking and rebuild logic
echo 'Checking for module changes that require rebuild...'

MODULES_STATE_FILE="/modules/.modules_state"
CURRENT_STATE=""
REBUILD_REQUIRED=0

# Create current module state hash
for module_var in MODULE_PLAYERBOTS MODULE_AOE_LOOT MODULE_LEARN_SPELLS MODULE_FIREWORKS MODULE_INDIVIDUAL_PROGRESSION MODULE_AHBOT MODULE_AUTOBALANCE MODULE_TRANSMOG MODULE_NPC_BUFFER MODULE_DYNAMIC_XP MODULE_SOLO_LFG MODULE_1V1_ARENA MODULE_PHASED_DUELS MODULE_BREAKING_NEWS MODULE_BOSS_ANNOUNCER MODULE_ACCOUNT_ACHIEVEMENTS MODULE_AUTO_REVIVE MODULE_GAIN_HONOR_GUARD MODULE_ELUNA MODULE_TIME_IS_TIME MODULE_POCKET_PORTAL MODULE_RANDOM_ENCHANTS MODULE_SOLOCRAFT MODULE_PVP_TITLES MODULE_NPC_BEASTMASTER MODULE_NPC_ENCHANTER MODULE_INSTANCE_RESET MODULE_LEVEL_GRANT; do
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

# Check if any C++ modules are enabled (all current modules require compilation)
ENABLED_MODULES=""
[ "$MODULE_PLAYERBOTS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-playerbots"
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
[ "$MODULE_ARAC" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-arac"
[ "$MODULE_TIME_IS_TIME" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-time-is-time"
[ "$MODULE_POCKET_PORTAL" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-pocket-portal"
[ "$MODULE_RANDOM_ENCHANTS" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-random-enchants"
[ "$MODULE_SOLOCRAFT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-solocraft"
[ "$MODULE_PVP_TITLES" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-pvp-titles"
[ "$MODULE_NPC_BEASTMASTER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-npc-beastmaster"
[ "$MODULE_NPC_ENCHANTER" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-npc-enchanter"
[ "$MODULE_INSTANCE_RESET" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-instance-reset"
[ "$MODULE_LEVEL_GRANT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-quest-count-level"
[ "$MODULE_ASSISTANT" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-assistant"
[ "$MODULE_REAGENT_BANK" = "1" ] && ENABLED_MODULES="$ENABLED_MODULES mod-reagent-bank"
# Note: mod-black-market is Lua-based, doesn't need C++ compilation

if [ -n "$ENABLED_MODULES" ]; then
  ENABLED_COUNT=$(echo $ENABLED_MODULES | wc -w)
  echo "🔧 Detected $ENABLED_COUNT enabled C++ modules requiring compilation:"
  for mod in $ENABLED_MODULES; do
    echo "   • $mod"
  done

  if [ "$REBUILD_REQUIRED" = "1" ]; then
    echo ""
    echo "🚨 REBUILD REQUIRED 🚨"
    echo "Module configuration has changed. To integrate C++ modules into AzerothCore:"
    echo ""
    echo "1. Stop current services:"
    echo "   docker compose -f docker-compose-azerothcore-services.yml down"
    echo ""
    echo "2. Build with source-based compilation:"
    echo "   docker compose -f /tmp/acore-dev-test/docker-compose.yml build"
    echo "   docker compose -f /tmp/acore-dev-test/docker-compose.yml up -d"
    echo ""
    echo "3. Or use the automated rebuild script (if available):"
    echo "   ./scripts/rebuild-with-modules.sh"
    echo ""
    echo "📋 NOTE: Source-based build will compile AzerothCore with all enabled modules"
    echo "⏱️  Expected build time: 15-45 minutes depending on system performance"
    echo ""
  fi
else
  echo "✅ No C++ modules enabled - pre-built containers can be used"
fi

echo 'Module management complete.'

# Download rebuild script from GitHub for local access
echo '📥 Downloading rebuild-with-modules.sh from GitHub...'
apk add --no-cache curl
if curl -fsSL https://raw.githubusercontent.com/uprightbass360/acore-compose/main/scripts/rebuild-with-modules.sh -o /tmp/rebuild-with-modules.sh 2>/dev/null; then
  echo '✅ Downloaded rebuild-with-modules.sh from GitHub'
  chmod +x /tmp/rebuild-with-modules.sh
  echo '📍 Script available at: /tmp/rebuild-with-modules.sh'
elif [ -f "/project/scripts/rebuild-with-modules.sh" ]; then
  echo '📁 Using local rebuild-with-modules.sh for testing'
  cp /project/scripts/rebuild-with-modules.sh /tmp/rebuild-with-modules.sh
  chmod +x /tmp/rebuild-with-modules.sh
  echo '✅ Copied to /tmp/rebuild-with-modules.sh'
else
  echo '⚠️  Warning: rebuild-with-modules.sh not found in GitHub or locally'
fi

echo 'Keeping container alive...'
tail -f /dev/null
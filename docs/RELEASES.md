# Release Strategy

This document explains how AzerothCore RealmMaster releases work and what they contain.

## Release Philosophy

Since **Docker images are stored on Docker Hub**, GitHub releases serve as **deployment packages** rather than source distributions. Each release contains everything users need to deploy pre-built images without building from source.

## What's in a Release?

### Release Assets (ZIP Archive)

Each release includes a downloadable `.zip` file containing:

```
azerothcore-realmmaster-v1.0.0-realmmaster.zip
├── .env.prebuilt              # Pre-configured for Docker Hub images
├── docker-compose.yml         # Service definitions
├── deploy.sh                  # Deployment script
├── status.sh                  # Status monitoring
├── cleanup.sh                 # Cleanup utilities
├── scripts/                   # Required Python/Bash scripts
├── config/                    # Module manifest and presets
├── docs/                      # Complete documentation
├── QUICKSTART.md             # Release-specific quick start
└── README.md                 # Project overview
```

### Release Notes

Each release includes:
- Module profile and count
- Docker Hub image tags (date-specific and latest)
- Quick start instructions
- Complete module list
- Build information (commit, date, source variant)
- Links to documentation
- Known issues

## Release Types

### 1. Profile-Based Releases

Each module profile gets its own release variant:

- **v1.0.0-realmmaster** - RealmMaster profile (32 modules, recommended)
- **v1.0.0-suggested-modules** - Alternative suggested module set
- **v1.0.0-all-modules** - All supported modules
- **v1.0.0-playerbots-only** - Just playerbots

Users choose the release that matches their desired module set.

### 2. Version Numbering

We use semantic versioning:
- **Major** (v1.0.0 → v2.0.0): Breaking changes, major feature additions
- **Minor** (v1.0.0 → v1.1.0): New modules, feature enhancements
- **Patch** (v1.0.0 → v1.0.1): Bug fixes, documentation updates

## Docker Hub Image Tags

Releases reference specific Docker Hub tags:

### Date-Tagged Images (Recommended for Production)
```
uprightbass360/azerothcore-realmmaster:authserver-realmmaster-20260109
uprightbass360/azerothcore-realmmaster:worldserver-realmmaster-20260109
```
- **Immutable**: Never change
- **Stable**: Guaranteed to match the release
- **Recommended**: For production deployments

### Latest Tags (Auto-Updated)
```
uprightbass360/azerothcore-realmmaster:authserver-realmmaster-latest
uprightbass360/azerothcore-realmmaster:worldserver-realmmaster-latest
```
- **Mutable**: Updated nightly by CI/CD
- **Convenient**: Always get the newest build
- **Use case**: Development, testing, staying current

## Creating a Release

### Automated (Recommended)

Use the GitHub Actions workflow:

1. Go to **Actions** → **Create Release**
2. Click **Run workflow**
3. Fill in:
   - **Version**: `v1.0.0`
   - **Profile**: `RealmMaster` (or other profile)
   - **Pre-release**: Check if beta/RC
4. Click **Run workflow**

The workflow automatically:
- Creates deployment package with all files
- Generates release notes with module list
- Uploads ZIP archive as release asset
- Creates GitHub release with proper tags

### Manual

If you need to create a release manually:

```bash
# 1. Tag the release
git tag -a v1.0.0 -m "Release v1.0.0 - RealmMaster Profile"
git push origin v1.0.0

# 2. Create deployment package
./scripts/create-release-package.sh v1.0.0 RealmMaster

# 3. Create GitHub release
# Go to GitHub → Releases → Draft a new release
# - Tag: v1.0.0
# - Title: RealmMaster v1.0.0 - RealmMaster Profile
# - Upload: azerothcore-realmmaster-v1.0.0-realmmaster.zip
# - Add release notes
```

## Release Checklist

Before creating a release:

- [ ] Verify CI/CD build succeeded
- [ ] Test Docker Hub images work correctly
- [ ] Update CHANGELOG.md
- [ ] Update version in documentation if needed
- [ ] Verify all module SQL migrations are included
- [ ] Test deployment on clean system
- [ ] Update known issues section

## For Users: Using a Release

### Quick Start

```bash
# 1. Download release
wget https://github.com/uprightbass360/AzerothCore-RealmMaster/releases/download/v1.0.0/azerothcore-realmmaster-v1.0.0-realmmaster.zip

# 2. Extract
unzip azerothcore-realmmaster-v1.0.0-realmmaster.zip
cd azerothcore-realmmaster-v1.0.0-realmmaster

# 3. Optional: server address, passwords
nano .env.prebuilt

# 4. Deploy
mv .env.prebuilt .env
./deploy.sh
```

### Upgrading Between Releases

```bash
# 1. Backup your data
./scripts/bash/backup.sh

# 2. Download new release
wget https://github.com/.../releases/download/v1.1.0/...

# 3. Extract to new directory
unzip azerothcore-realmmaster-v1.1.0-realmmaster.zip

# 4. Copy your .env and data
cp old-version/.env new-version/.env
cp -r old-version/storage new-version/storage

# 5. Deploy new version
cd new-version
./deploy.sh
```

## Release Schedule

- **Nightly Builds**: Images built automatically at 2 AM UTC
- **Releases**: Created as needed when significant changes accumulate
- **LTS Releases**: Planned quarterly for long-term support

## Support

- **Release Issues**: https://github.com/uprightbass360/AzerothCore-RealmMaster/issues
- **Documentation**: Included in each release ZIP
- **Discord**: https://discord.gg/gkt4y2x

## FAQ

### Why are images on Docker Hub and not in releases?

Docker images can be 1-2GB each. GitHub has a 2GB file limit and releases should be lightweight. Docker Hub is designed for hosting images, GitHub releases are for deployment packages.

### Can I use latest tags in production?

We recommend **date-tagged images** for production (e.g., `authserver-realmmaster-20260109`). Latest tags are updated nightly and may have untested changes.

### How do I know which image version a release uses?

Check the release notes - they include the specific Docker Hub tags (date-stamped) that were tested with that release.

### What if I want to build from source instead?

Clone the repository and use `./setup.sh` + `./build.sh` instead of using pre-built releases. See [GETTING_STARTED.md](GETTING_STARTED.md) for instructions.

### Are releases required?

No! You can:
1. **Use releases**: Download ZIP, deploy pre-built images (easiest)
2. **Use nightly images**: Pull latest tags directly from Docker Hub
3. **Build from source**: Clone repo, build locally (most flexible)

Releases are just convenient snapshots for users who want stability.

## Upgrade notes: module key rename (October 2026)

Module keys are now derived from the repository name. 73 hand-named keys and
12 same-named duplicates were renamed. A `.env` that still enables an old key
stops the build with a message naming the new key.

**Upgrade in three commands**

```bash
git pull
./modules.sh migrate      # rewrites .env and config/module-manifest.local.json; a .bak-<timestamp> copy is kept
./build.sh                # or ./deploy.sh, as before
```

`migrate` records the rename wave it applied in each file (`MODULES_KEY_SCHEMA=<n>`
in `.env`, `key_schema` in `config/module-manifest.local.json` and in profile
files) and skips waves already applied, so it is safe to run again. A file
from before the markers existed (an `.env` migrated by an earlier `migrate`, a
local manifest, or an old exported profile) may already hold keys that only exist
after a rename wave. `migrate` detects that, refuses with the exact line to add
(for example `MODULES_KEY_SCHEMA=1`, or `"key_schema": 1` in a JSON file), and
writes nothing; add the line it names and run it again.

Profile files exported from the config UI can be passed to the same command:
`./modules.sh migrate my-profile.json`.

**One meaning changed.** `MODULE_MOD_PLAYERBOTS` used to denote maluramichael's
fork of the playerbots module. It now denotes the upstream
mod-playerbots/mod-playerbots. The fork is `MODULE_MOD_PLAYERBOTS_MALURAMICHAEL`.

**Full rename table**

| Old key | New key | Repository |
|---|---|---|
| `MODULE_1V1_ARENA` | `MODULE_MOD_1V1_ARENA` | azerothcore/mod-1v1-arena |
| `MODULE_ACCOUNTWIDE_SYSTEMS` | `MODULE_AZEROTHCORE_ELUNA_ACCOUNTWIDE` | Aldori15/azerothcore-eluna-accountwide |
| `MODULE_ACCOUNT_ACHIEVEMENTS` | `MODULE_MOD_ACCOUNT_ACHIEVEMENTS` | azerothcore/mod-account-achievements |
| `MODULE_ACCOUNT_MOUNTS` | `MODULE_MOD_ACCOUNT_MOUNTS` | azerothcore/mod-account-mounts |
| `MODULE_ACORE_SUBSCRIPTIONS` | `MODULE_MOD_ACORE_SUBSCRIPTIONS` | azerothcore/mod-acore-subscriptions |
| `MODULE_ACTIVE_CHAT` | `MODULE_ACTIVECHAT` | Day36512/ActiveChat |
| `MODULE_AHBOT` | `MODULE_MOD_AHBOT` | azerothcore/mod-ahbot |
| `MODULE_ANTIFARMING` | `MODULE_MOD_ANTIFARMING` | azerothcore/mod-antifarming |
| `MODULE_AOE_LOOT` | `MODULE_MOD_AOE_LOOT` | azerothcore/mod-aoe-loot |
| `MODULE_ARAC` | `MODULE_MOD_ARAC` | heyitsbench/mod-arac |
| `MODULE_ARENA_REPLAY` | `MODULE_MOD_ARENA_REPLAY` | azerothcore/mod-arena-replay |
| `MODULE_ASSISTANT` | `MODULE_MOD_ASSISTANT` | noisiver/mod-assistant |
| `MODULE_AUTOBALANCE` | `MODULE_MOD_AUTOBALANCE` | azerothcore/mod-autobalance |
| `MODULE_AUTO_REVIVE` | `MODULE_MOD_AUTO_REVIVE` | azerothcore/mod-auto-revive |
| `MODULE_AZEROTHSHARD` | `MODULE_MOD_AZEROTHSHARD` | azerothcore/mod-azerothshard |
| `MODULE_BG_SLAVERYVALLEY` | `MODULE_MOD_BG_SLAVERYVALLEY` | Helias/mod-bg-slaveryvalley |
| `MODULE_BOSS_ANNOUNCER` | `MODULE_MOD_BOSS_ANNOUNCER` | azerothcore/mod-boss-announcer |
| `MODULE_BREAKING_NEWS` | `MODULE_MOD_BREAKING_NEWS_OVERRIDE` | azerothcore/mod-breaking-news-override |
| `MODULE_CHALLENGE_MODES` | `MODULE_MOD_CHALLENGE_MODES` | ZhengPeiRu21/mod-challenge-modes |
| `MODULE_DUEL_RESET` | `MODULE_MOD_DUEL_RESET` | azerothcore/mod-duel-reset |
| `MODULE_DYNAMIC_XP` | `MODULE_MOD_DYNAMIC_XP` | azerothcore/mod-dynamic-xp |
| `MODULE_ELUNA` | `MODULE_MOD_ALE` | azerothcore/mod-ale |
| `MODULE_EVENT_SCRIPTS` | `MODULE_ACORE_EVENTSCRIPTS` | 55Honey/Acore_eventScripts |
| `MODULE_EXCHANGE_NPC` | `MODULE_ACORE_EXCHANGENPC` | 55Honey/Acore_ExchangeNpc |
| `MODULE_FIREWORKS` | `MODULE_MOD_FIREWORKS_ON_LEVEL` | azerothcore/mod-fireworks-on-level |
| `MODULE_GAIN_HONOR_GUARD` | `MODULE_MOD_GAIN_HONOR_GUARD` | azerothcore/mod-gain-honor-guard |
| `MODULE_GLOBAL_CHAT` | `MODULE_MOD_GLOBAL_CHAT` | azerothcore/mod-global-chat |
| `MODULE_GLOBAL_MAIL_BANKING_AUCTIONS` | `MODULE_AZEROTHCORE_GLOBAL_MAIL_BANKING_AUCTIONS` | Aldori15/azerothcore-global-mail_banking_auctions |
| `MODULE_GUILDHOUSE` | `MODULE_MOD_GUILDHOUSE` | azerothcore/mod-guildhouse |
| `MODULE_HORADRIC_CUBE` | `MODULE_HORADRIC_CUBE_FOR_WORLD_OF_WARCRAFT` | TITIaio/Horadric-Cube-for-World-of-Warcraft |
| `MODULE_INDIVIDUAL_PROGRESSION` | `MODULE_MOD_INDIVIDUAL_PROGRESSION` | ZhengPeiRu21/mod-individual-progression |
| `MODULE_INSTANCE_RESET` | `MODULE_MOD_INSTANCE_RESET` | azerothcore/mod-instance-reset |
| `MODULE_ITEM_LEVEL_UP` | `MODULE_MOD_ITEM_LEVEL_UP` | azerothcore/mod-item-level-up |
| `MODULE_KEEP_OUT` | `MODULE_MOD_KEEP_OUT` | azerothcore/mod-keep-out |
| `MODULE_LEARN_SPELLS` | `MODULE_MOD_LEARN_SPELLS` | azerothcore/mod-learn-spells |
| `MODULE_LEVEL_UP_REWARD` | `MODULE_ACORE_LEVELUPREWARD` | 55Honey/Acore_LevelUpReward |
| `MODULE_LUA_AH_BOT` | `MODULE_AZEROTHCORE_LUA_AH_BOT` | mostlynick3/azerothcore-lua-ah-bot |
| `MODULE_MORPHSUMMON` | `MODULE_MOD_MORPHSUMMON` | azerothcore/mod-morphsummon |
| `MODULE_MULTIVENDOR` | `MODULE_AZEROTHCORE_LUA_MULTIVENDOR` | Shadowveil-WotLK/AzerothCore-lua-MultiVendor |
| `MODULE_NPC_BEASTMASTER` | `MODULE_MOD_NPC_BEASTMASTER` | azerothcore/mod-npc-beastmaster |
| `MODULE_NPC_BUFFER` | `MODULE_MOD_NPC_BUFFER` | azerothcore/mod-npc-buffer |
| `MODULE_NPC_ENCHANTER` | `MODULE_MOD_NPC_ENCHANTER` | azerothcore/mod-npc-enchanter |
| `MODULE_NPC_FREE_PROFESSIONS` | `MODULE_MOD_NPC_FREE_PROFESSIONS` | azerothcore/mod-npc-free-professions |
| `MODULE_NPC_TALENT_TEMPLATE` | `MODULE_MOD_NPC_TALENT_TEMPLATE` | azerothcore/mod-npc-talent-template |
| `MODULE_OLLAMA_CHAT` | `MODULE_MOD_OLLAMA_CHAT` | DustinHendrickson/mod-ollama-chat |
| `MODULE_PHASED_DUELS` | `MODULE_MOD_PHASED_DUELS` | azerothcore/mod-phased-duels |
| `MODULE_PLAYERBOTS` | `MODULE_MOD_PLAYERBOTS` | mod-playerbots/mod-playerbots |
| `MODULE_PLAYER_BOT_LEVEL_BRACKETS` | `MODULE_MOD_PLAYER_BOT_LEVEL_BRACKETS` | DustinHendrickson/mod-player-bot-level-brackets |
| `MODULE_POCKET_PORTAL` | `MODULE_MOD_POCKET_PORTAL` | azerothcore/mod-pocket-portal |
| `MODULE_PREMIUM` | `MODULE_MOD_PREMIUM` | azerothcore/mod-premium |
| `MODULE_PRESTIGE_DRAFT_MODE` | `MODULE_PRESTIGE_AND_DRAFT_MODE` | Youpeoples/Prestige-and-Draft-Mode |
| `MODULE_PROGRESSION_SYSTEM` | `MODULE_MOD_PROGRESSION_SYSTEM` | azerothcore/mod-progression-system |
| `MODULE_PROMOTION_AZEROTHCORE` | `MODULE_MOD_PROMOTION_AZEROTHCORE` | azerothcore/mod-promotion-azerothcore |
| `MODULE_PVP_TITLES` | `MODULE_MOD_PVP_TITLES` | azerothcore/mod-pvp-titles |
| `MODULE_RANDOM_ENCHANTS` | `MODULE_MOD_RANDOM_ENCHANTS` | azerothcore/mod-random-enchants |
| `MODULE_REAGENT_BANK` | `MODULE_MOD_REAGENT_BANK` | ZhengPeiRu21/mod-reagent-bank |
| `MODULE_RECRUIT_A_FRIEND` | `MODULE_ACORE_RECRUITAFRIEND` | 55Honey/Acore_RecruitAFriend |
| `MODULE_RESURRECTION_SCROLL` | `MODULE_MOD_RESURRECTION_SCROLL` | azerothcore/mod-resurrection-scroll |
| `MODULE_REWARD_PLAYED_TIME` | `MODULE_MOD_REWARD_PLAYED_TIME` | azerothcore/mod-reward-played-time |
| `MODULE_SERVER_AUTO_SHUTDOWN` | `MODULE_MOD_SERVER_AUTO_SHUTDOWN` | azerothcore/mod-server-auto-shutdown |
| `MODULE_SOLOCRAFT` | `MODULE_MOD_SOLOCRAFT` | azerothcore/mod-solocraft |
| `MODULE_SOLO_LFG` | `MODULE_MOD_SOLO_LFG` | azerothcore/mod-solo-lfg |
| `MODULE_SPELL_REGULATOR` | `MODULE_MOD_SPELL_REGULATOR` | azerothcore/mod-spell-regulator |
| `MODULE_SYSTEM_VIP` | `MODULE_MOD_SYSTEM_VIP` | azerothcore/mod-system-vip |
| `MODULE_TIC_TAC_TOE` | `MODULE_MOD_TIC_TAC_TOE` | azerothcore/mod-tic-tac-toe |
| `MODULE_TIME_IS_TIME` | `MODULE_MOD_TIMEISTIME` | dunjeon/mod-TimeIsTime |
| `MODULE_TRANSMOG` | `MODULE_MOD_TRANSMOG` | azerothcore/mod-transmog |
| `MODULE_TRANSMOG_AIO` | `MODULE_AZEROTHCORE_TRANSMOG_3_3_5A` | DanieltheDeveloper/azerothcore-transmog-3.3.5a |
| `MODULE_WAR_EFFORT` | `MODULE_MOD_WAR_EFFORT` | azerothcore/mod-war-effort |
| `MODULE_WEEKEND_XP` | `MODULE_MOD_WEEKEND_XP` | azerothcore/mod-weekend-xp |
| `MODULE_WHO_LOGGED` | `MODULE_MOD_WHO_LOGGED` | azerothcore/mod-who-logged |
| `MODULE_WORGOBLIN` | `MODULE_MOD_WORGOBLIN` | heyitsbench/mod-worgoblin |
| `MODULE_ZONE_DIFFICULTY` | `MODULE_MOD_ZONE_DIFFICULTY` | azerothcore/mod-zone-difficulty |
| `MODULE_MOD_ACCOUNT_MOUNTS` | `MODULE_MOD_ACCOUNT_MOUNTS_RGSON` | rgson/mod-account-mounts (duplicate, suffixed) |
| `MODULE_MOD_AOE_LOOT` | `MODULE_MOD_AOE_LOOT_TERRABYTE_TBWPS` | TerraByte-tbwps/mod-aoe-loot (duplicate, suffixed) |
| `MODULE_MOD_ASSISTANT` | `MODULE_MOD_ASSISTANT_MALURAMICHAEL` | maluramichael/mod-assistant (duplicate, suffixed) |
| `MODULE_MOD_AUTOBALANCE` | `MODULE_MOD_AUTOBALANCE_ARAXIAONLINE` | araxiaonline/mod-autobalance (duplicate, suffixed) |
| `MODULE_MOD_GUILDHOUSE` | `MODULE_MOD_GUILDHOUSE_BRIAN_ALDRIDGE` | Brian-Aldridge/mod-guildhouse (duplicate, suffixed) |
| `MODULE_MOD_LEARN_SPELLS` | `MODULE_MOD_LEARN_SPELLS_VENOMEKPL` | VenomekPL/mod-learn-spells (duplicate, suffixed) |
| `MODULE_MOD_NPC_BEASTMASTER` | `MODULE_MOD_NPC_BEASTMASTER_BRIAN_ALDRIDGE` | Brian-Aldridge/mod-npc-beastmaster (duplicate, suffixed) |
| `MODULE_MOD_OLLAMA_CHAT` | `MODULE_MOD_OLLAMA_CHAT_MALURAMICHAEL` | maluramichael/mod-ollama-chat (duplicate, suffixed) |
| `MODULE_MOD_PLAYERBOTS` | `MODULE_MOD_PLAYERBOTS_MALURAMICHAEL` | maluramichael/mod-playerbots (duplicate, suffixed) |
| `MODULE_MOD_SOLOCRAFT` | `MODULE_MOD_SOLOCRAFT_VALSAN_AZERTY_BOI` | valsan-azerty-boi/mod-solocraft (duplicate, suffixed) |
| `MODULE_MOD_TRANSMOG` | `MODULE_MOD_TRANSMOG_MALURAMICHAEL` | maluramichael/mod-transmog (duplicate, suffixed) |
| `MODULE_MOD_WORGOBLIN` | `MODULE_MOD_WORGOBLIN_ARAXIAONLINE` | araxiaonline/mod-worgoblin (duplicate, suffixed) |

### Fork keys and name collisions

Every GitHub-hosted module now records `fork: true|false`, refreshed nightly. A
fork from an owner other than `azerothcore` carries its owner in the key, and so
does any repository whose bare key another entry already holds. 17 forks that
still had bare keys were renamed; `./modules.sh migrate` handles them like the
rest:

| Old key | New key |
|---|---|
| `MODULE_BGQUEUECHECKER_PLAYERBOTS_HOTFIX` | `MODULE_BGQUEUECHECKER_PLAYERBOTS_HOTFIX_OUTTIETV` |
| `MODULE_DUNGEONRESPAWN` | `MODULE_DUNGEONRESPAWN_MONAKAIBRAHIM_CMYK` |
| `MODULE_MOD_ARAC_UPDATED` | `MODULE_MOD_ARAC_UPDATED_CHROMWOLF` |
| `MODULE_MOD_AUCTIONATOR` | `MODULE_MOD_AUCTIONATOR_ARAXIAONLINE` |
| `MODULE_MOD_CHALLENGE_MODES_HOTFIX` | `MODULE_MOD_CHALLENGE_MODES_HOTFIX_OUTTIETV` |
| `MODULE_MOD_CUSTOMLOGIN` | `MODULE_MOD_CUSTOMLOGIN_BRIAN_ALDRIDGE` |
| `MODULE_MOD_DEAD_MEANS_DEAD_HOTFIX` | `MODULE_MOD_DEAD_MEANS_DEAD_HOTFIX_OUTTIETV` |
| `MODULE_MOD_DYNAMIC_LOOT_RATES_HOTFIX` | `MODULE_MOD_DYNAMIC_LOOT_RATES_HOTFIX_OUTTIETV` |
| `MODULE_MOD_FLY_IN_OLD_WORLD` | `MODULE_MOD_FLY_IN_OLD_WORLD_TRACKMASTERSTEVE` |
| `MODULE_MOD_NPC_ENCHANTER_PROGRESSION` | `MODULE_MOD_NPC_ENCHANTER_PROGRESSION_RECKA50` |
| `MODULE_MOD_PVP_ZONES_HOTFIX` | `MODULE_MOD_PVP_ZONES_HOTFIX_OUTTIETV` |
| `MODULE_MOD_RANDOM_SUFFIX` | `MODULE_MOD_RANDOM_SUFFIX_LOHVHT` |
| `MODULE_MOD_REAGENT_BANK_ACCOUNT_DEPRECATED` | `MODULE_MOD_REAGENT_BANK_ACCOUNT_DEPRECATED_BRIAN_ALDRIDGE` |
| `MODULE_MOD_STAT_BOOSTER` | `MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH` |
| `MODULE_MOD_TRANSMOG_PLUS_UI` | `MODULE_MOD_TRANSMOG_PLUS_UI_MALINMR` |
| `MODULE_NETHERBOT` | `MODULE_NETHERBOT_DAY36512` |
| `MODULE_TELEPORTERWITHCD` | `MODULE_TELEPORTERWITHCD_IMAGIONATIONEDITOR` |

31 repositories that previously shared a name with a listed module, and were
silently merged onto it, are now listed under their own owner-suffixed keys.
The sync PR body lists each new collision under "Name collisions".

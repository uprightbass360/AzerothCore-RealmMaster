# Adding Modules

RealmMaster installs modules listed in `config/module-manifest.json`. You don't edit
that file by hand: a scheduled GitHub Action rebuilds it from GitHub topics and merges
the result into `main`. A hand edit would conflict on your next `git pull` or be
overwritten by the next sync.

This page covers how a module gets into the manifest, how you turn it on, and what
RealmMaster does with each kind of module.

## Getting a module listed

Add one of these topics to the module's GitHub repository:

| Topic | Manifest `type` | Used for |
|---|---|---|
| `azerothcore-module` | `cpp` | C++ modules compiled into the server |
| `azerothcore-lua` | `lua` | Lua scripts run by ALE (mod-ale, formerly Eluna) |
| `azerothcore-sql` | `sql` | SQL-only modules |
| `azerothcore-tools` | `tool` | Tools; cloned when enabled, not part of the server build |

The sync (`.github/workflows/update-module-manifest.yml`) searches these topics,
including forks, and adds every new repository to the manifest. The config UI is
republished after each sync.

- **Key:** the repository name, upper-cased, with non-alphanumerics turned into `_`
  and a `MODULE_` prefix. `lottery-lua` becomes `MODULE_LOTTERY_LUA`. Older curated
  entries may use shorter keys (`MODULE_TRANSMOG` for `mod-transmog`), so look up the
  exact key in the config UI or the manifest.
- **Status:** new entries start `active`. Entries that break the build are later set
  to `blocked` with a `block_reason`, and blocked modules can't be enabled.
- **Removal:** an entry is pruned only if GitHub returns 404/451 for its repository.
  A repository that just drops the topic stays listed.
- **Forks:** a fork of a listed module gets its own key but clones into the same
  folder name. Enable only one of them.

Modules that aren't public GitHub repositories (GitLab, Gitea, private repos), and
pinning a module to a branch, tag or commit, aren't supported yet. A local manifest
and a `./modules.sh add <git-url>` command are planned.

## Enabling a module

Set `MODULE_<KEY>=1` in `.env` and deploy. Other ways to pick modules:

- **Setup:** `./setup.sh --enable-modules MODULE_A,MODULE_B`, or
  `--module-config <profile>` for a profile from `config/module-profiles/`.
- **Config UI:** <https://uprightbass360.github.io/AzerothCore-RealmMaster/> builds a
  `.env` and profile from the catalog.

`./setup.sh` rewrites `.env` and keeps only keys that exist in the manifest.

## What happens to each type

### C++ (`cpp`)

- Cloned into the source tree and compiled in. `./deploy.sh` rebuilds (15–45 minutes)
  when the set of enabled C++ modules differs from the last build.
- AzerothCore calls the module's loader `Add<folder>Scripts()`, where `<folder>` is
  the clone folder (the repository name) with `-` replaced by `_`. `mod-foo` needs
  `void Addmod_fooScripts()`.
- SQL in `data/sql/db-world`, `db-characters`, `db-auth` and `db-playerbots` (and
  their `base/` and `updates/` subfolders), or in the legacy `world`, `characters`,
  `auth` (and their `base/`), is staged and applied by the worldserver. SQL anywhere
  else isn't imported.
- `conf/*.conf.dist` files are copied to `storage/config/modules/`. A `.conf` is
  created from the `.dist` only if you don't already have one.

### Lua (`lua`)

- Lua runs inside the worldserver through ALE and is staged into
  `storage/lua_scripts/<module>/`.
- Staging depends on the manifest entry's `post_install_hooks`:
  - `copy-standard-lua`: `.lua` files in the root, `lua_scripts/`, `scripts/` and
    `Server Files/lua_scripts/`.
  - `copy-lua-tree`: every `.lua` file, keeping subfolders. For modules that `require`
    files from subfolders.
  - `copy-aio-lua`: AIO addon server scripts; the module needs `MODULE_AIO`.
- **Entries created by the sync have no hook, so their Lua is not staged.** A
  maintainer has to add the right hook to the manifest entry. Ask for it in an issue
  or pull request.
- **Lua can take the worldserver down.** Scripts run in-process, and SQL errors are
  fatal to AzerothCore. Eluna-scripts' `lotteryDB.lua` runs invalid SQL at startup and
  crash-loops the worldserver. So large script collections (Eluna-scripts,
  Acore_eventScripts) aren't auto-staged: copy the scripts you want into
  `storage/lua_scripts/` yourself. If the worldserver crash-loops after enabling a Lua
  module, disable the module and deploy again, which removes its staged folder.
- Hook failures are listed at the end of `./deploy.sh`. On the host side, from
  `./build.sh`, they stop the build.

### SQL (`sql`)

SQL in the same `data/sql/...` folders as for C++ modules is staged and applied. No
compile is needed.

## Checking what got installed

- `./deploy.sh` ends with a summary of staged SQL and DBC files and any hook failures.
- Staged Lua: `ls storage/lua_scripts/`
- Module configs: `ls storage/config/modules/`
- Clone and hook details: `docker logs ac-modules`

## See also

- [MODULES.md](MODULES.md): module catalog and profiles
- [MODULE_DBC_FILES.md](MODULE_DBC_FILES.md): modules that ship server DBC files
- [scripts/hooks/README.md](../scripts/hooks/README.md): post-install hooks

# User Modules — Design

**Date:** 2026-09-26
**Status:** Approved in brainstorming, pending spec review

## Problem

Users want to add modules the manifest doesn't carry, typically by supplying a git URL.

`config/module-manifest.json` is populated automatically by the manifest sync workflow
(`.github/workflows/update-module-manifest.yml`), which scans GitHub topics
(`azerothcore-module`, `azerothcore-lua`, `azerothcore-sql`, `azerothcore-tools`,
forks included) weekly, moving to daily. A public GitHub repo carrying one of those
topics therefore already reaches users within a day or so; for that case the answer is
"tag your repo" and no code is needed.

This feature covers what the scraper cannot see:

1. Public GitHub repos without a topic (personal forks, repos the user doesn't own).
2. Non-GitHub hosts (GitLab, Gitea, self-hosted).
3. Overrides of an upstream module: a different `repo` (a fork) or a pinned `ref`.

Private repos are covered only insofar as the host's git credentials already work
(see Non-goals).

### Why not edit `module-manifest.json` directly

The sync auto-merges into that file on every run. Local edits would conflict on nearly
every `git pull` or be overwritten by the next sync, and the sync's pruning
(`--prune-missing`, profile pruning, `.env.template` cleanup, `check_roundtrip.py`)
would strip unknown keys.

## Design overview

- A gitignored, user-owned overlay: `config/module-manifest.local.json`.
- The manifest loader in `scripts/python/modules.py` merges it over the upstream
  manifest. Every consumer reads the merged view through that loader.
- A top-level `./modules.sh` (thin wrapper over new `modules.py` subcommands) adds,
  lists and removes local entries, probing the repo to determine its install type.
- Downstream (clone, `ref` checkout, hooks, conf copy, Lua staging, SQL staging)
  operates on merged manifest entries regardless of origin, with two additions:
  `manage-modules.sh` re-clones an existing checkout when its origin no longer
  matches the module's repo (a fork override added or removed), and `remove` leaves
  a disabled tombstone entry so the next deploy still knows the module and cleans it
  up like any other disabled module.
- C++ rebuilds follow automatically. Adding, enabling or disabling a user C++ module
  changes `MODULES_COMPILE`, and `deploy.sh`/`build.sh` compare that list with the
  last build's record (`local-storage/modules/.built-modules`, from #46).

## 1. Local manifest file

**Path:** `config/module-manifest.local.json`, discovered as a sibling of whatever
manifest path the loader is given. The `ac-modules` container mounts `./config` at
`/tmp/config`, so the sibling is visible there without compose changes.

**Format:** same shape as the upstream manifest, `{"modules": [ ... ]}`.

**Ownership:** added to `.gitignore`. The sync workflow and
`update_module_manifest.py` never read or write it, and `check_roundtrip.py` does not
see it.

### Merge rules (keyed on `key`)

| Local entry | Upstream has key? | Result |
|---|---|---|
| Has `key`, `name`, `repo` | No | Appended as a new module, `source: "local"` |
| Any fields | Yes | Per-field override of the upstream entry, `source: "override"` |
| Missing `name` or `repo` | No (orphaned override) | Warning, entry skipped; build continues |

- Per-field override: only the fields present in the local entry replace upstream
  values. Upstream changes to other fields (description, category, …) keep flowing in
  from the sync, so overrides don't go stale.
- List-valued fields (`requires`, `post_install_hooks`, `config_cleanup`) are
  **replaced**, not concatenated.
- Any field may be overridden, including `status`. Overriding a `blocked` upstream entry
  to non-blocked prints a warning that includes the upstream `block_reason`.
- Upstream entries carry `source: "upstream"` in the merged view.
- Duplicate keys inside the local file are an error, the same as upstream.
- A missing local file is the normal case, not an error. Invalid JSON in the local
  file is an error naming the local path.

An orphaned override arises when the daily sync prunes or renames an upstream entry
that a local partial override (e.g. only `ref`) points at. A local entry that carries
`name` and `repo` survives such a prune as a standalone local module.

### Enabling

Unchanged: `MODULE_<KEY>=1` in `.env`. `setup.sh` builds its known-key list from the
merged manifest, so local keys survive `.env` regeneration
(`scripts/bash/setup/env.sh`).

## 2. Consumers switched to the merged view

Consumers that pass the manifest path to `modules.py` get the merge for free:
`manage-modules.sh`, `rebuild-with-modules.sh`, `start-containers.sh`.

Consumers that read the JSON directly must switch:

| Consumer | Change |
|---|---|
| `scripts/python/setup_manifest.py` | Import the merging loader from `modules.py` |
| `scripts/bash/stage-modules.sh:615` (jq on `server_dbc_path`) | Read from `modules.py manifest --merged` output |
| `scripts/bash/statusjson.sh:90` | Use the merging loader |
| `scripts/python/check_module_staging.py:11` | Use the merging loader |

New `modules.py` subcommand: `manifest --merged` prints the merged manifest JSON
(including `source`) to stdout for bash/jq consumers.

Deliberately **not** switched (upstream-only by design): `update_module_manifest.py`,
`report_missing_modules.py`, `tools/config-ui/*`.

## 3. `./modules.sh`

A top-level script next to `setup.sh` / `build.sh` / `deploy.sh`. Logic lives in
`modules.py` subcommands (`add`, `list`, `remove`); the wrapper resolves paths and
forwards arguments.

```
./modules.sh add <git-url> [--ref <branch|tag|sha>] [--type cpp|lua|sql]
                           [--key MODULE_X] [--no-enable] [--yes]
./modules.sh add --key MODULE_X --ref <ref>           # ref-only override
./modules.sh add <fork-url> --key MODULE_X            # repo override of upstream
./modules.sh list                                     # local entries, enabled state, orphans
./modules.sh remove <MODULE_X>                        # remove local entry, set MODULE_X=0
```

### `add` flow

1. **Normalize the URL** (strip trailing `.git`/slash, the same normalization the
   sync uses). If it matches an upstream entry's repo, stop and say: "Already in the
   manifest as MODULE_X; enable it with MODULE_X=1". Passing `--key` to that same key
   makes it an override instead.
2. **Probe:** a shallow clone (`--depth 1`, at `--ref` if given) into a temp directory,
   removed afterwards. A failure here (bad URL, no access) aborts before anything is
   written.
3. **Detect install type** (section 4).
4. **Derive key and name.** The key uses the sync's `repo_name_to_key` so both paths
   agree. `name` comes from the repo name, adjusted by the C++ loader check. A
   collision with an existing key is refused unless `--key` is explicitly given.
5. **Show the proposed entry and confirm.** `--yes` skips the prompt.
6. **Write atomically** to `config/module-manifest.local.json` (temp file + rename),
   creating the file if absent.
7. **Enable:** set `MODULE_X=1` in `.env` plus any keys in `requires`, printing each
   key enabled. `--no-enable` skips this step.
8. **Validate:** run the `modules.py generate` logic against a temp output dir so
   manifest or `requires` errors show immediately.
9. **Print the next step:** `./build.sh` for C++, otherwise `./deploy.sh`.

### `remove`

- **Local-only module:** replaces the entry with a tombstone (`key`, `name`, `repo`,
  `status: "blocked"`, `block_reason: "removed with ./modules.sh remove"`) and sets
  `MODULE_X=0` in `.env`. Because the key stays in the merged manifest, the next
  `manage-modules.sh` run removes the checkout and the staged Lua folder, SQL staging
  skips it, and it leaves `MODULES_COMPILE`. `list` shows it as `removed`; removing
  it again is refused; `add` of the same URL or key replaces the tombstone.
- **Override:** deletes only the override and leaves `MODULE_X` in `.env` untouched,
  so the module reverts to its upstream `repo`/`ref` on the next run. A message says
  so.

## 4. Install type detection

The rules mirror how the pipeline consumes each type. They are checked in order and
the first match wins; `--type` bypasses detection.

### C++ (`type: cpp`)

**Match:** a `src/` directory containing `.cpp` or `.h` files.

- **Loader name check.** AzerothCore's module loader calls `Add<dir>Scripts()`, where
  `<dir>` is the module directory name with `-` replaced by `_`. The clone directory
  is the entry's `name`. Grep `src/` for `void Add(\w+)Scripts\s*\(`:
  - Exactly one match: set `name` so that it maps to that symbol. If the result
    differs from the repo name, say so.
  - Zero or several matches: warn that the build may fail to link, and keep the repo
    name.
- **Playerbots dependency.** If the source includes `Playerbots.h` or references
  `PlayerbotAI`, add `requires: ["MODULE_PLAYERBOTS"]`.
- **SQL.** Files under `data/sql/{db-world,db-characters,db-auth}` are imported
  automatically by `stage-modules.sh`. If `.sql` files exist elsewhere, warn that they
  will not be imported.
- **Config.** `conf/*.conf.dist` is auto-discovered by `manage-modules.sh`; nothing is
  recorded.

`needs_build` is left to its default (true for `cpp`).

### Lua (`type: lua`)

**Match:** any `.lua` file in the module outside `.git/`.

Pick the staging hook the same way the curated entries do:

| Module shape | Hook | `requires` |
|---|---|---|
| Scripts use AIO (`require("AIO")` / `AIO.`) | `copy-aio-lua` | `MODULE_AIO` |
| Scripts `require` files kept in subfolders, or have no `.lua` in the flat locations `copy-standard-lua` reads (root, `lua_scripts/`, `scripts/`, `Server Files/lua_scripts/`) | `copy-lua-tree` | `MODULE_ELUNA` |
| Otherwise | `copy-standard-lua` | `MODULE_ELUNA` |

For the `require` check, collect the names in `require("X")` calls and see whether
`X.lua` exists only below a subfolder, as `azerothcore-lua-ah-bot` needs.

**Script collections.** If the module has more than 20 `.lua` files, or `.lua` files
spread across several unrelated top-level folders, warn that it looks like a
collection rather than one module. Don't add a hook without explicit confirmation
(`--yes` alone is not enough; require `--type lua`). This is the lesson from
Eluna-scripts and Acore_eventScripts (see Runtime risk).

### SQL (`type: sql`)

**Match:** `.sql` files under `data/sql/…` and no C++ or Lua. SQL outside
`data/sql/{db-world,db-characters,db-auth}` gets the same "will not be imported"
warning as for C++.

### Anything else

Refused with the reason, e.g. "no src/, .lua or data/sql found; this looks like a
tool or client patch". `--type` forces a type.

### Not verified

Whether C++ compiles against the current core. That surfaces in `build.sh`; `--ref` is
the escape hatch for pinning a known-good commit.

## 5. Runtime risk

A user module runs code inside the worldserver, and nothing in the pipeline can prove
it safe. The end-to-end test for #44 showed how badly that can go: Eluna-scripts'
`lotteryDB.lua` ran invalid SQL at startup, AzerothCore treats SQL errors as fatal,
and the worldserver crash-looped.

- `add` prints the warning below whenever it writes an entry, and the docs repeat it:
  "Lua and SQL from this module run inside your worldserver. If the worldserver
  crash-loops after deploying, run `./modules.sh remove <KEY>` and deploy again."
- `remove` plus a deploy must fully undo an `add`. `remove` keeps the entry as a
  disabled tombstone (see §3 `remove`), so the next deploy treats it as a disabled
  module: `remove_disabled_modules` deletes its checkout, `reset_staged_lua` clears
  its Lua folder, SQL staging skips it, and a C++ module leaves the build set. Module
  SQL that was already applied stays in the database; say so in the `remove` output.

## 6. Error handling summary

| Situation | Behaviour |
|---|---|
| Local file missing | Normal; upstream only |
| Local file invalid JSON / duplicate keys | Hard error naming the local file |
| Orphaned partial override | Warning, skipped |
| Local override unblocks a blocked module | Warning including upstream `block_reason` |
| `add`: clone fails | Abort, nothing written |
| `add`: repo already upstream | Abort with the `MODULE_X=1` hint (unless `--key` override) |
| `add`: key collision | Abort unless `--key` given |
| `add`: type undetectable | Abort unless `--type` given |
| `add`: Lua looks like a script collection | Warn; add a hook only with `--type lua` |

## 7. Testing

- **pytest for the merge in `modules.py`:** new key; per-field override; list
  replacement; orphaned override with and without `name`/`repo`; duplicate local keys;
  invalid local JSON; missing local file; `status` override warning.
- **pytest for detection, against fixture directories:** C++ with a single loader
  symbol, a mismatched name, and zero/multiple symbols; playerbots include; C++ with
  stray SQL; Lua standard vs AIO vs tree (subfolder `require`); a collection (>20 files) warns and needs `--type`; SQL-only; undetectable.
- **pytest for `add`/`list`/`remove`:** writes to a temp config dir, `.env` updates,
  key collision, upstream-duplicate detection. Probing is exercised against a local
  bare git repo, with no network.
- **`setup_manifest.py`:** local keys appear in `keys` output.
- **Manual end-to-end on the local stack:** add one small public Lua module and one
  small C++ module, run `./build.sh` and `./deploy.sh`, and confirm both load. Also
  confirm that re-running `setup.sh` keeps the local `MODULE_*` values.

## 8. Docs

- `docs/MODULES.md`: a "Custom / user modules" section covering tagging your repo
  (preferred for public modules), `./modules.sh`, the overlay file format, and
  overrides.
- `docs/GETTING_STARTED.md:254`: replace "edit config/module-manifest.json" with a
  pointer to `./modules.sh`.

## Non-goals

- Credential handling for private repos. A host-side `build.sh` run uses the host's git
  credentials; the `ac-modules` container has none. This is documented rather than
  solved.
- Arbitrary include lists or multiple overlay files.
- Config UI support (see follow-ups).
- Any change to the manifest sync workflow.

## Follow-ups (separate issues)

Open:

1. **Scraped Lua entries lack hooks and `requires`.** 57 upstream Lua entries have
   neither, so enabling one stages nothing. Don't blanket-add hooks during sync: the
   collections showed that staging unreviewed Lua can crash the worldserver. Reuse
   section 4's detection to *suggest* hooks, and have a person review them.
2. **`stage-modules.sh` hard-coded `MODULE_REPO_MAP`** (38 keys). It only drives
   automatic profile selection when playerbots is off and no `--profile` is given.
   Replace it with `MODULES_COMPILE`.
3. **Private repo support:** credentials for clones inside `ac-modules`.
4. **Config UI:** let users drop in `module-manifest.local.json` next to the upstream
   manifest, so local modules appear in the builder.
5. **Manifest types:** `mod-arac` and `mod-aio` are typed `cpp` but have no `src/`, so
   toggling them triggers a no-op rebuild.
6. `manage-modules-sql.sh`/`load_sql_helper` are dead code, and SQL staging applies no
   filter when `modules-enabled.txt` is empty. Both are in the slop-sweep queue.

Resolved by #44, #45 and #46 (merged 2026-09-27), which this design now relies on:

- **Lua staging never reached the worldserver.** Fixed: the `ac-modules` mount,
  per-module folders, `reset_staged_lua`, and the `copy-lua-tree` / `copy-aio-server`
  hooks.
- **`AC_ELUNA_*` never reached mod-ale.** Compose now also sets `AC_ALE_*`.
- **Hook failures were only logged.** They now stop the build, or are reported at the
  end of the deploy.
- **Enabling a C++ module didn't trigger a rebuild.** Fixed with the build record.

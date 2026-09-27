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
- Everything downstream (clone, `ref` checkout, hooks, conf copy, C++ rebuild via
  `MODULES_COMPILE`, SQL staging) is unchanged: it already operates on manifest entries
  regardless of origin.

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

- **Local-only module:** deletes the entry and sets `MODULE_X=0` in `.env`. The
  existing `manage-modules.sh` cleanup removes the cloned directory on the next run.
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

**Match:** `.lua` files at the root, in `lua_scripts/`, in `Server/` or `server/`, or
in `Server Files/lua_scripts/` (the paths the hooks search).

- The scripts reference `AIO` (`require("AIO")` / `AIO.`):
  `requires: ["MODULE_AIO"]`, `post_install_hooks: ["copy-aio-lua"]`.
- Otherwise: `requires: ["MODULE_ELUNA"]`, `post_install_hooks: ["copy-standard-lua"]`.

This matches the 25 curated Lua entries in the upstream manifest.

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

## 5. Error handling summary

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

## 6. Testing

- **pytest for the merge in `modules.py`:** new key; per-field override; list
  replacement; orphaned override with and without `name`/`repo`; duplicate local keys;
  invalid local JSON; missing local file; `status` override warning.
- **pytest for detection, against fixture directories:** C++ with a single loader
  symbol, a mismatched name, and zero/multiple symbols; playerbots include; C++ with
  stray SQL; Lua standard vs AIO; SQL-only; undetectable.
- **pytest for `add`/`list`/`remove`:** writes to a temp config dir, `.env` updates,
  key collision, upstream-duplicate detection. Probing is exercised against a local
  bare git repo, with no network.
- **`setup_manifest.py`:** local keys appear in `keys` output.
- **Manual end-to-end on the local stack:** add one small public Lua module and one
  small C++ module, run `./build.sh` and `./deploy.sh`, and confirm both load. Also
  confirm that re-running `setup.sh` keeps the local `MODULE_*` values.

## 7. Docs

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

1. **Lua staging is broken for all modules (confirmed 2026-09-26 on the local
   stack).** `manage-modules.sh:143` hard-codes
   `LUA_SCRIPTS_TARGET=/azerothcore/lua_scripts`, and `ac-modules` does not mount
   `storage/lua_scripts`.
   - **Evidence:** the `ac-modules` log shows `copy-standard-lua` reporting "Copied
     10 Lua script(s) to /azerothcore/lua_scripts", but that path lives in the
     container's own filesystem and is discarded when it exits. Host
     `storage/lua_scripts`, which the worldserver mounts, is empty even though three
     copy-hook modules are enabled and cloned (364 `.lua` files between them).
   - **Host path (`build.sh`):** it exports `MODULES_LUA_TARGET_DIR`, which nothing
     reads, so the hook targets `/azerothcore/lua_scripts` on the host.
   - **Side issues:**
     - `export MODULE_NAME=…` targets an associative array, so hooks receive an empty
       `MODULE_NAME` (visible as "Processing " with a blank name).
     - The hooks flatten files by basename, so files from different modules can
       overwrite each other.
     - Nothing removes a disabled module's Lua files.

   This directly affects user Lua modules and blocks their end-to-end test.
2. **Scraped Lua entries lack hooks and `requires`.** 57 upstream Lua entries have
   neither, so enabling one may stage nothing. Reuse the section 4 detection in
   `update_module_manifest.py` to fill them in during sync.
3. **`stage-modules.sh` hard-coded `MODULE_REPO_MAP`** (`:299-338`, 38 keys). It only
   drives automatic profile selection when playerbots is off and no `--profile` is
   given. Replace it with `MODULES_COMPILE` so any C++ module selects
   `services-modules`.
4. **Private repo support:** credentials for clones inside `ac-modules` (for example a
   mounted git credential helper or a token env var).
5. **Config UI:** let users drop in `module-manifest.local.json` alongside the upstream
   manifest so local modules appear in the builder.
6. **Dead code:** `manage-modules-sql.sh` and `load_sql_helper` are loaded but never
   called (`manage-modules.sh:540-567`). Remove them or wire them in.
7. **SQL staging with an empty enabled list:** when `modules-enabled.txt` is empty,
   `stage-modules.sh:285-296` applies no filter and stages SQL from every module
   directory. Confirm whether this is intended.

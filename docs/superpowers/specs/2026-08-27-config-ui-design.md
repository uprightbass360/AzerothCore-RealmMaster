# Config UI — Static Web Builder for Module Profiles and Settings Presets

**Date:** 2026-08-27
**Status:** Approved design, pending implementation plan

## Purpose

A simple, easy-to-maintain web UI for building the configuration artifacts
that RealmMaster's bash tooling consumes:

1. **Module profiles** — `config/module-profiles/*.json`
2. **Settings presets** — `config/presets/*.conf`
3. **`.env` module flag blocks** — `MODULE_*=1` lines for patching an
   existing install

The UI is an *authoring tool only*. It never runs setup, deploys, or touches
a server. Users download (or copy) the generated files, place them in the
repo, and review with `git diff` before committing. `setup.sh` and
`deploy.sh` remain the only paths that act on configuration.

## Decisions already made

| Decision | Choice |
|---|---|
| Scope | Author config files only; no deploy/admin actions |
| Hosting | Static page; GitHub Pages via a workflow, plus local `http.server` mode |
| Artifacts | Module profiles, settings presets, `.env` flag blocks |
| Editing | Import + edit existing files (repo dropdown and drag-and-drop) |
| Data source | Live repo data fetched at load; no embedded/baked snapshot |
| Stack | Vanilla HTML/CSS/JS; no framework, no npm, no build/compile step |

## Architecture

```
tools/config-ui/
  index.html      # page shell, three tabs
  app.js          # all behavior (fetch, render, import, export, validate)
  style.css       # styling
  serve.sh        # local mode: regen index.json, run python3 -m http.server
.github/workflows/
  config-ui-pages.yml   # publish page + config data to GitHub Pages
```

No dependencies are vendored or installed. Total maintained surface: one
HTML file, one JS file, one CSS file, one ~30-line workflow, one ~5-line
serve script.

### Data the page reads at load (relative fetches)

- `config/module-manifest.json` — the 541-entry module catalogue: `key`,
  `name`, `description`, `category`, `status`, `requires`, `order`.
- `config/index.json` — **generated** (by the workflow or `serve.sh`, never
  committed): lists the profile and preset files that exist, since a static
  page cannot enumerate directories.
- `config/module-profiles/<name>.json` and `config/presets/<name>.conf` —
  fetched on demand when chosen as a starting point.

If the fetches fail (page opened via `file://`), the page degrades to
drag-and-drop/file-picker for both the manifest and any starting files. It
must not render a broken page; it shows what it needs and how to provide it.

### Publishing (the only "build")

`config-ui-pages.yml` runs on push to `main`:

1. Assemble an artifact directory: `tools/config-ui/*` at the root plus a
   copy of `config/module-manifest.json`, `config/module-profiles/`, and
   `config/presets/` under `config/`.
2. Generate `config/index.json` (a JSON object with `profiles: []` and
   `presets: []` filename arrays) via a few lines of shell.
3. Deploy with `actions/upload-pages-artifact` + `actions/deploy-pages`.

There is no transform of any file — the deployed data is byte-identical to
`main`, so the UI can never drift from the repo. Manifest syncs republish
automatically.

### Local mode

`tools/config-ui/serve.sh` writes `config/index.json` in the working copy
(the path is gitignored) and runs `python3 -m http.server` from the repo
root, printing the URL to open. Same page, same relative paths, reading the
checkout instead of `main`.

## UI behavior

Three tabs. A shared header holds the data-source status (module count
loaded, repo vs. local file) and the import drop target.

### Tab 1: Module Profile

- Modules grouped by `category`, ordered by manifest `order`; a search box
  filters by key, name, and description text.
- Each module renders as a checkbox row with name, key, one-line
  description, and status badge (e.g. `active`).
- **Dependency hints:** when a checked module's `requires` entries are not
  all checked, show a warning badge on the module and a one-click "add
  required" action. Warn, never auto-check silently.
- Metadata fields: profile name (filename), `label`, `description`, `order`.
- **Start from:** dropdown of repo profiles (from `index.json`) that
  pre-ticks the selection; drag-and-drop of a local profile JSON does the
  same.
- **Export:** downloads `<name>.json` matching the existing format exactly:
  `{"modules": [...], "label": "...", "description": "...", "order": N}`
  with modules in manifest order.

### Tab 2: Settings Preset

- Form sections for the knobs used by the existing presets: XP/drop rates,
  level cap, cross-faction interaction toggles, death/corpse settings,
  grouped under their target file heading (`[worldserver.conf]`).
- A free-form key=value table per target file for any setting not covered
  by the form. Imported keys the form does not recognize land here —
  round-trips are lossless, nothing is dropped.
- Metadata fields: preset name (filename), `CONFIG_NAME`,
  `CONFIG_DESCRIPTION`.
- **Start from:** dropdown of repo presets; drag-and-drop of a `.conf` also
  supported.
- **Export:** downloads `<name>.conf` with the `# CONFIG_NAME:` /
  `# CONFIG_DESCRIPTION:` header comments and `[file]` sections the setup
  flow parses.

### Tab 3: .env Flags

- Renders the `MODULE_KEY=1` / `MODULE_KEY=0` block derived from the Module
  Profile tab's current selection (all manifest modules listed, selected
  ones set to 1), with a copy-to-clipboard button.
- **Import:** dropping a `.env` pre-ticks the Module Profile selection from
  its `MODULE_*=1` lines (other `.env` content is ignored, never exported).

## Validation

- On import, module keys are checked against the manifest. Unknown keys
  (typos, removed modules) are listed in a visible warning and excluded
  from export unless the user explicitly keeps them.
- Export refuses an empty profile name or a name that isn't a safe filename
  (`[a-zA-Z0-9._-]`).
- Preset values are exported verbatim; the form does not second-guess
  worldserver semantics (that's the server's job).

## Error handling

- Fetch failures show a per-resource message with the fallback action
  (file picker), not a blank page.
- Malformed imported JSON/conf shows the parse error and leaves current UI
  state untouched.
- The page never writes anywhere except via the browser download/clipboard;
  there is no failure mode that can corrupt repo or server state.

## Testing

- **Round-trip check (primary):** a small Python script,
  `tools/config-ui/check_roundtrip.py`, that drives the same parse/serialize
  rules as `app.js` re-implemented minimally (profile JSON and preset conf
  are trivial formats): import every file in `config/module-profiles/` and
  `config/presets/`, export, and diff against the original. Run manually
  and as a step in the Pages workflow; a mismatch fails the deploy.
- **Manual smoke:** open via `serve.sh`, build one profile and one preset,
  verify downloads match hand-written equivalents.
- No JS test framework is introduced; keeping the formats trivial is the
  test strategy.

## Out of scope (explicitly)

- Running setup/deploy/rebuild from the UI
- Live server status, log viewing, or any admin-panel features
- Authentication (nothing mutable is exposed)
- Editing `docker-compose.yml`, `.env` non-module settings, or the module
  manifest itself
- Framework/tooling adoption (React, bundlers, npm)

## Risks and mitigations

- **Manifest schema drift** (fields renamed/added): the page reads only
  `key`, `name`, `description`, `category`, `status`, `requires`, `order`,
  and tolerates missing optional fields. The round-trip check in the
  workflow catches format breakage on every push.
- **Pages exposure:** the deployed site is read-only data already public in
  the repo; no secrets are copied into the artifact (only
  `module-manifest.json`, `module-profiles/`, `presets/`).
- **`serve.sh` index staleness locally:** regenerated on every run of
  `serve.sh`; the file is gitignored so it cannot leak into commits.

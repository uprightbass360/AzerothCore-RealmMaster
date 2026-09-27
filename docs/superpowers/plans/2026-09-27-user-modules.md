# User Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users add modules the GitHub-topic sync can't see (non-GitHub hosts, untagged repos, forks, pinned refs) through a gitignored `config/module-manifest.local.json` and a `./modules.sh add|list|remove` command.

**Architecture:** A small loader (`scripts/python/manifest_overlay.py`) merges the local file over the upstream manifest by `key`. `modules.py`'s `build_state` and the remaining direct manifest readers use it, so everything downstream (clone, hooks, Lua/SQL staging, C++ rebuild detection) works on local entries unchanged. `./modules.sh` wraps `scripts/python/local_modules.py`, which probes a repo with a shallow clone, detects its install type (`scripts/python/module_detect.py`), and writes the local file and `.env`.

**Tech Stack:** Python 3 standard library only (the repo has no Python dependencies), with `unittest` tests. Bash wrapper, git.

**Spec:** `docs/superpowers/specs/2026-09-26-user-modules-design.md`

## Global Constraints

- Local file path: `config/module-manifest.local.json`, found as a sibling of whatever manifest path the loader is given. Gitignored. Same shape as upstream: `{"modules": [ ... ]}`.
- The upstream manifest is never written by this feature, and neither the sync (`update_module_manifest.py`), `report_missing_modules.py` nor `tools/config-ui/*` reads the local file.
- Merge is keyed on `key`. A local entry for an upstream key is a **per-field** override, and list fields are **replaced**, not concatenated. A local entry for an unknown key needs `name` and `repo`; otherwise it is warned about and skipped. Merged entries carry `source`: `"upstream"`, `"override"` or `"local"`.
- A missing local file is normal. Invalid JSON, a non-list `modules`, entries without a string `key`, or duplicate keys in the local file are errors that name the local path.
- Overriding a `blocked` upstream entry to non-blocked warns, quoting the upstream `block_reason`.
- New keys come from the sync's `repo_name_to_key` (`scripts/python/update_module_manifest.py`), so both paths derive the same key.
- `add` refuses: a URL already in the merged manifest (unless `--key` names that entry), a key collision (unless `--key`), an undetectable type (unless `--type`), and a Lua script collection (unless `--type lua`; `--yes` alone is not enough).
- `add` always prints: "Lua and SQL from this module run inside your worldserver. If the worldserver crash-loops after deploying, run `./modules.sh remove <KEY>` and deploy again."
- `remove`: for a local-only entry, delete it and set `MODULE_X=0`. For an override, delete only the override and leave `.env` alone. Always say that SQL already applied stays in the database.
- Tests use `python3 -m unittest`, with no network access (git tests use local repositories).

## Deviations from the spec (decided while planning)

1. **`add`/`list`/`remove` live in `scripts/python/local_modules.py`, not as `modules.py` subcommands.** `modules.py` already has a `list` subcommand (compile/enabled/keys lists) and is ~700 lines.
2. **The C++ loader check warns instead of renaming the entry.** Prod shows `mod-TimeIsTime` compiling with only `AddTimeIsTimeScripts` defined, so a mismatch isn't reliably fatal, and renaming the clone folder would change a working layout. The warning names the loader AzerothCore will look for.
3. **`scripts/python/check_module_staging.py` is deleted rather than switched.** It has no callers and resolves its own paths wrongly (`parents[1]` → `scripts/`); the slop sweep lists it as dead code.
4. **Tests use `unittest`, not pytest.** The repo has no Python test setup; `unittest` needs no dependency.

## Review Focus

1. **URL variants of the same repo** (trailing `/`, `.git`, letter case, `http` vs `https`): `add` must treat them as the same repo for duplicate detection. Pinned in Task 5 (`test_normalize_repo_variants`) and Task 6 (`test_add_rejects_upstream_repo_with_git_suffix`).
2. **`.env` shapes:** a missing trailing newline, `export KEY=` lines, the key appearing twice, a missing `.env`. `set_env_value` must update in place without breaking other lines. Pinned in Task 5.
3. **`--ref` as a commit SHA:** `git clone --branch <sha>` fails, so the probe must fall back to clone + checkout. Pinned in Task 5 (`test_probe_clone_commit_sha`).
4. **A hand-edited, broken local file:** `add`/`remove` must abort with the file named, and never overwrite it. Pinned in Task 6 (`test_add_refuses_when_local_file_is_invalid`) and Task 7.
5. **Running `add` twice for the same URL:** the second run must say it's already added under its key, not create a second entry. Pinned in Task 6 (`test_add_twice_same_url_is_rejected`).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/python/manifest_overlay.py` (new) | Find, load and validate the local file; merge it over upstream entries; `load_merged_manifest()` for callers that read JSON directly |
| `scripts/python/modules.py` (modify) | `build_state` uses the overlay; `ModuleState.source`; new `manifest --merged` subcommand |
| `scripts/python/setup_manifest.py` (modify) | Read the merged manifest so `setup.sh` knows local keys |
| `scripts/bash/statusjson.sh` (modify) | Read the merged manifest for the status module list |
| `scripts/bash/stage-modules.sh` (modify) | DBC path lookup from the merged manifest |
| `scripts/python/check_module_staging.py` (delete) | Dead, broken |
| `scripts/python/module_detect.py` (new) | Inspect a checked-out module: type, hooks, requires, warnings, collection flag |
| `scripts/python/local_modules.py` (new) | CLI: `add`, `list`, `remove`; URL normalisation; `.env` editing; atomic local-file writes; probe clone |
| `modules.sh` (new, repo root) | Thin wrapper around `local_modules.py` |
| `scripts/python/tests/` (new) | `unittest` tests: `test_manifest_overlay.py`, `test_modules_merged.py`, `test_setup_manifest_merged.py`, `test_module_detect.py`, `test_local_modules_helpers.py`, `test_local_modules_cli.py`, and shared `helpers.py` |
| `.gitignore` (modify) | Ignore `config/module-manifest.local.json` |
| `docs/ADDING_MODULES.md`, `docs/GETTING_STARTED.md` (modify) | Document `./modules.sh` |

Run all Python tests with:

```bash
python3 -m unittest discover -s scripts/python/tests -t scripts/python -v
```

---

### Task 1: Overlay loader

**Files:**
- Create: `scripts/python/manifest_overlay.py`
- Create: `scripts/python/tests/__init__.py` (empty)
- Create: `scripts/python/tests/helpers.py`
- Create: `scripts/python/tests/test_manifest_overlay.py`
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - `LOCAL_MANIFEST_NAME = "module-manifest.local.json"`
  - `class ManifestError(ValueError)`
  - `local_manifest_path(manifest_path: Path) -> Path`
  - `load_local_entries(local_path: Path) -> List[dict]`: `[]` if the file is missing, raises `ManifestError` otherwise
  - `merge_manifest(upstream: List[dict], local: List[dict]) -> Tuple[List[dict], List[str]]`: merged entries (each with `source`) and warnings
  - `load_merged_manifest(manifest_path: Path) -> Tuple[List[dict], List[str]]`: reads the upstream JSON (`modules` list) plus the sibling local file
  - `helpers.write_manifest(path: Path, modules: List[dict]) -> Path`, `helpers.entry(key, **fields) -> dict`

- [ ] **Step 1: Write the test helpers and failing tests**

`scripts/python/tests/__init__.py`: empty file.

`scripts/python/tests/helpers.py`:

```python
"""Shared helpers for scripts/python tests."""
import json
from pathlib import Path
from typing import List


def write_manifest(path: Path, modules: List[dict]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"modules": modules}, indent=2) + "\n")
    return path


def entry(key: str, **fields) -> dict:
    base = {"key": key, "name": key.lower().replace("_", "-"), "repo": f"https://github.com/example/{key.lower()}.git"}
    base.update(fields)
    return base
```

`scripts/python/tests/test_manifest_overlay.py`:

```python
import tempfile
import unittest
from pathlib import Path

from manifest_overlay import (
    ManifestError,
    load_local_entries,
    load_merged_manifest,
    local_manifest_path,
    merge_manifest,
)
from tests.helpers import entry, write_manifest


class MergeManifestTest(unittest.TestCase):
    def test_upstream_only_gets_source_upstream(self):
        merged, warnings = merge_manifest([entry("MODULE_A")], [])
        self.assertEqual(merged[0]["source"], "upstream")
        self.assertEqual(warnings, [])

    def test_new_local_entry_is_appended(self):
        merged, _ = merge_manifest([entry("MODULE_A")], [entry("MODULE_MINE")])
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_MINE"])
        self.assertEqual(merged[1]["source"], "local")

    def test_override_is_per_field(self):
        up = entry("MODULE_A", description="upstream text", ref=None)
        merged, _ = merge_manifest([up], [{"key": "MODULE_A", "ref": "v1.2"}])
        self.assertEqual(merged[0]["ref"], "v1.2")
        self.assertEqual(merged[0]["description"], "upstream text")
        self.assertEqual(merged[0]["repo"], up["repo"])
        self.assertEqual(merged[0]["source"], "override")

    def test_override_replaces_lists(self):
        up = entry("MODULE_A", requires=["MODULE_X", "MODULE_Y"])
        merged, _ = merge_manifest([up], [{"key": "MODULE_A", "requires": ["MODULE_Z"]}])
        self.assertEqual(merged[0]["requires"], ["MODULE_Z"])

    def test_override_keeps_upstream_position(self):
        merged, _ = merge_manifest(
            [entry("MODULE_A"), entry("MODULE_B")], [{"key": "MODULE_A", "ref": "x"}]
        )
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_B"])

    def test_orphaned_partial_override_is_skipped_with_warning(self):
        merged, warnings = merge_manifest([entry("MODULE_A")], [{"key": "MODULE_GONE", "ref": "v1"}])
        self.assertEqual([m["key"] for m in merged], ["MODULE_A"])
        self.assertEqual(len(warnings), 1)
        self.assertIn("MODULE_GONE", warnings[0])

    def test_orphan_with_name_and_repo_becomes_local(self):
        merged, warnings = merge_manifest([], [entry("MODULE_GONE")])
        self.assertEqual(merged[0]["source"], "local")
        self.assertEqual(warnings, [])

    def test_unblocking_override_warns_with_reason(self):
        up = entry("MODULE_A", status="blocked", block_reason="breaks the build")
        merged, warnings = merge_manifest([up], [{"key": "MODULE_A", "status": "active"}])
        self.assertEqual(merged[0]["status"], "active")
        self.assertEqual(len(warnings), 1)
        self.assertIn("breaks the build", warnings[0])

    def test_local_source_field_is_ignored(self):
        merged, _ = merge_manifest([], [dict(entry("MODULE_MINE"), source="upstream")])
        self.assertEqual(merged[0]["source"], "local")

    def test_inputs_are_not_mutated(self):
        up = entry("MODULE_A")
        local = {"key": "MODULE_A", "ref": "v1"}
        merge_manifest([up], [local])
        self.assertNotIn("source", up)
        self.assertNotIn("ref", up)


class LoadLocalEntriesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_missing_file_is_empty(self):
        self.assertEqual(load_local_entries(self.tmp / "nope.json"), [])

    def test_invalid_json_names_the_file(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text("{not json")
        with self.assertRaises(ManifestError) as ctx:
            load_local_entries(path)
        self.assertIn(str(path), str(ctx.exception))

    def test_modules_must_be_a_list(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text('{"modules": {}}')
        with self.assertRaises(ManifestError):
            load_local_entries(path)

    def test_entry_needs_string_key(self):
        path = write_manifest(self.tmp / "module-manifest.local.json", [{"name": "x"}])
        with self.assertRaises(ManifestError):
            load_local_entries(path)

    def test_duplicate_keys_are_an_error(self):
        path = write_manifest(self.tmp / "module-manifest.local.json", [entry("MODULE_A"), {"key": "MODULE_A"}])
        with self.assertRaises(ManifestError) as ctx:
            load_local_entries(path)
        self.assertIn("MODULE_A", str(ctx.exception))


class LoadMergedManifestTest(unittest.TestCase):
    def test_reads_sibling_local_file(self):
        tmp = Path(tempfile.mkdtemp())
        manifest = write_manifest(tmp / "module-manifest.json", [entry("MODULE_A")])
        write_manifest(local_manifest_path(manifest), [entry("MODULE_MINE")])
        merged, warnings = load_merged_manifest(manifest)
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_MINE"])
        self.assertEqual(warnings, [])

    def test_local_path_is_a_sibling(self):
        self.assertEqual(
            local_manifest_path(Path("/tmp/config/module-manifest.json")),
            Path("/tmp/config/module-manifest.local.json"),
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: ERROR, `ModuleNotFoundError: No module named 'manifest_overlay'`.

- [ ] **Step 3: Implement `scripts/python/manifest_overlay.py`**

```python
#!/usr/bin/env python3
"""
Merge the user-owned local manifest over the upstream module manifest.

config/module-manifest.json is generated from GitHub topics and auto-merged by
CI, so users never edit it. They add modules, or override fields of upstream
ones (repo for a fork, ref for a pin), in the gitignored sibling file
config/module-manifest.local.json. Merge rules (keyed on "key"):

- local key not upstream, with name and repo -> appended, source "local"
- local key upstream                       -> per-field override, source "override"
  (lists are replaced, not concatenated)
- local key not upstream, missing name/repo -> warning, skipped (orphaned override)
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Dict, List, Tuple

LOCAL_MANIFEST_NAME = "module-manifest.local.json"


class ManifestError(ValueError):
    """The local manifest file is unusable."""


def local_manifest_path(manifest_path: Path) -> Path:
    return Path(manifest_path).with_name(LOCAL_MANIFEST_NAME)


def load_local_entries(local_path: Path) -> List[dict]:
    local_path = Path(local_path)
    if not local_path.exists():
        return []
    try:
        data = json.loads(local_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ManifestError(
            f"Invalid JSON in local manifest {local_path}: line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc
    modules = data.get("modules") if isinstance(data, dict) else None
    if not isinstance(modules, list):
        raise ManifestError(f"Local manifest {local_path} must define a top-level 'modules' array")
    seen: set = set()
    for idx, item in enumerate(modules):
        if not isinstance(item, dict) or not isinstance(item.get("key"), str) or not item["key"]:
            raise ManifestError(f"Local manifest {local_path}: entry {idx} must be an object with a string 'key'")
        if item["key"] in seen:
            raise ManifestError(f"Local manifest {local_path}: duplicate key '{item['key']}'")
        seen.add(item["key"])
    return modules


def _is_blocked(entry: dict) -> bool:
    return str(entry.get("status", "active")).lower() == "blocked"


def merge_manifest(upstream: List[dict], local: List[dict]) -> Tuple[List[dict], List[str]]:
    merged: List[dict] = []
    index: Dict[str, int] = {}
    for item in upstream:
        copied = copy.deepcopy(item)
        copied["source"] = "upstream"
        index[copied["key"]] = len(merged)
        merged.append(copied)

    warnings: List[str] = []
    for item in local:
        fields = {k: copy.deepcopy(v) for k, v in item.items() if k not in ("key", "source")}
        key = item["key"]
        if key in index:
            base = merged[index[key]]
            was_blocked = _is_blocked(base)
            block_reason = base.get("block_reason") or "blocked in manifest"
            base.update(fields)
            base["source"] = "override"
            if was_blocked and not _is_blocked(base):
                warnings.append(
                    f"{key}: local override unblocks a module blocked upstream ({block_reason})"
                )
            continue
        if isinstance(item.get("name"), str) and item["name"] and isinstance(item.get("repo"), str) and item["repo"]:
            new_entry = {"key": key, **fields, "source": "local"}
            index[key] = len(merged)
            merged.append(new_entry)
        else:
            warnings.append(
                f"{key}: local override has no upstream entry (pruned or renamed?) and no name/repo; skipped"
            )
    return merged, warnings


def load_merged_manifest(manifest_path: Path) -> Tuple[List[dict], List[str]]:
    manifest_path = Path(manifest_path)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    upstream = [m for m in (data.get("modules") or []) if isinstance(m, dict) and m.get("key")]
    local = load_local_entries(local_manifest_path(manifest_path))
    return merge_manifest(upstream, local)
```

In `.gitignore`, add under the "Environment & Configuration" block:

```
config/module-manifest.local.json
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all `MergeManifestTest`, `LoadLocalEntriesTest` and `LoadMergedManifestTest` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/python/manifest_overlay.py scripts/python/tests/__init__.py scripts/python/tests/helpers.py scripts/python/tests/test_manifest_overlay.py .gitignore
git commit -m "feat(modules): merge a local manifest over the upstream one"
```

---

### Task 2: `modules.py` uses the merged manifest

**Files:**
- Modify: `scripts/python/modules.py` (`ModuleState` ~line 219; `build_state` ~line 275; `configure_parser` ~line 612)
- Create: `scripts/python/tests/test_modules_merged.py`

**Interfaces:**
- Consumes: `manifest_overlay.load_local_entries`, `local_manifest_path`, `merge_manifest`, `ManifestError` (Task 1)
- Produces:
  - `ModuleState.source: str` (default `"upstream"`)
  - `build_state()` returns merged modules, with overlay warnings in `state.warnings`
  - CLI `python3 modules.py --manifest <path> manifest --merged` prints `{"modules": [...]}` (merged, including `source`) to stdout and exits 0; on `ManifestError` it prints the message to stderr and exits 1

- [ ] **Step 1: Write the failing tests**

`scripts/python/tests/test_modules_merged.py`:

```python
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from modules import build_state
from manifest_overlay import local_manifest_path
from tests.helpers import entry, write_manifest

MODULES_PY = Path(__file__).resolve().parents[1] / "modules.py"


class BuildStateMergedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.manifest = write_manifest(
            self.tmp / "module-manifest.json",
            [entry("MODULE_A", type="cpp"), entry("MODULE_B", type="lua")],
        )
        self.env = self.tmp / ".env"
        self.env.write_text("MODULE_MINE=1\nMODULE_A=1\n")

    def test_local_module_is_enabled_and_compiled(self):
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE", type="cpp", name="mod-mine")])
        state = build_state(self.env, self.manifest)
        mine = next(m for m in state.modules if m.key == "MODULE_MINE")
        self.assertEqual(mine.source, "local")
        self.assertTrue(mine.enabled_effective)
        self.assertIn("mod-mine", [m.name for m in state.compile_modules()])
        self.assertFalse(any("MODULE_MINE" in w and "missing from the manifest" in w for w in state.warnings))

    def test_override_ref_reaches_module_state(self):
        write_manifest(local_manifest_path(self.manifest), [{"key": "MODULE_A", "ref": "v9"}])
        state = build_state(self.env, self.manifest)
        a = next(m for m in state.modules if m.key == "MODULE_A")
        self.assertEqual(a.ref, "v9")
        self.assertEqual(a.source, "override")

    def test_overlay_warnings_are_reported(self):
        write_manifest(local_manifest_path(self.manifest), [{"key": "MODULE_GONE", "ref": "v1"}])
        state = build_state(self.env, self.manifest)
        self.assertTrue(any("MODULE_GONE" in w for w in state.warnings))

    def test_no_local_file_is_unchanged_behaviour(self):
        state = build_state(self.env, self.manifest)
        self.assertEqual({m.source for m in state.modules}, {"upstream"})

    def test_manifest_merged_cli(self):
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE")])
        out = subprocess.run(
            [sys.executable, str(MODULES_PY), "--env-path", str(self.env), "--manifest", str(self.manifest), "manifest", "--merged"],
            capture_output=True, text=True, check=True,
        )
        data = json.loads(out.stdout)
        self.assertEqual([m["source"] for m in data["modules"]], ["upstream", "upstream", "local"])

    def test_manifest_merged_cli_invalid_local_file(self):
        local_manifest_path(self.manifest).write_text("{broken")
        out = subprocess.run(
            [sys.executable, str(MODULES_PY), "--manifest", str(self.manifest), "manifest", "--merged"],
            capture_output=True, text=True,
        )
        self.assertEqual(out.returncode, 1)
        self.assertIn("module-manifest.local.json", out.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_modules_merged -v` from `scripts/python` (or the discover command).
Expected: FAIL. `source` is not a field of `ModuleState`, and the `manifest` subcommand is unknown (argparse exit 2).

- [ ] **Step 3: Implement**

In `scripts/python/modules.py`:

1. Add an import below the existing imports:

```python
from manifest_overlay import ManifestError, load_local_entries, local_manifest_path, merge_manifest
```

2. Add a field to `ModuleState`, after `sql_files`:

```python
    source: str = "upstream"
```

3. In `build_state`, replace `manifest_entries = load_manifest(manifest_path)` with:

```python
    upstream_entries = load_manifest(manifest_path)
    local_entries = load_local_entries(local_manifest_path(manifest_path))
    manifest_entries, overlay_warnings = merge_manifest(upstream_entries, local_entries)
```

   Initialise `warnings: List[str] = list(overlay_warnings)` in place of the current `warnings: List[str] = []`, and in the `ModuleState(...)` constructor call add:

```python
            source=str(entry.get("source", "upstream")),
```

   A local entry reaches `build_state` only if `merge_manifest` accepted it, so the existing `name`/`repo` handling stays as it is.

4. In `configure_parser`, before `return parser`, add:

```python
    manifest_parser = subparsers.add_parser(
        "manifest", help="Print the manifest with config/module-manifest.local.json merged in"
    )
    manifest_parser.add_argument("--merged", action="store_true", required=True,
                                 help="Merge the local manifest (the only supported mode)")

    def handle_manifest(args: argparse.Namespace) -> int:
        manifest_path = Path(args.manifest).resolve()
        try:
            upstream = load_manifest(manifest_path)
            local = load_local_entries(local_manifest_path(manifest_path))
        except (ManifestError, ValueError, FileNotFoundError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        merged, overlay_warnings = merge_manifest(upstream, local)
        for warning in overlay_warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        json.dump({"modules": merged}, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    manifest_parser.set_defaults(func=handle_manifest)
```

5. In `main`, let a broken local file end the run with a clear message instead of a traceback. Change the body to:

```python
def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = configure_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
```

- [ ] **Step 4: Run all tests**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all PASS.

Then check that the real manifest behaves the same with no local file:

```bash
T=$(mktemp -d); python3 scripts/python/modules.py --env-path .env --manifest config/module-manifest.json generate --output-dir $T; echo rc=$?; grep -c '^export MODULE_' $T/modules.env; rm -rf $T
```

Expected: `rc=0` and the same `export MODULE_` count as on `main` before the change (run the same command on `main` to compare).

- [ ] **Step 5: Commit**

```bash
git add scripts/python/modules.py scripts/python/tests/test_modules_merged.py
git commit -m "feat(modules): build module state from the merged manifest"
```

---

### Task 3: Remaining manifest readers use the merged view

**Files:**
- Modify: `scripts/python/setup_manifest.py:12-22` (`load_manifest`)
- Modify: `scripts/bash/statusjson.sh` (`module_list`, ~lines 86-97)
- Modify: `scripts/bash/stage-modules.sh` (`get_module_dbc_path` and `stage_module_dbc_files`)
- Delete: `scripts/python/check_module_staging.py`
- Create: `scripts/python/tests/test_setup_manifest_merged.py`

**Interfaces:**
- Consumes: `manifest_overlay.load_merged_manifest`, `ManifestError` (Task 1); `modules.py manifest --merged` (Task 2)
- Produces: `setup_manifest.py keys|metadata|sorted-keys <manifest>` include local keys; `stage-modules.sh` resolves `server_dbc_path` for local modules

- [ ] **Step 1: Write the failing test**

`scripts/python/tests/test_setup_manifest_merged.py`:

```python
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from manifest_overlay import local_manifest_path
from tests.helpers import entry, write_manifest

SETUP_MANIFEST = Path(__file__).resolve().parents[1] / "setup_manifest.py"


class SetupManifestMergedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.manifest = write_manifest(self.tmp / "module-manifest.json", [entry("MODULE_A")])
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE")])

    def run_cmd(self, command):
        return subprocess.run([sys.executable, str(SETUP_MANIFEST), command, str(self.manifest)],
                              capture_output=True, text=True)

    def test_keys_include_local_modules(self):
        out = self.run_cmd("keys")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.split(), ["MODULE_A", "MODULE_MINE"])

    def test_metadata_includes_local_modules(self):
        out = self.run_cmd("metadata")
        self.assertIn("MODULE_MINE", out.stdout)

    def test_broken_local_file_fails_with_path(self):
        local_manifest_path(self.manifest).write_text("{broken")
        out = self.run_cmd("keys")
        self.assertEqual(out.returncode, 1)
        self.assertIn("module-manifest.local.json", out.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: `test_keys_include_local_modules` FAILS (only `MODULE_A` is printed).

- [ ] **Step 3: Implement**

`scripts/python/setup_manifest.py`: add the import and replace `load_manifest`:

```python
from manifest_overlay import ManifestError, load_merged_manifest


def load_manifest(path: str) -> dict:
    manifest_path = Path(path)
    if not manifest_path.is_file():
        print(f"ERROR: Module manifest not found at {manifest_path}", file=sys.stderr)
        sys.exit(1)
    try:
        modules, warnings = load_merged_manifest(manifest_path)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Failed to parse manifest {manifest_path}: {exc}", file=sys.stderr)
        sys.exit(1)
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    return {"modules": modules}
```

`scripts/bash/statusjson.sh`: in `module_list(env)`, replace the block that reads `manifest_path` with:

```python
    # Load module manifest (with config/module-manifest.local.json merged in)
    sys.path.insert(0, str(PROJECT_DIR / "scripts" / "python"))
    from manifest_overlay import load_merged_manifest

    manifest_path = PROJECT_DIR / "config" / "module-manifest.json"
    manifest_map = {}
    if manifest_path.exists():
        try:
            merged, _warnings = load_merged_manifest(manifest_path)
            for mod in merged:
                manifest_map[mod["key"]] = mod
        except Exception:
            pass
```

`scripts/bash/stage-modules.sh`: load the merged manifest once per staging run instead of running `jq` on the upstream file for each module. Replace `get_module_dbc_path` with:

```bash
MERGED_MANIFEST_JSON=""

# Merged manifest (config/module-manifest.local.json over the upstream file), loaded once.
load_merged_manifest_json(){
  [ -n "$MERGED_MANIFEST_JSON" ] && return 0
  MERGED_MANIFEST_JSON="$(python3 "$PROJECT_DIR/scripts/python/modules.py" \
    --manifest "$PROJECT_DIR/config/module-manifest.json" manifest --merged)" || return 1
}

get_module_dbc_path(){
  local module_name="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ⚠️  jq not installed; cannot read server_dbc_path for $module_name, DBC files not staged" >&2
    return 1
  fi
  if ! load_merged_manifest_json; then
    echo "  ⚠️  Could not load the module manifest; DBC files for $module_name not staged" >&2
    return 1
  fi

  local dbc_path
  dbc_path=$(printf '%s' "$MERGED_MANIFEST_JSON" | jq -r --arg n "$module_name" '.modules[] | select(.name == $n) | .server_dbc_path // empty' 2>/dev/null)
  if [ -n "$dbc_path" ]; then
    echo "$dbc_path"
    return 0
  fi
  return 1
}
# ---- end DBC lookup ----
```

`get_module_dbc_path` runs in `$(...)`, so a cache set inside it would be lost. Call `load_merged_manifest_json || true` once at the top of `stage_module_dbc_files` (right after its `show_staging_step` line), so later lookups reuse it.

Delete `scripts/python/check_module_staging.py` (`git rm`). Confirm first that nothing references it:

```bash
grep -rn "check_module_staging" --exclude-dir=.git . | grep -v "^./docs"
```

Expected: no output.

- [ ] **Step 4: Verify**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`. Expected: all PASS.

Then check the DBC lookup against the real manifest (MODULE_ARAC ships DBC files):

```bash
bash -c 'PROJECT_DIR=$PWD; source <(sed -n "/^MERGED_MANIFEST_JSON=\"\"$/,/^# ---- end DBC lookup ----$/p" scripts/bash/stage-modules.sh); load_merged_manifest_json; get_module_dbc_path mod-arac'
```

Expected: prints `jq`'s value for `mod-arac` (the same as `jq -r '.modules[]|select(.name=="mod-arac")|.server_dbc_path' config/module-manifest.json`).

Also run `bash -n scripts/bash/stage-modules.sh` and `python3 scripts/bash/statusjson.sh >/dev/null` (the latter must not raise).

- [ ] **Step 5: Commit**

```bash
git add scripts/python/setup_manifest.py scripts/bash/statusjson.sh scripts/bash/stage-modules.sh scripts/python/tests/test_setup_manifest_merged.py
git rm scripts/python/check_module_staging.py
git commit -m "feat(modules): read the merged manifest in setup, status and DBC staging"
```

---

### Task 4: Install-type detection

**Files:**
- Create: `scripts/python/module_detect.py`
- Create: `scripts/python/tests/test_module_detect.py`

**Interfaces:**
- Produces:

```python
@dataclass
class Detection:
    module_type: Optional[str]          # "cpp" | "lua" | "sql" | None
    post_install_hooks: List[str]
    requires: List[str]
    warnings: List[str]
    is_collection: bool = False         # Lua that looks like a script collection
    reason: str = ""                    # why module_type is None

def detect(module_dir: Path, folder_name: str) -> Detection
COLLECTION_FILE_THRESHOLD = 20
COLLECTION_DIR_THRESHOLD = 3
```

`folder_name` is the clone folder name, i.e. the entry's `name`, which is the repository name.

- [ ] **Step 1: Write the failing tests**

`scripts/python/tests/test_module_detect.py`:

```python
import tempfile
import unittest
from pathlib import Path

from module_detect import COLLECTION_FILE_THRESHOLD, detect


def make(root: Path, files: dict) -> Path:
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    return root


class DetectTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def mod(self, files):
        return make(self.tmp / "mod", files)

    # C++
    def test_cpp_with_matching_loader(self):
        d = detect(self.mod({"src/loader.cpp": "void Addmod_fooScripts() {}"}), "mod-foo")
        self.assertEqual(d.module_type, "cpp")
        self.assertEqual(d.warnings, [])

    def test_cpp_loader_mismatch_warns(self):
        d = detect(self.mod({"src/x.cpp": "void AddFooScripts() {}"}), "mod-foo")
        self.assertEqual(d.module_type, "cpp")
        self.assertTrue(any("Addmod_fooScripts" in w for w in d.warnings))

    def test_cpp_no_loader_warns(self):
        d = detect(self.mod({"src/x.h": "// nothing"}), "mod-foo")
        self.assertTrue(any("Addmod_fooScripts" in w for w in d.warnings))

    def test_cpp_playerbots_dependency(self):
        d = detect(self.mod({"src/x.cpp": '#include "Playerbots.h"\nvoid Addmod_fooScripts(){}'}), "mod-foo")
        self.assertIn("MODULE_PLAYERBOTS", d.requires)

    def test_cpp_stray_sql_warns(self):
        d = detect(self.mod({"src/x.cpp": "void Addmod_fooScripts(){}", "sql/world.sql": "SELECT 1;"}), "mod-foo")
        self.assertTrue(any("sql/world.sql" in w for w in d.warnings))

    def test_cpp_sql_in_staged_dirs_is_quiet(self):
        d = detect(self.mod({"src/x.cpp": "void Addmod_fooScripts(){}",
                             "data/sql/db-world/a.sql": "SELECT 1;",
                             "data/sql/db-characters/updates/b.sql": "SELECT 1;",
                             "data/sql/world/base/c.sql": "SELECT 1;"}), "mod-foo")
        self.assertEqual(d.warnings, [])

    # Lua
    def test_lua_standard(self):
        d = detect(self.mod({"script.lua": "print(1)"}), "lua-thing")
        self.assertEqual((d.module_type, d.post_install_hooks, d.requires), ("lua", ["copy-standard-lua"], ["MODULE_ELUNA"]))

    def test_lua_aio(self):
        d = detect(self.mod({"Server/s.lua": 'local AIO = AIO or require("AIO")'}), "aio-thing")
        self.assertEqual((d.post_install_hooks, d.requires), (["copy-aio-lua"], ["MODULE_AIO"]))

    def test_lua_require_from_subfolder_uses_tree(self):
        d = detect(self.mod({"Bot.lua": 'local E = require("EnchantmentModule")',
                             "Bot/EnchantmentModule.lua": "return {}"}), "lua-bot")
        self.assertEqual(d.post_install_hooks, ["copy-lua-tree"])

    def test_lua_only_in_subfolder_uses_tree(self):
        d = detect(self.mod({"thing/Main.lua": "print(1)"}), "lua-thing")
        self.assertEqual(d.post_install_hooks, ["copy-lua-tree"])

    def test_lua_collection_by_count(self):
        files = {f"s{i}.lua": "print(1)" for i in range(COLLECTION_FILE_THRESHOLD + 1)}
        d = detect(self.mod(files), "scripts")
        self.assertTrue(d.is_collection)

    def test_lua_collection_by_folders(self):
        d = detect(self.mod({"A/a.lua": "", "B/b.lua": "", "C/c.lua": ""}), "scripts")
        self.assertTrue(d.is_collection)

    def test_git_dir_is_ignored(self):
        d = detect(self.mod({".git/hooks/x.lua": "", "main.lua": ""}), "lua-thing")
        self.assertEqual(d.post_install_hooks, ["copy-standard-lua"])

    # SQL / other
    def test_sql_only(self):
        d = detect(self.mod({"data/sql/db-world/a.sql": "SELECT 1;"}), "sql-thing")
        self.assertEqual((d.module_type, d.post_install_hooks), ("sql", []))

    def test_nothing_recognisable(self):
        d = detect(self.mod({"README.md": "hi", "tool.py": ""}), "tool")
        self.assertIsNone(d.module_type)
        self.assertIn("no src/", d.reason)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: ERROR, `No module named 'module_detect'`.

- [ ] **Step 3: Implement `scripts/python/module_detect.py`**

```python
#!/usr/bin/env python3
"""
Work out how RealmMaster should install a checked-out module.

Mirrors what the pipeline does with each type (see docs/ADDING_MODULES.md):
C++ is compiled (AzerothCore calls Add<folder>Scripts(), '-' -> '_'), Lua is
staged by a post-install hook, and SQL in data/sql/<db> folders is applied.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional

COLLECTION_FILE_THRESHOLD = 20
COLLECTION_DIR_THRESHOLD = 3

# Folders stage-modules.sh reads SQL from, relative to data/sql/.
_SQL_DIRS = {
    f"{db}{suffix}"
    for db in ("db-world", "db-characters", "db-auth", "db-playerbots")
    for suffix in ("", "/base", "/updates")
} | {f"{db}{suffix}" for db in ("world", "characters", "auth") for suffix in ("", "/base")}

# Flat locations copy-standard-lua reads.
_STANDARD_LUA_DIRS = {".", "lua_scripts", "scripts", "Server Files/lua_scripts"}

_LOADER_RE = re.compile(r"void\s+(Add\w+Scripts)\s*\(")
_REQUIRE_RE = re.compile(r"""require\s*\(?\s*["']([\w./-]+)["']""")
_AIO_RE = re.compile(r"""require\s*\(?\s*["']AIO["']|\bAIO\.""")


@dataclass
class Detection:
    module_type: Optional[str]
    post_install_hooks: List[str] = field(default_factory=list)
    requires: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    is_collection: bool = False
    reason: str = ""


def _files(root: Path, pattern: str) -> Iterator[Path]:
    for path in root.rglob(pattern):
        if ".git" in path.relative_to(root).parts:
            continue
        if path.is_file():
            yield path


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _stray_sql_warnings(root: Path) -> List[str]:
    warnings = []
    for sql in _files(root, "*.sql"):
        rel = sql.relative_to(root)
        parts = rel.parts
        parent = "/".join(parts[2:-1]) if parts[:2] == ("data", "sql") else None
        if parent not in _SQL_DIRS:
            warnings.append(f"{rel.as_posix()} is outside data/sql/<db>/ and will not be imported")
    return warnings


def _detect_cpp(root: Path, folder_name: str) -> Detection:
    detection = Detection("cpp")
    sources = list(_files(root / "src", "*.cpp")) + list(_files(root / "src", "*.h"))
    text = "\n".join(_read(p) for p in sources)
    expected = f"Add{folder_name.replace('-', '_')}Scripts"
    found = sorted(set(_LOADER_RE.findall(text)))
    if expected not in found:
        detection.warnings.append(
            f"AzerothCore will call {expected}() for folder '{folder_name}', "
            f"but src/ defines {', '.join(found) if found else 'no Add...Scripts() function'}; "
            "the build may fail to link"
        )
    if "Playerbots.h" in text or "PlayerbotAI" in text:
        detection.requires.append("MODULE_PLAYERBOTS")
    detection.warnings.extend(_stray_sql_warnings(root))
    return detection


def _detect_lua(root: Path, lua_files: List[Path]) -> Detection:
    detection = Detection("lua")
    rels = [p.relative_to(root) for p in lua_files]
    top_dirs = {r.parts[0] for r in rels if len(r.parts) > 1}
    if len(rels) > COLLECTION_FILE_THRESHOLD or len(top_dirs) >= COLLECTION_DIR_THRESHOLD:
        detection.is_collection = True
    text = "\n".join(_read(p) for p in lua_files)

    if _AIO_RE.search(text):
        detection.post_install_hooks = ["copy-aio-lua"]
        detection.requires = ["MODULE_AIO"]
        return detection

    detection.requires = ["MODULE_ELUNA"]
    in_standard = {r for r in rels if (r.parent.as_posix() or ".") in _STANDARD_LUA_DIRS}
    standard_names = {r.stem for r in in_standard}
    all_names = {r.stem for r in rels}
    required = {name.replace(".", "/").split("/")[-1] for name in _REQUIRE_RE.findall(text)}
    needs_subfolder = any(name in all_names and name not in standard_names for name in required)
    if not in_standard or needs_subfolder:
        detection.post_install_hooks = ["copy-lua-tree"]
    else:
        detection.post_install_hooks = ["copy-standard-lua"]
    return detection


def detect(module_dir: Path, folder_name: str) -> Detection:
    root = Path(module_dir)
    src = root / "src"
    if src.is_dir() and (any(_files(src, "*.cpp")) or any(_files(src, "*.h"))):
        return _detect_cpp(root, folder_name)

    lua_files = list(_files(root, "*.lua"))
    if lua_files:
        return _detect_lua(root, lua_files)

    sql_dir = root / "data" / "sql"
    if sql_dir.is_dir() and any(_files(sql_dir, "*.sql")):
        detection = Detection("sql")
        detection.warnings.extend(_stray_sql_warnings(root))
        return detection

    return Detection(None, reason="no src/ with C++, no .lua files and no data/sql/*.sql; "
                                  "this looks like a tool or client patch")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all PASS.

Then compare against real modules (this reads only; it needs the local `storage/modules` checkouts):

```bash
cd scripts/python && for m in azerothcore-lua-ah-bot mod-aio Eluna-scripts mod-transmog mod-TimeIsTime; do python3 -c "import sys; from module_detect import detect; d=detect(sys.argv[1], sys.argv[2]); print(sys.argv[2], d.module_type, d.post_install_hooks, d.requires, 'collection' if d.is_collection else '', d.warnings)" ../../storage/modules/$m $m; done
```

Expected, matching what the end-to-end test established:
- `azerothcore-lua-ah-bot`: `lua ['copy-lua-tree']`
- `mod-aio`: `lua`, AIO hook (its own AIO scripts reference `AIO.`), which is acceptable. The curated entry uses `copy-aio-server`, and `add` refuses it anyway because it's already upstream.
- `Eluna-scripts`: `collection`
- `mod-transmog`: `cpp`, no loader warning
- `mod-TimeIsTime`: `cpp`, and the warnings include one saying AzerothCore will call `Addmod_TimeIsTimeScripts()`

- [ ] **Step 5: Commit**

```bash
git add scripts/python/module_detect.py scripts/python/tests/test_module_detect.py
git commit -m "feat(modules): detect a module's install type from its checkout"
```

---

### Task 5: `local_modules.py` helpers

**Files:**
- Create: `scripts/python/local_modules.py` (helpers only; the CLI comes in Tasks 6–7)
- Create: `scripts/python/tests/test_local_modules_helpers.py`

**Interfaces:**
- Produces:
  - `normalize_repo(url: str) -> str`: lower-cased, with no scheme, no trailing `/` and no trailing `.git` (for comparison only, never stored)
  - `repo_basename(url: str) -> str`: last path segment, without `.git`, case preserved
  - `set_env_value(env_path: Path, key: str, value: str) -> None`: replaces every `KEY=`/`export KEY=` line with `KEY=value` (first occurrence kept, later duplicates removed); appends if absent; creates the file if missing; keeps other lines and a trailing newline
  - `write_local_entries(local_path: Path, entries: List[dict]) -> None`: atomic (temp file + `os.replace`), `{"modules": entries}` with indent 2
  - `class ProbeError(RuntimeError)`
  - `probe_clone(url: str, ref: Optional[str], dest: Path) -> None`: shallow clone at `ref`; falls back to a full clone + `git checkout <ref>` when `--branch` fails (commit SHAs); raises `ProbeError` with git's stderr
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing tests**

`scripts/python/tests/test_local_modules_helpers.py`:

```python
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from local_modules import (
    ProbeError,
    normalize_repo,
    probe_clone,
    repo_basename,
    set_env_value,
    write_local_entries,
)

GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull)


def make_repo(root: Path, files: dict, branch: str = "main") -> Path:
    root.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", "-b", branch, str(root)], check=True, env=GIT_ENV)
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True, env=GIT_ENV)
    subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", "init"], check=True, env=GIT_ENV)
    return root


class NormalizeTest(unittest.TestCase):
    def test_normalize_repo_variants(self):
        variants = [
            "https://github.com/Foo/mod-bar.git",
            "https://github.com/foo/mod-bar",
            "https://github.com/foo/mod-bar/",
            "http://github.com/foo/mod-bar.git",
            "  https://GitHub.com/foo/mod-bar.git/ ",
        ]
        self.assertEqual(len({normalize_repo(v) for v in variants}), 1)

    def test_different_repos_differ(self):
        self.assertNotEqual(normalize_repo("https://github.com/a/x"), normalize_repo("https://github.com/b/x"))

    def test_repo_basename(self):
        self.assertEqual(repo_basename("https://gitlab.com/me/Mod-Thing.git/"), "Mod-Thing")
        self.assertEqual(repo_basename("/srv/git/lua-ah-bot"), "lua-ah-bot")


class EnvFileTest(unittest.TestCase):
    def setUp(self):
        self.env = Path(tempfile.mkdtemp()) / ".env"

    def test_creates_missing_file(self):
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X=1\n")

    def test_replaces_in_place(self):
        self.env.write_text("A=1\nMODULE_X=0\nB=2\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "A=1\nMODULE_X=1\nB=2\n")

    def test_appends_when_absent_without_trailing_newline(self):
        self.env.write_text("A=1")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "A=1\nMODULE_X=1\n")

    def test_export_prefix_and_duplicates(self):
        self.env.write_text("export MODULE_X=0\nA=1\nMODULE_X=0\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X=1\nA=1\n")

    def test_does_not_touch_similar_keys(self):
        self.env.write_text("MODULE_X_EXTRA=0\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X_EXTRA=0\nMODULE_X=1\n")


class WriteLocalEntriesTest(unittest.TestCase):
    def test_atomic_write(self):
        path = Path(tempfile.mkdtemp()) / "config" / "module-manifest.local.json"
        write_local_entries(path, [{"key": "MODULE_X", "name": "x", "repo": "r"}])
        self.assertEqual(json.loads(path.read_text())["modules"][0]["key"], "MODULE_X")
        self.assertEqual([p.name for p in path.parent.iterdir()], ["module-manifest.local.json"])


class ProbeCloneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.repo = make_repo(self.tmp / "src", {"a.lua": "print(1)"})
        subprocess.run(["git", "-C", str(self.repo), "tag", "v1"], check=True, env=GIT_ENV)

    def test_probe_clone_default_branch(self):
        probe_clone(str(self.repo), None, self.tmp / "out1")
        self.assertTrue((self.tmp / "out1" / "a.lua").exists())

    def test_probe_clone_tag(self):
        probe_clone(str(self.repo), "v1", self.tmp / "out2")
        self.assertTrue((self.tmp / "out2" / "a.lua").exists())

    def test_probe_clone_commit_sha(self):
        sha = subprocess.run(["git", "-C", str(self.repo), "rev-parse", "HEAD"], capture_output=True,
                             text=True, check=True).stdout.strip()
        probe_clone(str(self.repo), sha, self.tmp / "out3")
        head = subprocess.run(["git", "-C", str(self.tmp / "out3"), "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
        self.assertEqual(head, sha)

    def test_probe_clone_bad_url(self):
        with self.assertRaises(ProbeError):
            probe_clone(str(self.tmp / "does-not-exist"), None, self.tmp / "out4")

    def test_probe_clone_bad_ref(self):
        with self.assertRaises(ProbeError):
            probe_clone(str(self.repo), "no-such-ref", self.tmp / "out5")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: ERROR, `No module named 'local_modules'`.

- [ ] **Step 3: Implement the helpers in `scripts/python/local_modules.py`**

```python
#!/usr/bin/env python3
"""
./modules.sh backend: add, list and remove user-defined modules.

Entries live in config/module-manifest.local.json (gitignored), merged over the
upstream manifest by scripts/python/manifest_overlay.py. See
docs/ADDING_MODULES.md.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional


class ProbeError(RuntimeError):
    """The repository could not be cloned at the requested ref."""


def normalize_repo(url: str) -> str:
    value = url.strip().lower()
    value = re.sub(r"^[a-z]+://", "", value)
    value = value.rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    return value.rstrip("/")


def repo_basename(url: str) -> str:
    name = url.strip().rstrip("/").split("/")[-1]
    return name[:-4] if name.endswith(".git") else name


def set_env_value(env_path: Path, key: str, value: str) -> None:
    env_path = Path(env_path)
    lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
    pattern = re.compile(rf"^\s*(export\s+)?{re.escape(key)}=")
    out: List[str] = []
    written = False
    for line in lines:
        if pattern.match(line):
            if not written:
                out.append(f"{key}={value}")
                written = True
            continue
        out.append(line)
    if not written:
        out.append(f"{key}={value}")
    env_path.write_text("\n".join(out) + "\n", encoding="utf-8")


def write_local_entries(local_path: Path, entries: List[dict]) -> None:
    local_path = Path(local_path)
    local_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=local_path.parent, prefix=".module-manifest.local.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"modules": entries}, fh, indent=2)
            fh.write("\n")
        os.replace(tmp_name, local_path)
    except BaseException:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise


def _git(args: List[str]) -> subprocess.CompletedProcess:
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    return subprocess.run(["git", *args], capture_output=True, text=True, env=env)


def probe_clone(url: str, ref: Optional[str], dest: Path) -> None:
    dest = Path(dest)
    args = ["clone", "--quiet", "--depth", "1"]
    if ref:
        args += ["--branch", ref]
    result = _git([*args, url, str(dest)])
    if result.returncode == 0:
        return
    if not ref:
        raise ProbeError(f"Could not clone {url}: {result.stderr.strip()}")
    # --branch only takes branches and tags; a commit SHA needs a full clone.
    shutil.rmtree(dest, ignore_errors=True)
    full = _git(["clone", "--quiet", url, str(dest)])
    if full.returncode != 0:
        raise ProbeError(f"Could not clone {url}: {full.stderr.strip()}")
    checkout = _git(["-C", str(dest), "checkout", "--quiet", ref])
    if checkout.returncode != 0:
        shutil.rmtree(dest, ignore_errors=True)
        raise ProbeError(f"Ref '{ref}' not found in {url}: {checkout.stderr.strip()}")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/python/local_modules.py scripts/python/tests/test_local_modules_helpers.py
git commit -m "feat(modules): helpers for local module entries, .env edits and repo probing"
```

---

### Task 6: `./modules.sh add`

**Files:**
- Modify: `scripts/python/local_modules.py` (add the CLI and `cmd_add`)
- Create: `modules.sh` (repo root, executable)
- Create: `scripts/python/tests/test_local_modules_cli.py`

**Interfaces:**
- Consumes: Task 1 (`load_local_entries`, `local_manifest_path`, `merge_manifest`, `ManifestError`); Task 2 (`modules.build_state`); Task 4 (`detect`, `Detection`); Task 5 helpers; `update_module_manifest.repo_name_to_key`
- Produces:
  - `main(argv: Optional[List[str]] = None) -> int`
  - Subcommand `add [url] [--ref R] [--type cpp|lua|sql] [--key K] [--no-enable] [--yes]`, plus the global `--root DIR` (default: the repo root, `Path(__file__).parents[2]`)
  - Exit codes: `0` ok; `1` refused (duplicate, collision, collection, undetectable, invalid local file, clone failure, declined prompt); `2` usage error (argparse)
  - `WORLDSERVER_WARNING` (module-level string constant, printed on every successful `add`)

- [ ] **Step 1: Write the failing tests**

`scripts/python/tests/test_local_modules_cli.py`:

```python
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from local_modules import main
from manifest_overlay import LOCAL_MANIFEST_NAME
from tests.helpers import entry, write_manifest
from tests.test_local_modules_helpers import make_repo


class CliCase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.repos = Path(tempfile.mkdtemp())
        (self.root / "config").mkdir()
        self.upstream_repo = "https://github.com/azerothcore/mod-up.git"
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
        ])
        (self.root / ".env").write_text("MODULE_ELUNA=1\n")

    def run_cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = main(["--root", str(self.root), *args])
        return rc, out.getvalue(), err.getvalue()

    def local_entries(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        return json.loads(path.read_text())["modules"] if path.exists() else []

    def env(self):
        return (self.root / ".env").read_text()


class AddTest(CliCase):
    def test_add_lua_module(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual((e["key"], e["name"], e["type"]), ("MODULE_LUA_THING", "lua-thing", "lua"))
        self.assertEqual(e["post_install_hooks"], ["copy-standard-lua"])
        self.assertEqual(e["requires"], ["MODULE_ELUNA"])
        self.assertIn("MODULE_LUA_THING=1", self.env())
        self.assertIn("run inside your worldserver", out)
        self.assertIn("./deploy.sh", out)

    def test_add_enables_requires(self):
        repo = make_repo(self.repos / "aio-thing", {"Server/s.lua": 'local AIO = require("AIO")'})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("MODULE_AIO=1", self.env())
        self.assertIn("MODULE_AIO", out)

    def test_add_cpp_says_build(self):
        repo = make_repo(self.repos / "mod-mine", {"src/l.cpp": "void Addmod_mineScripts(){}"})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("./build.sh", out)

    def test_add_no_enable(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        rc, _, _ = self.run_cli("add", str(repo), "--yes", "--no-enable")
        self.assertEqual(rc, 0)
        self.assertNotIn("MODULE_LUA_THING", self.env())

    def test_add_records_ref(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        import subprocess
        from tests.test_local_modules_helpers import GIT_ENV
        subprocess.run(["git", "-C", str(repo), "tag", "v2"], check=True, env=GIT_ENV)
        rc, _, _ = self.run_cli("add", str(repo), "--ref", "v2", "--yes")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries()[0]["ref"], "v2")

    def test_add_rejects_upstream_repo_with_git_suffix(self):
        rc, _, err = self.run_cli("add", "https://github.com/AzerothCore/mod-up/", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_UP=1", err)
        self.assertEqual(self.local_entries(), [])

    def test_add_twice_same_url_is_rejected(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        self.assertEqual(self.run_cli("add", str(repo), "--yes")[0], 0)
        rc, _, err = self.run_cli("add", str(repo) + "/", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_LUA_THING", err)
        self.assertEqual(len(self.local_entries()), 1)

    def test_add_key_collision_needs_explicit_key(self):
        repo = make_repo(self.repos / "mod-up", {"thing.lua": ""})  # derives MODULE_MOD_UP; force a clash:
        write_manifest(self.root / "config" / "module-manifest.json",
                       [entry("MODULE_MOD_UP", name="mod-up-other", repo="https://example.com/other.git")])
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--key", err)

    def test_add_collection_refused_without_type(self):
        files = {f"s{i}.lua": "" for i in range(25)}
        repo = make_repo(self.repos / "scripts", files)
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--type lua", err)
        self.assertEqual(self.local_entries(), [])

    def test_add_collection_with_type_lua(self):
        files = {f"s{i}.lua": "" for i in range(25)}
        repo = make_repo(self.repos / "scripts", files)
        rc, _, _ = self.run_cli("add", str(repo), "--type", "lua", "--yes")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries()[0]["post_install_hooks"], ["copy-standard-lua"])

    def test_add_undetectable_refused(self):
        repo = make_repo(self.repos / "tool", {"README.md": "x"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--type", err)

    def test_add_bad_url_writes_nothing(self):
        rc, _, err = self.run_cli("add", str(self.repos / "missing"), "--yes")
        self.assertEqual(rc, 1)
        self.assertEqual(self.local_entries(), [])

    def test_add_refuses_when_local_file_is_invalid(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        path.write_text("{broken")
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn(LOCAL_MANIFEST_NAME, err)
        self.assertEqual(path.read_text(), "{broken")

    def test_ref_only_override(self):
        rc, out, _ = self.run_cli("add", "--key", "MODULE_UP", "--ref", "v1.2", "--yes")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.local_entries(), [{"key": "MODULE_UP", "ref": "v1.2"}])

    def test_fork_override(self):
        fork = make_repo(self.repos / "mod-up", {"src/l.cpp": "void Addmod_upScripts(){}"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual((e["key"], e["repo"]), ("MODULE_UP", str(fork)))
        self.assertNotIn("description", e)

    def test_declined_prompt_writes_nothing(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        import builtins
        from unittest import mock
        with mock.patch.object(builtins, "input", return_value="n"):
            rc, _, _ = self.run_cli("add", str(repo))
        self.assertEqual(rc, 1)
        self.assertEqual(self.local_entries(), [])


if __name__ == "__main__":
    unittest.main()
```

`test_ref_only_override` doesn't probe: the upstream URL in the fixture is fake, and the override targets a repo that is already listed. `add` validates the ref in the ac-modules run instead, where `checkout_module_ref` warns if it's missing (see Step 3, "ref-only override").

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: ERROR, `cannot import name 'main' from 'local_modules'`.

- [ ] **Step 3: Implement**

Append to `scripts/python/local_modules.py`:

```python
import argparse
import sys

from manifest_overlay import ManifestError, load_local_entries, local_manifest_path, merge_manifest
from module_detect import detect
from update_module_manifest import repo_name_to_key

WORLDSERVER_WARNING = (
    "⚠️  Lua and SQL from this module run inside your worldserver. If the worldserver "
    "crash-loops after deploying, run ./modules.sh remove {key} and deploy again."
)


class Refused(Exception):
    """add/remove refused with a message for the user (exit code 1)."""


class Paths:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.manifest = self.root / "config" / "module-manifest.json"
        self.local = local_manifest_path(self.manifest)
        self.env = self.root / ".env"


def _load(paths: Paths):
    try:
        local = load_local_entries(paths.local)
    except ManifestError as exc:
        raise Refused(f"{exc}\nFix or remove {paths.local} first; it was not modified.")
    upstream = json.loads(paths.manifest.read_text(encoding="utf-8")).get("modules", [])
    merged, warnings = merge_manifest(upstream, local)
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    return upstream, local, merged


def _confirm(prompt: str, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    try:
        return input(f"{prompt} [y/N]: ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def _enable(paths: Paths, keys: List[str]) -> None:
    for key in keys:
        set_env_value(paths.env, key, "1")
        print(f"   enabled {key}=1 in .env")


def cmd_add(args: argparse.Namespace, paths: Paths) -> int:
    upstream, local, merged = _load(paths)
    by_key = {m["key"]: m for m in merged}
    upstream_keys = {m["key"] for m in upstream}

    # Ref-only override of a listed module: no clone, nothing to detect.
    if not args.url:
        if not args.key or not args.ref:
            raise Refused("add needs a git URL, or --key MODULE_X --ref <ref> to pin a listed module")
        if args.key not in by_key:
            raise Refused(f"{args.key} is not in the manifest; give a git URL to add it")
        override = next((e for e in local if e["key"] == args.key), {"key": args.key})
        override = {**override, "ref": args.ref}
        print(json.dumps(override, indent=2))
        if not _confirm(f"Pin {args.key} to {args.ref}?", args.yes):
            raise Refused("Nothing written.")
        write_local_entries(paths.local, [e for e in local if e["key"] != args.key] + [override])
        print(f"✅ {args.key} pinned to {args.ref} in {paths.local.name}. Run ./deploy.sh to apply.")
        return 0

    wanted = normalize_repo(args.url)
    same_repo = next((m for m in merged if normalize_repo(str(m.get("repo", ""))) == wanted), None)
    if same_repo and args.key != same_repo["key"]:
        where = "added locally" if same_repo.get("source") == "local" else "in the manifest"
        raise Refused(f"{args.url} is already {where} as {same_repo['key']}; "
                      f"enable it with {same_repo['key']}=1 in .env")

    name = repo_basename(args.url)
    key = args.key or repo_name_to_key(name)
    is_override = key in upstream_keys
    if not args.key and key in by_key:
        raise Refused(f"Key {key} is already used by {by_key[key].get('repo')}; choose one with --key MODULE_...")

    with tempfile.TemporaryDirectory(prefix="realmmaster-probe-") as tmp:
        checkout = Path(tmp) / name
        try:
            probe_clone(args.url, args.ref, checkout)
        except ProbeError as exc:
            raise Refused(str(exc))
        detection = detect(checkout, by_key[key]["name"] if is_override else name)

    module_type = args.type or detection.module_type
    if module_type is None:
        raise Refused(f"Could not tell how to install {name}: {detection.reason}. "
                      "Pass --type cpp|lua|sql if you know better.")
    if detection.is_collection and args.type != "lua":
        raise Refused(f"{name} looks like a Lua script collection (many scripts or folders). "
                      "Staging all of it can break the worldserver; copy the scripts you want into "
                      "storage/lua_scripts/ yourself, or pass --type lua to stage everything.")
    for warning in detection.warnings:
        print(f"WARNING: {warning}", file=sys.stderr)

    hooks = detection.post_install_hooks if module_type == detection.module_type else []
    if module_type == "lua" and not hooks:
        hooks, requires = ["copy-standard-lua"], ["MODULE_ELUNA"]
    else:
        requires = detection.requires if module_type == detection.module_type else []

    if is_override:
        new_entry = {"key": key, "repo": args.url}
        if args.ref:
            new_entry["ref"] = args.ref
        if module_type != str(by_key[key].get("type", "cpp")):
            print(f"WARNING: {args.url} looks like {module_type}, but {key} is {by_key[key].get('type')} upstream",
                  file=sys.stderr)
    else:
        new_entry = {"key": key, "name": name, "repo": args.url, "type": module_type,
                     "post_install_hooks": hooks, "requires": requires,
                     "description": f"User module from {args.url}", "category": "local"}
        if args.ref:
            new_entry["ref"] = args.ref

    print(json.dumps(new_entry, indent=2))
    if not _confirm(f"Add {key}?", args.yes):
        raise Refused("Nothing written.")
    write_local_entries(paths.local, [e for e in local if e["key"] != key] + [new_entry])
    print(f"✅ {key} written to {paths.local.name}")

    if not args.no_enable:
        _enable(paths, [key] + [r for r in requires])

    from modules import build_state
    state = build_state(paths.env, paths.manifest)
    for error in state.errors:
        print(f"ERROR: {error}", file=sys.stderr)

    print(WORLDSERVER_WARNING.format(key=key))
    print("Next: ./build.sh (C++ module)" if module_type == "cpp" else "Next: ./deploy.sh")
    return 1 if state.errors else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="modules.sh", description="Manage user-defined modules")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="command", required=True)

    add = sub.add_parser("add", help="Add a module from a git URL, or pin/fork a listed one")
    add.add_argument("url", nargs="?", help="git URL (omit with --key and --ref to pin a listed module)")
    add.add_argument("--ref", help="branch, tag or commit to check out")
    add.add_argument("--type", choices=["cpp", "lua", "sql"], help="skip detection")
    add.add_argument("--key", help="MODULE_* key (to override a listed module, or on a key collision)")
    add.add_argument("--no-enable", action="store_true", help="don't set MODULE_*=1 in .env")
    add.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    add.set_defaults(func=cmd_add)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    paths = Paths(Path(args.root))
    try:
        return args.func(args, paths)
    except Refused as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

Move the new `import argparse` / `import sys` lines up to the module's import block, and the `manifest_overlay` / `module_detect` / `update_module_manifest` imports below the existing ones.

Create `modules.sh` at the repo root and make it executable (`chmod +x modules.sh`):

```bash
#!/bin/bash
# Add, list and remove user-defined modules (config/module-manifest.local.json).
# See docs/ADDING_MODULES.md.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$ROOT_DIR/scripts/python/local_modules.py" --root "$ROOT_DIR" "$@"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all PASS.

Then check the wrapper: `./modules.sh --help` prints usage, `./modules.sh add` with no arguments exits 1 with the "needs a git URL" message, and `shellcheck modules.sh` is clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/python/local_modules.py scripts/python/tests/test_local_modules_cli.py modules.sh
git commit -m "feat(modules): ./modules.sh add for user-defined modules"
```

---

### Task 7: `./modules.sh list` and `remove`

**Files:**
- Modify: `scripts/python/local_modules.py` (`cmd_list`, `cmd_remove`, parser entries)
- Modify: `scripts/python/tests/test_local_modules_cli.py` (add `ListRemoveTest`)

**Interfaces:**
- Consumes: Task 6 (`CliCase`, `Paths`, `_load`, `Refused`, `main`)
- Produces:
  - `list`: one line per local entry, as `KEY  kind  enabled  repo[@ref]`, where kind is `local` | `override` | `orphaned`
  - `remove KEY`: exit 0 on success, 1 if the key has no local entry or the local file is invalid

- [ ] **Step 1: Write the failing tests** (append to `scripts/python/tests/test_local_modules_cli.py`)

```python
class ListRemoveTest(CliCase):
    def seed(self, entries, env="MODULE_ELUNA=1\n"):
        write_manifest(self.root / "config" / LOCAL_MANIFEST_NAME, entries)
        (self.root / ".env").write_text(env)

    def test_list_shows_kinds_and_enabled(self):
        self.seed([entry("MODULE_MINE", name="mine", repo="https://x/mine.git"),
                   {"key": "MODULE_UP", "ref": "v1"},
                   {"key": "MODULE_GONE", "ref": "v1"}], env="MODULE_MINE=1\n")
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        lines = {line.split()[0]: line.split() for line in out.strip().splitlines()[1:]}
        self.assertEqual(lines["MODULE_MINE"][1:3], ["local", "yes"])
        self.assertEqual(lines["MODULE_UP"][1], "override")
        self.assertEqual(lines["MODULE_GONE"][1], "orphaned")

    def test_list_empty(self):
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        self.assertIn("No user-defined modules", out)

    def test_remove_local_module_disables_it(self):
        self.seed([entry("MODULE_MINE", name="mine")], env="MODULE_MINE=1\nA=1\n")
        rc, out, _ = self.run_cli("remove", "MODULE_MINE")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries(), [])
        self.assertIn("MODULE_MINE=0", self.env())
        self.assertIn("A=1", self.env())
        self.assertIn("stays in the database", out)

    def test_remove_override_keeps_env(self):
        self.seed([{"key": "MODULE_UP", "ref": "v1"}], env="MODULE_UP=1\n")
        rc, out, _ = self.run_cli("remove", "MODULE_UP")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries(), [])
        self.assertIn("MODULE_UP=1", self.env())
        self.assertIn("upstream", out)

    def test_remove_unknown_key(self):
        rc, _, err = self.run_cli("remove", "MODULE_NOPE")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_NOPE", err)

    def test_remove_refuses_invalid_local_file(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        path.write_text("{broken")
        rc, _, err = self.run_cli("remove", "MODULE_X")
        self.assertEqual(rc, 1)
        self.assertEqual(path.read_text(), "{broken")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: argparse errors (exit 2) for `list` and `remove`.

- [ ] **Step 3: Implement** (in `scripts/python/local_modules.py`)

```python
from modules import load_env_file, parse_bool


def cmd_list(args: argparse.Namespace, paths: Paths) -> int:
    upstream, local, _merged = _load(paths)
    if not local:
        print("No user-defined modules (config/module-manifest.local.json is empty or missing).")
        return 0
    upstream_keys = {m["key"] for m in upstream}
    env = load_env_file(paths.env)
    rows = [("KEY", "KIND", "ENABLED", "REPO")]
    for item in local:
        key = item["key"]
        if key in upstream_keys:
            kind = "override"
        elif item.get("name") and item.get("repo"):
            kind = "local"
        else:
            kind = "orphaned"
        enabled = "yes" if parse_bool(env.get(key, "0")) else "no"
        repo = item.get("repo", "(upstream repo)")
        if item.get("ref"):
            repo = f"{repo}@{item['ref']}"
        rows.append((key, kind, enabled, repo))
    widths = [max(len(r[i]) for r in rows) for i in range(3)]
    for row in rows:
        print("  ".join(cell.ljust(widths[i]) if i < 3 else cell for i, cell in enumerate(row)))
    return 0


def cmd_remove(args: argparse.Namespace, paths: Paths) -> int:
    upstream, local, _merged = _load(paths)
    key = args.key
    if not any(e["key"] == key for e in local):
        raise Refused(f"{key} has no entry in {paths.local.name}; ./modules.sh list shows the local entries")
    write_local_entries(paths.local, [e for e in local if e["key"] != key])
    if key in {m["key"] for m in upstream}:
        print(f"✅ Removed the local override for {key}; it goes back to its upstream repo/ref "
              f"on the next deploy. {key} in .env is unchanged.")
    else:
        set_env_value(paths.env, key, "0")
        print(f"✅ Removed {key} and set {key}=0 in .env. The next deploy removes its checkout "
              f"and staged Lua.")
    print("   SQL the module already applied stays in the database.")
    return 0
```

Parser entries, added in `build_parser` before `return parser`:

```python
    lst = sub.add_parser("list", help="Show user-defined modules and overrides")
    lst.set_defaults(func=cmd_list)

    rm = sub.add_parser("remove", help="Remove a user-defined module or override")
    rm.add_argument("key", help="MODULE_* key")
    rm.set_defaults(func=cmd_remove)
```

Move `from modules import load_env_file, parse_bool` to the import block, and drop the now-redundant local `from modules import build_state` in `cmd_add` in favour of a top-level `from modules import build_state, load_env_file, parse_bool`.

- [ ] **Step 4: Run all tests**

Run: `python3 -m unittest discover -s scripts/python/tests -t scripts/python -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/python/local_modules.py scripts/python/tests/test_local_modules_cli.py
git commit -m "feat(modules): ./modules.sh list and remove"
```

---

### Task 8: Docs and an end-to-end check on the local stack

**Files:**
- Modify: `docs/ADDING_MODULES.md` (the "aren't supported yet" paragraph, plus a new section)
- Modify: `docs/GETTING_STARTED.md` (the module metadata bullet)

**Interfaces:**
- Consumes: the finished `./modules.sh`.

`docs/ADDING_MODULES.md` is added by PR #47. Rebase this branch on `main` after #47 merges, before starting this task.

- [ ] **Step 1: Update `docs/ADDING_MODULES.md`**

Replace the paragraph starting "Modules that aren't public GitHub repositories" with:

```markdown
Modules that aren't public GitHub repositories, repositories without a topic, forks,
and pinned refs can be added locally with `./modules.sh` (next section).
```

Add this section after "Enabling a module":

````markdown
## Adding a module yourself (`./modules.sh`)

`./modules.sh` writes `config/module-manifest.local.json`, which is gitignored and
merged over the upstream manifest by every script that reads it. The sync never
touches it.

```bash
./modules.sh add https://gitlab.com/me/mod-thing.git          # add a new module
./modules.sh add https://github.com/me/mod-thing --ref v1.2   # pinned to a tag, branch or commit
./modules.sh add https://github.com/me/mod-transmog --key MODULE_TRANSMOG  # use your fork of a listed module
./modules.sh add --key MODULE_TRANSMOG --ref 1a2b3c4          # pin a listed module
./modules.sh list                                             # local entries: local, override or orphaned
./modules.sh remove MODULE_MOD_THING                          # undo an add or an override
```

- `add` clones the repository to a temp folder, works out the type (C++, Lua or
  SQL) and the staging hook, shows the entry and asks before writing it. It also
  enables the module (and anything it requires) in `.env`. `--yes` skips the
  question and `--no-enable` leaves `.env` alone.
- It refuses a repository that is already listed (enable its key instead), a key
  that's already taken (pass `--key`), and a repository it can't classify (pass
  `--type`). A Lua script collection needs `--type lua`, because staging a whole
  collection can crash the worldserver.
- Overrides are per field: `--ref` or a fork URL replaces only those fields, and
  everything else still comes from the upstream entry. If the sync later drops the
  upstream entry, a partial override is skipped with a warning; `list` shows it as
  `orphaned`.
- `remove` on your own module deletes it and sets it to `0` in `.env`. On an override,
  it restores the upstream repo/ref and leaves `.env` alone. SQL the module already
  applied stays in the database.
- Private repositories work when the host's git can clone them. The `ac-modules`
  container has no credentials, so a deploy can't clone them yet.
````

In `docs/GETTING_STARTED.md`, change the bullet to:

```markdown
- Module metadata lives in `config/module-manifest.json`, which is generated from GitHub topics; don't edit it by hand. Add your own modules with `./modules.sh` (see [ADDING_MODULES.md](ADDING_MODULES.md)).
```

- [ ] **Step 2: End-to-end on the local stack**

Use a git worktree for any branch switching while the stack runs: containers bind-mount scripts from the working tree.

```bash
./modules.sh add https://github.com/mostlynick3/azerothcore-lua-ah-bot --key MODULE_LUA_AH_BOT --ref master --yes   # override with a pinned ref
./modules.sh list
./deploy.sh --yes --no-watch
docker logs ac-modules 2>&1 | grep -E "azerothcore-lua-ah-bot|checkout|Staged"
./modules.sh remove MODULE_LUA_AH_BOT
./deploy.sh --yes --no-watch
```

Expected:
- `list` shows `MODULE_LUA_AH_BOT override`.
- The first deploy checks out `master` for that module and stages its Lua.
- `remove` says it goes back to upstream.
- The second deploy clones it from upstream again.
- `ac-worldserver` stays healthy: `docker inspect ac-worldserver --format '{{.RestartCount}}'` doesn't increase.

Then add a small public Lua module that isn't listed (choose one whose repository has no `azerothcore-lua` topic), deploy, and check `ls storage/lua_scripts/`. Remove it again, deploy, and check that its folder is gone.

- [ ] **Step 3: Commit**

```bash
git add docs/ADDING_MODULES.md docs/GETTING_STARTED.md
git commit -m "docs: document ./modules.sh for user-defined modules"
```

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
import re
from pathlib import Path
from typing import Dict, List, Tuple

LOCAL_MANIFEST_NAME = "module-manifest.local.json"

# Keys are written unquoted into .env/modules.env and names become directories
# (rm -rf'd when disabled), so both are restricted to safe characters.
KEY_PATTERN = re.compile(r"^MODULE_[A-Z0-9_]+$")
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def is_valid_key(key: object) -> bool:
    return isinstance(key, str) and bool(KEY_PATTERN.match(key))


def is_valid_name(name: object) -> bool:
    return isinstance(name, str) and bool(NAME_PATTERN.match(name)) and name not in (".", "..")


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
        if not is_valid_key(item["key"]):
            raise ManifestError(
                f"Local manifest {local_path}: entry {idx} has invalid key '{item['key']}' "
                "(keys look like MODULE_SOMETHING: capitals, digits and underscores)"
            )
        if "name" in item and not is_valid_name(item["name"]):
            raise ManifestError(
                f"Local manifest {local_path}: entry {idx} ({item['key']}) has invalid name '{item['name']}' "
                "(a folder name: letters, digits, '.', '_' and '-', not starting with '.' or '-')"
            )
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

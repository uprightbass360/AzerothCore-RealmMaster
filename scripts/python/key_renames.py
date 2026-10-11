#!/usr/bin/env python3
"""Apply MODULE_* key renames from config/key-renames.json.

The map is flat (old key -> new key) and applied in a single pass: every key
is looked up once and rewritten once. A value may itself be a key in the map;
that never chains. Shared by rename_keys.py (repo files, no backups) and the
``./modules.sh migrate`` subcommand (user files, with backups).
"""
from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

DEFAULT_RENAMES_PATH = "config/key-renames.json"
Change = Tuple[str, str]

# lead: optional indent and ``export``; key; rest: ``=value`` and anything after.
_ENV_LINE = re.compile(r"^(?P<lead>\s*(?:export\s+)?)(?P<key>MODULE_[A-Z0-9_]+)(?P<rest>\s*=.*)$")


class RenameError(ValueError):
    """The rename map is missing or malformed."""


def load_rename_map(path) -> Dict[str, str]:
    p = Path(path)
    if not p.exists():
        raise RenameError(f"{p}: rename map not found")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RenameError(f"{p}: {exc}") from exc
    if not isinstance(data, dict):
        raise RenameError(f"{p}: top level must be an object of old key -> new key")
    for old, new in data.items():
        if not (isinstance(new, str) and old.startswith("MODULE_") and new.startswith("MODULE_")):
            raise RenameError(f"{p}: {old!r} -> {new!r} must map a MODULE_* key to a MODULE_* key")
        if old == new:
            raise RenameError(f"{p}: {old!r} maps to itself")
    return dict(data)


def rewrite_env_text(text: str, renames: Dict[str, str]) -> Tuple[str, List[Change]]:
    """Rename keys on ``KEY=value`` lines; every other byte is preserved."""
    out: List[str] = []
    changes: List[Change] = []
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        match = _ENV_LINE.match(body)
        if match and match.group("key") in renames:
            old = match.group("key")
            new = renames[old]
            changes.append((old, new))
            body = f"{match.group('lead')}{new}{match.group('rest')}"
        out.append(body + ending)
    return "".join(out), changes


def rewrite_entries(entries: List[dict], renames: Dict[str, str]) -> List[Change]:
    """Rename ``key`` and ``requires`` on manifest entries, in place."""
    changes: List[Change] = []
    for entry in entries:
        key = entry.get("key")
        if key in renames:
            entry["key"] = renames[key]
            changes.append((key, renames[key]))
        requires = entry.get("requires")
        if isinstance(requires, list):
            changes.extend((dep, renames[dep]) for dep in requires if dep in renames)
            entry["requires"] = [renames.get(dep, dep) for dep in requires]
    return changes


def rewrite_key_list(keys: List[str], renames: Dict[str, str]) -> Tuple[List[str], List[Change]]:
    changes = [(key, renames[key]) for key in keys if key in renames]
    return [renames.get(key, key) for key in keys], changes


def backup_path(path: Path, now: datetime) -> Path:
    return path.with_name(path.name + now.strftime(".bak-%Y%m%d-%H%M%S"))


def _rewrite_file(path, renames, transform: Callable[[str], Tuple[str, List[Change]]],
                  backup: bool, now: Optional[datetime]) -> List[Change]:
    p = Path(path)
    raw = p.read_bytes()
    original = raw.decode("utf-8")
    updated, changes = transform(original)
    if not changes:
        return []
    if backup:
        backup_path(p, now or datetime.now()).write_bytes(raw)
    p.write_bytes(updated.encode("utf-8"))
    return changes


def rewrite_env_file(path, renames: Dict[str, str], *, backup: bool = True,
                     now: Optional[datetime] = None) -> List[Change]:
    return _rewrite_file(path, renames, lambda text: rewrite_env_text(text, renames), backup, now)


def _json_transform(renames: Dict[str, str], apply: Callable[[dict], List[Change]]):
    def transform(text: str) -> Tuple[str, List[Change]]:
        data = json.loads(text)
        changes = apply(data)
        return json.dumps(data, indent=2) + "\n", changes
    return transform


def rewrite_manifest_file(path, renames: Dict[str, str], *, backup: bool = True,
                          now: Optional[datetime] = None) -> List[Change]:
    """A ``{"modules": [entry, ...]}`` document (manifest or local overlay)."""
    def apply(data: dict) -> List[Change]:
        modules = data.get("modules") if isinstance(data, dict) else None
        return rewrite_entries([m for m in (modules or []) if isinstance(m, dict)], renames)
    return _rewrite_file(path, renames, _json_transform(renames, apply), backup, now)


def rewrite_profile_file(path, renames: Dict[str, str], *, backup: bool = True,
                         now: Optional[datetime] = None) -> List[Change]:
    """A ``{"modules": [key, ...]}`` document; other fields untouched."""
    def apply(data: dict) -> List[Change]:
        keys = data.get("modules") if isinstance(data, dict) else None
        if not isinstance(keys, list):
            return []
        data["modules"], changes = rewrite_key_list([str(k) for k in keys], renames)
        return changes
    return _rewrite_file(path, renames, _json_transform(renames, apply), backup, now)

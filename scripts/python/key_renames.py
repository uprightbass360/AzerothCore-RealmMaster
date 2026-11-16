#!/usr/bin/env python3
"""Apply MODULE_* key renames from config/key-renames.json.

The map is a list of waves. Each wave is a flat object (old key -> new key)
applied in a single pass: every key is looked up once and rewritten once, and
a value that is itself a key of the same wave never chains. Waves are applied
in id order, and an env file records the last wave applied to it as
``MODULES_KEY_SCHEMA=<id>`` so that running the tooling again applies nothing.
Shared by rename_keys.py (repo files, no backups) and the
``./modules.sh migrate`` subcommand (user files, with backups).
"""
from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, Iterable, List, NamedTuple, Optional, Sequence, Set, Tuple

DEFAULT_RENAMES_PATH = "config/key-renames.json"
SCHEMA_KEY = "MODULES_KEY_SCHEMA"
SCHEMA_FIELD = "key_schema"  # top-level field of JSON documents that hold module keys
Change = Tuple[str, str]
Renames = Dict[str, str]

# lead: optional indent and ``export``; key; rest: ``=value`` and anything after.
_ENV_LINE = re.compile(r"^(?P<lead>\s*(?:export\s+)?)(?P<key>MODULE_[A-Z0-9_]+)(?P<rest>\s*=.*)$")
_SCHEMA_LINE = re.compile(
    r"^(?P<lead>\s*(?:export\s+)?)" + SCHEMA_KEY + r"(?P<eq>\s*=\s*)(?P<value>[^\s#]*)(?P<rest>.*)$"
)


class RenameError(ValueError):
    """The rename map is missing or malformed."""


class Wave(NamedTuple):
    id: int
    renames: Renames


def _validate_renames(path: Path, wave_id: int, renames) -> Renames:
    if not isinstance(renames, dict) or not renames:
        raise RenameError(f"{path}: wave {wave_id} must have a non-empty 'renames' object")
    for old, new in renames.items():
        if not (isinstance(new, str) and old.startswith("MODULE_") and new.startswith("MODULE_")):
            raise RenameError(f"{path}: wave {wave_id}: {old!r} -> {new!r} must map a MODULE_* key to a MODULE_* key")
        if old == new:
            raise RenameError(f"{path}: wave {wave_id}: {old!r} maps to itself")
    return dict(renames)


def load_rename_waves(path) -> List[Wave]:
    """``{"waves": [{"id": 1, "renames": {...}}, ...]}`` with ids 1, 2, 3... in order."""
    p = Path(path)
    if not p.exists():
        raise RenameError(f"{p}: rename map not found")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RenameError(f"{p}: {exc}") from exc
    raw_waves = data.get("waves") if isinstance(data, dict) else None
    if not isinstance(raw_waves, list) or not raw_waves:
        raise RenameError(f'{p}: top level must be {{"waves": [...]}} with at least one wave')
    waves: List[Wave] = []
    renamed_away: set = set()
    for index, raw in enumerate(raw_waves, start=1):
        wave_id = raw.get("id") if isinstance(raw, dict) else None
        if isinstance(wave_id, bool) or not isinstance(wave_id, int) or wave_id != index:
            raise RenameError(f'{p}: wave #{index} must carry "id": {index} (ids are consecutive from 1)')
        renames = _validate_renames(p, wave_id, raw.get("renames"))
        repeated = renamed_away & set(renames)
        if repeated:
            raise RenameError(
                f"{p}: wave {wave_id} renames {sorted(repeated)[0]!r} again; a key is renamed away in one wave only"
            )
        renamed_away |= set(renames)
        waves.append(Wave(wave_id, renames))
    return waves


def cumulative_map(waves: Sequence[Wave]) -> Renames:
    """Old key -> final key: one lookup per wave in order, never chaining inside a wave."""
    out: Renames = {}
    for wave in waves:
        for old in wave.renames:
            key = old
            for step in waves:
                key = step.renames.get(key, key)
            out[old] = key
    return out


def introduced_keys(wave: Wave) -> Set[str]:
    """Keys that first exist once ``wave`` is applied: its new keys that are not also its old keys."""
    return set(wave.renames.values()) - set(wave.renames)


def ahead_of_schema(keys: Iterable[str], waves: Sequence[Wave], schema: int) -> Optional[int]:
    """The highest wave above ``schema`` whose introduced keys appear in ``keys``, or None.

    A document that records ``schema`` but holds such keys was migrated past it
    without a marker; applying the pending waves again would rename it wrongly.
    """
    present = set(keys)
    ahead = [wave.id for wave in waves if wave.id > schema and present & introduced_keys(wave)]
    return max(ahead) if ahead else None


def env_keys(text: str) -> List[str]:
    """The MODULE_* keys defined on ``KEY=value`` lines of an env file."""
    keys: List[str] = []
    for line in text.splitlines():
        match = _ENV_LINE.match(line)
        if match:
            keys.append(match.group("key"))
    return keys


def document_keys(data) -> List[str]:
    """The module keys a manifest-style or profile-style JSON document holds."""
    modules = data.get("modules") if isinstance(data, dict) else None
    if not isinstance(modules, list):
        return []
    keys: List[str] = []
    for item in modules:
        if isinstance(item, dict):
            if isinstance(item.get("key"), str):
                keys.append(item["key"])
            keys.extend(dep for dep in (item.get("requires") or []) if isinstance(dep, str))
        elif isinstance(item, str):
            keys.append(item)
    return keys


def read_schema(text: str) -> int:
    """The ``MODULES_KEY_SCHEMA`` value of an env file: 0 when absent, an error when present but not a number."""
    for line in text.splitlines():
        match = _SCHEMA_LINE.match(line)
        if match:
            value = match.group("value").strip().strip("\"'")
            if not value.isdigit():
                raise RenameError(f"{SCHEMA_KEY}={match.group('value')!r} is not a wave number")
            return int(value)
    return 0


def read_json_schema(data) -> int:
    """The ``key_schema`` of a parsed JSON document: 0 when absent, an error when not a non-negative integer."""
    if not isinstance(data, dict) or SCHEMA_FIELD not in data:
        return 0
    value = data[SCHEMA_FIELD]
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise RenameError(f"{SCHEMA_FIELD} must be a wave number, got {value!r}")
    return value


def catalogue_schema(manifest_path) -> int:
    """The catalogue's current schema: the top-level ``key_schema`` of config/module-manifest.json (0 when absent)."""
    return read_json_schema(json.loads(Path(manifest_path).read_text(encoding="utf-8")))


def set_schema_text(text: str, schema: int) -> str:
    """Set ``MODULES_KEY_SCHEMA=<schema>``: rewrite the existing line in place, else append in the file's line ending."""
    ending = "\r\n" if "\r\n" in text else "\n"
    out: List[str] = []
    done = False
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        match = _SCHEMA_LINE.match(body)
        if match and not done:
            body = f"{match.group('lead')}{SCHEMA_KEY}{match.group('eq')}{schema}{match.group('rest')}"
            done = True
        out.append(body + line[len(line.rstrip("\r\n")):])
    if not done:
        if out and not out[-1].endswith(("\n", "\r")):
            out[-1] += ending
        out.append(f"{SCHEMA_KEY}={schema}{ending}")
    return "".join(out)


def rewrite_env_text(text: str, renames: Renames) -> Tuple[str, List[Change]]:
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


def rewrite_entries(entries: List[dict], renames: Renames) -> List[Change]:
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


def rewrite_key_list(keys: List[str], renames: Renames) -> Tuple[List[str], List[Change]]:
    changes = [(key, renames[key]) for key in keys if key in renames]
    return [renames.get(key, key) for key in keys], changes


def backup_path(path: Path, now: datetime) -> Path:
    return path.with_name(path.name + now.strftime(".bak-%Y%m%d-%H%M%S"))


def _rewrite_file(path, transform: Callable[[str], Tuple[str, List[Change]]],
                  backup: bool, now: Optional[datetime]) -> List[Change]:
    """Read bytes, transform the text, write back only if it differs; one backup of the original first."""
    p = Path(path)
    raw = p.read_bytes()
    original = raw.decode("utf-8")
    updated, changes = transform(original)
    if updated == original:
        return []
    if backup:
        backup_path(p, now or datetime.now()).write_bytes(raw)
    p.write_bytes(updated.encode("utf-8"))
    return changes


def rewrite_env_file(path, passes: Sequence[Renames], *, schema: Optional[int] = None,
                     backup: bool = True, now: Optional[datetime] = None) -> List[Change]:
    """Apply each pass in order, then record ``schema`` when given."""
    def transform(text: str) -> Tuple[str, List[Change]]:
        changes: List[Change] = []
        for renames in passes:
            text, made = rewrite_env_text(text, renames)
            changes.extend(made)
        if schema is not None:
            text = set_schema_text(text, schema)
        return text, changes
    return _rewrite_file(path, transform, backup, now)


def _json_transform(apply: Callable[[dict], List[Change]]):
    def transform(text: str) -> Tuple[str, List[Change]]:
        data = json.loads(text)
        changes = apply(data)
        dirty = data != json.loads(text)
        return (json.dumps(data, indent=2) + "\n") if dirty else text, changes
    return transform


def rewrite_manifest_file(path, passes: Sequence[Renames], *, schema: Optional[int] = None, backup: bool = True,
                          now: Optional[datetime] = None) -> List[Change]:
    """A ``{"modules": [entry, ...]}`` document (manifest or local overlay)."""
    def apply(data: dict) -> List[Change]:
        modules = data.get("modules") if isinstance(data, dict) else None
        entries = [m for m in (modules or []) if isinstance(m, dict)]
        changes: List[Change] = []
        for renames in passes:
            changes.extend(rewrite_entries(entries, renames))
        if schema is not None and isinstance(data, dict):
            data[SCHEMA_FIELD] = schema
        return changes
    return _rewrite_file(path, _json_transform(apply), backup, now)


def rewrite_profile_file(path, passes: Sequence[Renames], *, schema: Optional[int] = None, backup: bool = True,
                         now: Optional[datetime] = None) -> List[Change]:
    """A ``{"modules": [key, ...]}`` document; other fields untouched."""
    def apply(data: dict) -> List[Change]:
        keys = data.get("modules") if isinstance(data, dict) else None
        if not isinstance(keys, list):
            return []
        keys = [str(k) for k in keys]
        changes: List[Change] = []
        for renames in passes:
            keys, made = rewrite_key_list(keys, renames)
            changes.extend(made)
        if changes:
            data["modules"] = keys
        if schema is not None:
            data[SCHEMA_FIELD] = schema
        return changes
    return _rewrite_file(path, _json_transform(apply), backup, now)

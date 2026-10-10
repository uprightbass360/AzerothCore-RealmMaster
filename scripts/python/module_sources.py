#!/usr/bin/env python3
"""Catalogue sources policy: declined repos, keep list and staleness window.

Owns ``config/module-sources.json``::

    {
      "policy":   {"stale_after_days": 1095, "ignore_profiles": ["all-modules.json"]},
      "declined": {"owner/*": {"reason": "...", "date": "YYYY-MM-DD"},
                   "owner/repo": {"reason": "...", "date": "YYYY-MM-DD"}},
      "keep":     ["owner/repo"]
    }

``declined`` repos are never admitted by the manifest sync and are removed if
present. ``keep`` repos are exempt from staleness review. Patterns and names
are matched case-insensitively on the GitHub ``owner/repo`` full name.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set

DEFAULT_SOURCES_PATH = "config/module-sources.json"
DEFAULT_STALE_AFTER_DAYS = 1095
DEFAULT_IGNORE_PROFILES = ["all-modules.json"]


class SourcesError(ValueError):
    """The sources file exists but cannot be used. Never ignored: a broken
    denylist must not silently readmit excluded repositories."""


def normalize_full_name(full_name: str) -> str:
    name = str(full_name).strip().strip("/")
    if name.endswith(".git"):
        name = name[:-4]
    return name.lower()


@dataclass
class Sources:
    stale_after_days: int = DEFAULT_STALE_AFTER_DAYS
    ignore_profiles: List[str] = field(default_factory=lambda: list(DEFAULT_IGNORE_PROFILES))
    # normalised pattern ("owner/repo" or "owner/*") -> {"reason": str, "date": "YYYY-MM-DD"}
    declined: Dict[str, dict] = field(default_factory=dict)
    # normalised "owner/repo"
    keep: Set[str] = field(default_factory=set)

    def is_declined(self, full_name: Optional[str]) -> Optional[str]:
        """Return the declined pattern matching ``full_name`` or None."""
        if not full_name:
            return None
        name = normalize_full_name(full_name)
        if name in self.declined:
            return name
        wildcard = f"{name.split('/', 1)[0]}/*"
        if wildcard in self.declined:
            return wildcard
        return None

    def is_kept(self, full_name: Optional[str]) -> bool:
        return bool(full_name) and normalize_full_name(full_name) in self.keep

    def stale_cutoff(self, today: date) -> date:
        return today - timedelta(days=self.stale_after_days)

    def decline(self, full_name: str, reason: str, on: date) -> None:
        self.declined[normalize_full_name(full_name)] = {"reason": reason, "date": on.isoformat()}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SourcesError(message)


def load_sources(path: str) -> Sources:
    """Parse the sources file; a missing file yields defaults, a bad one raises."""
    if not os.path.exists(path):
        return Sources()
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise SourcesError(f"{path}: {exc}") from exc
    _require(isinstance(data, dict), f"{path}: top level must be an object")

    policy = data.get("policy", {})
    _require(isinstance(policy, dict), f"{path}: 'policy' must be an object")
    days = policy.get("stale_after_days", DEFAULT_STALE_AFTER_DAYS)
    _require(isinstance(days, int) and not isinstance(days, bool) and days > 0,
             f"{path}: policy.stale_after_days must be a positive integer")
    ignore = policy.get("ignore_profiles", list(DEFAULT_IGNORE_PROFILES))
    _require(isinstance(ignore, list) and all(isinstance(x, str) for x in ignore),
             f"{path}: policy.ignore_profiles must be a list of file names")

    raw_declined = data.get("declined", {})
    _require(isinstance(raw_declined, dict), f"{path}: 'declined' must be an object")
    declined: Dict[str, dict] = {}
    for pattern, record in raw_declined.items():
        key = normalize_full_name(pattern)
        _require(key.count("/") == 1 and all(key.split("/")),
                 f"{path}: declined pattern {pattern!r} must be 'owner/repo' or 'owner/*'")
        _require(isinstance(record, dict) and isinstance(record.get("reason"), str),
                 f"{path}: declined[{pattern!r}] must be an object with a 'reason'")
        declined[key] = {"reason": record["reason"], "date": str(record.get("date", ""))}

    raw_keep = data.get("keep", [])
    _require(isinstance(raw_keep, list) and all(isinstance(x, str) for x in raw_keep),
             f"{path}: 'keep' must be a list of 'owner/repo' names")
    for name in raw_keep:
        _require("*" not in name,
                 f"{path}: keep entry {name!r} must be an exact 'owner/repo'; wildcards only work in 'declined'")

    return Sources(
        stale_after_days=days,
        ignore_profiles=list(ignore),
        declined=declined,
        keep={normalize_full_name(x) for x in raw_keep},
    )


def save_sources(sources: Sources, path: str) -> None:
    """Write the file with sorted keys so review diffs stay small."""
    data = {
        "policy": {
            "stale_after_days": sources.stale_after_days,
            "ignore_profiles": list(sources.ignore_profiles),
        },
        "declined": {key: sources.declined[key] for key in sorted(sources.declined)},
        "keep": sorted(sources.keep),
    }
    Path(path).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def profile_keys(profiles_dir: str, ignore_profiles: Sequence[str]) -> Set[str]:
    """Module keys referenced by curated profiles (every *.json not in ``ignore_profiles``)."""
    root = Path(profiles_dir)
    if not root.is_dir():
        return set()
    keys: Set[str] = set()
    for path in sorted(root.glob("*.json")):
        if path.name in ignore_profiles:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        modules = data.get("modules") if isinstance(data, dict) else None
        if isinstance(modules, list):
            keys.update(str(key) for key in modules)
    return keys

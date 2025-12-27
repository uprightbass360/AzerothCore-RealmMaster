#!/usr/bin/env python3
"""
Expose profile metadata for setup.sh.

Profiles are JSON documents with at least:
{
  "modules": ["MODULE_FOO", "MODULE_BAR"],
  "label": "...",            # optional
  "description": "..."       # optional
}
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Iterable, List, Tuple


def normalize_modules(raw_modules: Iterable[str], profile: Path) -> List[str]:
    """Return a cleaned list of module identifiers."""
    modules: List[str] = []
    for item in raw_modules:
        if not isinstance(item, str):
            raise ValueError(f"Profile {profile.name}: module entries must be strings")
        value = item.strip()
        if not value:
            continue
        modules.append(value)
    # Allow empty modules list for vanilla/minimal profiles
    if not modules and "vanilla" not in profile.stem.lower() and "minimal" not in profile.stem.lower():
        raise ValueError(f"Profile {profile.name}: modules list cannot be empty (except for vanilla/minimal profiles)")
    return modules


def sanitize(text: str | None) -> str:
    if not text:
        return ""
    return str(text).replace("\t", " ").replace("\n", " ").strip()


def load_profile(path: Path) -> Tuple[str, List[str], str, str, int]:
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"Profile {path.name}: invalid JSON - {exc}") from exc

    raw_modules = data.get("modules")
    if not isinstance(raw_modules, list):
        raise ValueError(f"Profile {path.name}: 'modules' must be a list")

    modules = normalize_modules(raw_modules, path)
    name = data.get("name") or path.stem
    label = sanitize(data.get("label")) or " ".join(part.capitalize() for part in name.replace("-", " ").split())
    description = sanitize(data.get("description"))

    order_raw = data.get("order")
    try:
        order = int(order_raw) if order_raw is not None else 10000
    except (TypeError, ValueError):
        raise ValueError(f"Profile {path.name}: 'order' must be an integer") from None

    return name, modules, label, description, order


def cmd_list(directory: Path) -> int:
    if not directory.is_dir():
        print(f"ERROR: Profile directory not found: {directory}", file=sys.stderr)
        return 1

    profiles: List[Tuple[str, List[str], str, str, int]] = []
    for candidate in sorted(directory.glob("*.json")):
        try:
            profiles.append(load_profile(candidate))
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

    profiles.sort(key=lambda item: item[4])

    for name, modules, label, description, order in profiles:
        modules_csv = ",".join(modules)
        print("\t".join([name, modules_csv, label, description, str(order)]))
    return 0


COMMANDS = {
    "list": cmd_list,
}


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print(f"Usage: {argv[0]} <command> <profiles-dir>", file=sys.stderr)
        return 1

    command = argv[1]
    handler = COMMANDS.get(command)
    if handler is None:
        valid = ", ".join(sorted(COMMANDS))
        print(f"Unknown command '{command}'. Valid commands: {valid}", file=sys.stderr)
        return 1

    directory = Path(argv[2])
    return handler(directory)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

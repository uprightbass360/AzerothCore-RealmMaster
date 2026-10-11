#!/usr/bin/env python3
"""Apply config/key-renames.json to the repository's own catalogue files.

Rewrites config/module-manifest.json, every config/module-profiles/*.json,
.env.template and .env.prebuilt in place, without backups (git is the backup).
Used once per rename wave by the maintainer; users run ``./modules.sh migrate``.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

from key_renames import (
    DEFAULT_RENAMES_PATH,
    RenameError,
    load_rename_map,
    rewrite_env_text,
    rewrite_entries,
    rewrite_env_file,
    rewrite_manifest_file,
    rewrite_profile_file,
)


def _targets(root: Path):
    yield root / "config" / "module-manifest.json", rewrite_manifest_file
    for profile in sorted((root / "config" / "module-profiles").glob("*.json")):
        yield profile, rewrite_profile_file
    for name in (".env.template", ".env.prebuilt"):
        path = root / name
        if path.exists():
            yield path, rewrite_env_file


def _count_dry(path: Path, renames) -> int:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".json":
        data = json.loads(text)
        modules = data.get("modules") or []
        if modules and isinstance(modules[0], dict):
            return len(rewrite_entries(modules, renames))
        return sum(1 for k in modules if k in renames)
    return len(rewrite_env_text(text, renames)[1])


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--renames", default=None, help=f"default: <root>/{DEFAULT_RENAMES_PATH}")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root)
    try:
        renames = load_rename_map(Path(args.renames) if args.renames else root / DEFAULT_RENAMES_PATH)
    except RenameError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    total = 0
    for path, rewrite in _targets(root):
        if args.dry_run:
            count = _count_dry(path, renames)
            prefix = "[dry-run] "
        else:
            count = len(rewrite(path, renames, backup=False))
            prefix = ""
        total += count
        print(f"{prefix}{path.relative_to(root)}: {count}")
    print(f"{'[dry-run] ' if args.dry_run else ''}total renames applied: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

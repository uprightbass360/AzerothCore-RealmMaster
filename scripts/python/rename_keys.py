#!/usr/bin/env python3
"""Apply one wave of config/key-renames.json to the repository's own catalogue files.

Rewrites config/module-manifest.json, every config/module-profiles/*.json,
.env.template and .env.prebuilt in place, without backups (git is the backup),
and records the wave in the two env templates as MODULES_KEY_SCHEMA=<wave>.
Run once per wave by the maintainer, after appending the wave to the map;
users run ``./modules.sh migrate`` instead.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Callable, Iterator, List, Optional, Tuple

from key_renames import (
    DEFAULT_RENAMES_PATH,
    SCHEMA_KEY,
    RenameError,
    Wave,
    load_rename_waves,
    rewrite_entries,
    rewrite_env_file,
    rewrite_env_text,
    rewrite_manifest_file,
    rewrite_profile_file,
)

Target = Tuple[Path, Callable[[Path], int], str]


def _targets(root: Path, wave: Wave) -> Iterator[Target]:
    passes = [wave.renames]
    yield root / "config" / "module-manifest.json", lambda p: len(rewrite_manifest_file(p, passes, backup=False)), ""
    for profile in sorted((root / "config" / "module-profiles").glob("*.json")):
        yield profile, lambda p: len(rewrite_profile_file(p, passes, backup=False)), ""
    for name in (".env.template", ".env.prebuilt"):
        path = root / name
        if path.exists():
            yield path, lambda p: len(rewrite_env_file(p, passes, schema=wave.id, backup=False)), f", {SCHEMA_KEY}={wave.id}"


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
    parser.add_argument("--wave", type=int, required=True, help="id of the wave to apply")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root)
    renames_path = Path(args.renames) if args.renames else root / DEFAULT_RENAMES_PATH
    try:
        waves = load_rename_waves(renames_path)
    except RenameError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    wave = next((w for w in waves if w.id == args.wave), None)
    if wave is None:
        print(f"❌ wave {args.wave} is not in {renames_path} (waves: {', '.join(str(w.id) for w in waves)})", file=sys.stderr)
        return 1
    total = 0
    for path, rewrite, note in _targets(root, wave):
        if args.dry_run:
            count = _count_dry(path, wave.renames)
            prefix, suffix = "[dry-run] ", ""
        else:
            count = rewrite(path)
            prefix, suffix = "", note
        total += count
        print(f"{prefix}{path.relative_to(root)}: {count}{suffix}")
    print(f"{'[dry-run] ' if args.dry_run else ''}total renames applied: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
Utility commands for setup.sh to read module manifest metadata.
"""

import json
import sys
from pathlib import Path
from typing import Iterable, List


def load_manifest(path: str) -> dict:
    manifest_path = Path(path)
    if not manifest_path.is_file():
        print(f"ERROR: Module manifest not found at {manifest_path}", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(manifest_path.read_text())
    except json.JSONDecodeError as exc:
        print(f"ERROR: Failed to parse manifest {manifest_path}: {exc}", file=sys.stderr)
        sys.exit(1)


def iter_modules(manifest: dict) -> Iterable[dict]:
    modules = manifest.get("modules") or []
    for entry in modules:
        if isinstance(entry, dict) and entry.get("key"):
            yield entry


def unique_preserve_order(values: Iterable[str]) -> List[str]:
    seen = set()
    ordered: List[str] = []
    for value in values:
        if not value:
            continue
        if value not in seen:
            seen.add(value)
            ordered.append(value)
    return ordered


def clean(value: str) -> str:
    if value is None:
        return "-"
    text = str(value).replace("\t", " ").replace("\n", " ").strip()
    return text if text else "-"


def cmd_keys(manifest_path: str) -> None:
    manifest = load_manifest(manifest_path)
    for entry in iter_modules(manifest):
        # Skip blocked modules
        if entry.get("status") == "blocked":
            continue
        print(entry["key"])


def cmd_metadata(manifest_path: str) -> None:
    manifest = load_manifest(manifest_path)
    for entry in iter_modules(manifest):
        key = entry["key"]
        name = clean(entry.get("name", key))
        module_type_raw = entry.get("type", "")
        module_type = clean(module_type_raw)
        needs_build_flag = entry.get("needs_build")
        if needs_build_flag is None:
            needs_build = "1" if str(module_type_raw).lower() == "cpp" else "0"
        else:
            needs_build = "1" if needs_build_flag else "0"
        status = clean(entry.get("status", "active"))
        block_reason = clean(entry.get("block_reason", ""))
        requires = unique_preserve_order(entry.get("requires") or [])
        requires_csv = ",".join(requires) if requires else "-"
        notes = clean(entry.get("notes", ""))
        description = clean(entry.get("description", ""))
        category = clean(entry.get("category", ""))
        special_message = clean(entry.get("special_message", ""))
        repo = clean(entry.get("repo", ""))
        print(
            "\t".join(
                [
                    key,
                    name,
                    needs_build,
                    module_type if module_type != "" else "-",
                    status,
                    block_reason,
                    requires_csv,
                    notes,
                    description,
                    category,
                    special_message,
                    repo,
                ]
            )
        )


def cmd_sorted_keys(manifest_path: str) -> None:
    manifest = load_manifest(manifest_path)
    modules = [entry for entry in iter_modules(manifest) if entry.get("status") != "blocked"]
    modules.sort(
        key=lambda item: (
            # Primary sort by order (default to 5000 if not specified)
            item.get("order", 5000),
            # Secondary sort by type
            str(item.get("type", "")),
            # Tertiary sort by name (case insensitive)
            str(item.get("name", item.get("key", ""))).lower(),
        )
    )
    for entry in modules:
        print(entry["key"])


COMMAND_MAP = {
    "keys": cmd_keys,
    "metadata": cmd_metadata,
    "sorted-keys": cmd_sorted_keys,
}


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print(f"Usage: {argv[0]} <command> <manifest-path>", file=sys.stderr)
        return 1

    command = argv[1]
    manifest_path = argv[2]
    handler = COMMAND_MAP.get(command)
    if handler is None:
        valid = ", ".join(sorted(COMMAND_MAP))
        print(f"Unknown command '{command}'. Valid commands: {valid}", file=sys.stderr)
        return 1

    handler(manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

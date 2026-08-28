#!/usr/bin/env python3
"""Round-trip check for config-ui file formats.

This script is the format authority: tools/config-ui/app.js mirrors these
parse/serialize rules. It parses every profile and preset in the repo,
re-serializes, re-parses, and requires semantic equality. Run manually or
as the gate step in the Pages workflow; exits 1 on any mismatch.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def parse_profile(text):
    data = json.loads(text)
    return {
        "modules": sorted(data.get("modules", [])),
        "label": data.get("label", ""),
        "description": data.get("description", ""),
        "order": data.get("order", 10000),
    }


def serialize_profile(profile, order_map):
    modules = sorted(
        profile["modules"],
        key=lambda k: (order_map.get(k, 99999), k),
    )
    doc = {
        "modules": modules,
        "label": profile["label"],
        "description": profile["description"],
        "order": profile["order"],
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def parse_preset(text):
    name = ""
    description = ""
    entries = []  # list of (target_file, key, value)
    section = None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"#\s*CONFIG_NAME:\s*(.*)", s)
        if m:
            name = m.group(1).strip()
            continue
        m = re.match(r"#\s*CONFIG_DESCRIPTION:\s*(.*)", s)
        if m:
            description = m.group(1).strip()
            continue
        if not s or s.startswith("#"):
            continue
        m = re.match(r"\[(.+)\]$", s)
        if m:
            section = m.group(1)
            continue
        if "=" in s:
            key, value = s.split("=", 1)
            entries.append((section or "worldserver.conf", key.strip(), value.strip()))
    return {"name": name, "description": description, "entries": entries}


def serialize_preset(preset):
    lines = [
        f"# CONFIG_NAME: {preset['name']}",
        f"# CONFIG_DESCRIPTION: {preset['description']}",
        "",
    ]
    current = None
    for target_file, key, value in preset["entries"]:
        if target_file != current:
            if current is not None:
                lines.append("")
            lines.append(f"[{target_file}]")
            current = target_file
        lines.append(f"{key} = {value}")
    return "\n".join(lines).rstrip("\n") + "\n"


def main() -> int:
    data = json.loads((REPO / "config/module-manifest.json").read_text())
    manifest = data.get("modules", data) if isinstance(data, dict) else data
    order_map = {m["key"]: m.get("order", 99999) for m in manifest}
    valid_keys = set(order_map)
    failures = 0

    for path in sorted((REPO / "config/module-profiles").glob("*.json")):
        original = parse_profile(path.read_text())
        rebuilt = parse_profile(serialize_profile(original, order_map))
        if original != rebuilt:
            print(f"FAIL round-trip: {path}")
            failures += 1
        unknown = [k for k in original["modules"] if k not in valid_keys]
        if unknown:
            print(f"FAIL unknown module keys in {path.name}: {', '.join(unknown)}")
            failures += 1

    for path in sorted((REPO / "config/presets").glob("*.conf")):
        original = parse_preset(path.read_text())
        rebuilt = parse_preset(serialize_preset(original))
        if original != rebuilt:
            print(f"FAIL round-trip: {path}")
            failures += 1

    if failures:
        print(f"{failures} failure(s)")
        return 1
    print("round-trip OK: all profiles and presets")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Generate config/index.json listing profile and preset files.

A static page cannot enumerate directories; the Pages workflow and
serve.sh both run this so the UI knows what exists.
"""
import json
import sys
from pathlib import Path

def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "config")
    index = {
        "profiles": sorted(p.name for p in (target / "module-profiles").glob("*.json")),
        "presets": sorted(p.name for p in (target / "presets").glob("*.conf")),
    }
    out = target / "index.json"
    out.write_text(json.dumps(index, indent=2) + "\n")
    print(f"wrote {out}: {len(index['profiles'])} profiles, {len(index['presets'])} presets")

if __name__ == "__main__":
    main()

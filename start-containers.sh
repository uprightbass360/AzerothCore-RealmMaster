#!/bin/bash

# Thin wrapper to bring the AzerothCore stack online without triggering rebuilds.
# Picks the right profile automatically (standard/playerbots/modules) and delegates
# to deploy.sh so all staging/health logic stays consistent.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROFILE="$(python3 - <<'PY' "$ROOT_DIR"
import json, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
modules_py = root / "scripts" / "modules.py"
env_path = root / ".env"
manifest_path = root / "config" / "modules.json"

state = json.loads(subprocess.check_output([
    sys.executable,
    str(modules_py),
    "--env-path", str(env_path),
    "--manifest", str(manifest_path),
    "dump", "--format", "json",
]))

enabled = [m for m in state["modules"] if m["enabled"]]
profile = "standard"
if any(m["key"] == "MODULE_PLAYERBOTS" and m["enabled"] for m in enabled):
    profile = "playerbots"
elif any(m["needs_build"] and m["enabled"] for m in enabled):
    profile = "modules"

print(profile)
PY
)"

exec "${ROOT_DIR}/deploy.sh" --profile "$PROFILE" --yes --no-watch

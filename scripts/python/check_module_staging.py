#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path


def load_module_state(root: Path) -> dict:
    env_path = root / ".env"
    manifest_path = root / "config" / "module-manifest.json"
    modules_py = root / "scripts" / "python" / "modules.py"

    try:
        output = subprocess.check_output(
            [
                sys.executable,
                str(modules_py),
                "--env-path",
                str(env_path),
                "--manifest",
                str(manifest_path),
                "dump",
                "--format",
                "json",
            ],
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        print("Unable to load module state:", exc, file=sys.stderr)
        sys.exit(2)

    return json.loads(output)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    data = load_module_state(root)

    enabled_modules = [m for m in data["modules"] if m["enabled"]]
    storage_dir = root / "storage" / "modules"

    local_root = Path(os.environ.get("STORAGE_PATH_LOCAL", "./local-storage"))
    local_root = (root / local_root).resolve()
    requires_playerbots = any(m["key"] == "MODULE_PLAYERBOTS" and m["enabled"] for m in enabled_modules)
    source_dir = local_root / "source"
    source_dir = source_dir / ("azerothcore-playerbots" if requires_playerbots else "azerothcore") / "modules"

    print(f"📦 Checking module staging in {storage_dir} and {source_dir}")
    print("Enabled modules:", ", ".join(m["name"] for m in enabled_modules))

    status = 0
    for module in enabled_modules:
        dir_name = module["name"]
        storage_path = storage_dir / dir_name
        source_path = source_dir / dir_name

        def state(path: Path) -> str:
            if (path / ".git").is_dir():
                return "git"
            if path.is_dir():
                return "present"
            return "missing"

        storage_state = state(storage_path)
        source_state = state(source_path)
        print(f" - {dir_name} ({module['key']}): storage={storage_state}, source={source_state}")

        if storage_state == "missing" or source_state == "missing":
            status = 1

    return status


if __name__ == "__main__":
    sys.exit(main())

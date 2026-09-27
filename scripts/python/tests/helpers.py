"""Shared helpers for scripts/python tests."""
import json
from pathlib import Path
from typing import List


def write_manifest(path: Path, modules: List[dict]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"modules": modules}, indent=2) + "\n")
    return path


def entry(key: str, **fields) -> dict:
    base = {"key": key, "name": key.lower().replace("_", "-"), "repo": f"https://github.com/example/{key.lower()}.git"}
    base.update(fields)
    return base

#!/usr/bin/env python3
"""
./modules.sh backend: add, list and remove user-defined modules.

Entries live in config/module-manifest.local.json (gitignored), merged over the
upstream manifest by scripts/python/manifest_overlay.py. See
docs/ADDING_MODULES.md.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional

GIT_TIMEOUT_SECONDS = 600


class ProbeError(RuntimeError):
    """The repository could not be cloned at the requested ref."""


def normalize_repo(url: str) -> str:
    value = url.strip().lower()
    value = re.sub(r"^[a-z]+://", "", value)
    value = value.rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    return value.rstrip("/")


def repo_basename(url: str) -> str:
    name = url.strip().rstrip("/").split("/")[-1]
    return name[:-4] if name.endswith(".git") else name


def set_env_value(env_path: Path, key: str, value: str) -> None:
    env_path = Path(env_path)
    lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
    pattern = re.compile(rf"^\s*(export\s+)?{re.escape(key)}=")
    out: List[str] = []
    written = False
    for line in lines:
        if pattern.match(line):
            if not written:
                out.append(f"{key}={value}")
                written = True
            continue
        out.append(line)
    if not written:
        out.append(f"{key}={value}")
    env_path.write_text("\n".join(out) + "\n", encoding="utf-8")


def write_local_entries(local_path: Path, entries: List[dict]) -> None:
    local_path = Path(local_path)
    local_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=local_path.parent, prefix=".module-manifest.local.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"modules": entries}, fh, indent=2)
            fh.write("\n")
        os.chmod(tmp_name, 0o644)
        os.replace(tmp_name, local_path)
    except BaseException:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise


def _git(args: List[str], url: Optional[str] = None) -> subprocess.CompletedProcess:
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    if "GIT_SSH_COMMAND" not in env:
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
    try:
        return subprocess.run(["git", *args], capture_output=True, text=True, env=env, timeout=GIT_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        raise ProbeError(f"Could not clone {url}: timed out after {GIT_TIMEOUT_SECONDS} seconds" if url else f"Git command timed out after {GIT_TIMEOUT_SECONDS} seconds")


def probe_clone(url: str, ref: Optional[str], dest: Path) -> None:
    dest = Path(dest)
    args = ["clone", "--quiet", "--depth", "1"]
    if ref:
        args += ["--branch", ref]
    try:
        result = _git([*args, url, str(dest)], url=url)
    except ProbeError:
        shutil.rmtree(dest, ignore_errors=True)
        raise
    if result.returncode == 0:
        return
    if not ref:
        raise ProbeError(f"Could not clone {url}: {result.stderr.strip()}")
    # --branch only takes branches and tags; a commit SHA needs a full clone.
    shutil.rmtree(dest, ignore_errors=True)
    try:
        full = _git(["clone", "--quiet", url, str(dest)], url=url)
    except ProbeError:
        shutil.rmtree(dest, ignore_errors=True)
        raise
    if full.returncode != 0:
        raise ProbeError(f"Could not clone {url}: {full.stderr.strip()}")
    try:
        checkout = _git(["-C", str(dest), "checkout", "--quiet", ref], url=url)
    except ProbeError:
        shutil.rmtree(dest, ignore_errors=True)
        raise
    if checkout.returncode != 0:
        shutil.rmtree(dest, ignore_errors=True)
        raise ProbeError(f"Ref '{ref}' not found in {url}: {checkout.stderr.strip()}")

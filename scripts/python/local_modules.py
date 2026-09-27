#!/usr/bin/env python3
"""
./modules.sh backend: add, list and remove user-defined modules.

Entries live in config/module-manifest.local.json (gitignored), merged over the
upstream manifest by scripts/python/manifest_overlay.py. See
docs/ADDING_MODULES.md.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional

from manifest_overlay import (
    ManifestError,
    is_valid_key,
    is_valid_name,
    load_local_entries,
    local_manifest_path,
    merge_manifest,
)
from module_detect import detect
from modules import build_state, load_env_file, parse_bool
from update_module_manifest import repo_name_to_key

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


WORLDSERVER_WARNING = (
    "⚠️  Lua and SQL from this module run inside your worldserver. If the worldserver "
    "crash-loops after deploying, run ./modules.sh remove {key} and deploy again."
)


def _warn_type_ignored(key: str, module_type: str) -> None:
    print(f"WARNING: --type is ignored for {key}; its type is defined by the listed "
          f"entry ({module_type})", file=sys.stderr)


# `remove` leaves this marker in place of a local-only entry, so the next deploy
# still knows the module and cleans it up like any disabled module (checkout,
# staged Lua, SQL staging, C++ build set). `add` of the same URL or key replaces it.
TOMBSTONE_REASON = "removed with ./modules.sh remove"


def is_tombstone(item: dict) -> bool:
    return (str(item.get("status", "")).lower() == "blocked"
            and item.get("block_reason") == TOMBSTONE_REASON
            and item.get("source", "local") == "local")


def tombstone_for(item: dict) -> dict:
    return {"key": item["key"], "name": item["name"], "repo": item["repo"],
            "status": "blocked", "block_reason": TOMBSTONE_REASON}


class Refused(Exception):
    """add/remove refused with a message for the user (exit code 1)."""


def _check_key(key: str) -> None:
    if not is_valid_key(key):
        raise Refused(f"Invalid key '{key}'. Keys look like MODULE_SOMETHING: capitals, digits and underscores.")


def _check_name(name: str, url: str) -> None:
    if not is_valid_name(name):
        raise Refused(f"'{name}' (from {url}) can't be used as a module folder name: use letters, digits, "
                      "'.', '_' and '-', not starting with '.' or '-'.")


class Paths:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.manifest = self.root / "config" / "module-manifest.json"
        self.local = local_manifest_path(self.manifest)
        self.env = self.root / ".env"


def _load(paths: Paths):
    try:
        local = load_local_entries(paths.local)
    except ManifestError as exc:
        raise Refused(f"{exc}\nFix or remove {paths.local} first; it was not modified.")
    upstream = json.loads(paths.manifest.read_text(encoding="utf-8")).get("modules", [])
    merged, warnings = merge_manifest(upstream, local)
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    return upstream, local, merged


def _confirm(prompt: str, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    try:
        return input(f"{prompt} [y/N]: ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def _enable(paths: Paths, keys: List[str]) -> None:
    for key in keys:
        set_env_value(paths.env, key, "1")
        print(f"   enabled {key}=1 in .env")


def _finish(paths: Paths, key: str, requires: List[str], module_type: str,
            is_override: bool, no_enable: bool) -> int:
    """Shared tail for every add path: enable, validate, warn, and say what's next."""
    if not no_enable:
        _enable(paths, [key] + list(requires))

    state = build_state(paths.env, paths.manifest)
    relevant = {key} if no_enable else {key, *requires}
    blocking = [error for error in state.errors
                if set(re.findall(r"\bMODULE_[A-Z0-9_]+\b", error)) & relevant]
    other = [error for error in state.errors if error not in blocking]
    for warning in other:
        print(f"WARNING: {warning}", file=sys.stderr)
    for error in blocking:
        print(f"ERROR: {error}", file=sys.stderr)

    print(WORLDSERVER_WARNING.format(key=key))
    if module_type == "cpp":
        print("Next: ./build.sh --force (rebuilds even though the module name hasn't changed)"
              if is_override else "Next: ./build.sh")
    else:
        print("Next: ./deploy.sh")

    if blocking:
        print(f"{key} was kept in {paths.local.name} despite the error(s) above; "
              f"run ./modules.sh remove {key} to remove it.", file=sys.stderr)
        return 1
    return 0


def cmd_add(args: argparse.Namespace, paths: Paths) -> int:
    if args.key:
        _check_key(args.key)
    upstream, local, merged = _load(paths)
    by_key = {m["key"]: m for m in merged}
    local_by_key = {e["key"]: e for e in local}
    upstream_keys = {m["key"] for m in upstream}

    # Ref-only override of a listed module: no clone, nothing to detect.
    if not args.url:
        if not args.key or not args.ref:
            raise Refused("add needs a git URL, or --key MODULE_X --ref <ref> to pin a listed module")
        if args.key not in by_key:
            raise Refused(f"{args.key} is not in the manifest; give a git URL to add it")
        listed = by_key[args.key]
        if is_tombstone(listed):
            raise Refused(f"{args.key} was removed; add it again with ./modules.sh add {listed['repo']}")
        module_type = str(listed.get("type", "cpp"))
        requires = [str(r) for r in (listed.get("requires") or [])]
        if args.type:
            _warn_type_ignored(args.key, module_type)
        override = local_by_key.get(args.key, {"key": args.key})
        override = {**override, "ref": args.ref}
        print(json.dumps(override, indent=2))
        if not _confirm(f"Pin {args.key} to {args.ref}?", args.yes):
            raise Refused("Nothing written. (Use --yes to skip the confirmation.)")
        write_local_entries(paths.local, [e for e in local if e["key"] != args.key] + [override])
        print(f"✅ {args.key} pinned to {args.ref} in {paths.local.name}")
        return _finish(paths, args.key, requires, module_type, True, args.no_enable)

    def drop_tombstone(tomb_key: str) -> None:
        nonlocal local, merged
        local = [e for e in local if e["key"] != tomb_key]
        merged = [m for m in merged if m["key"] != tomb_key]
        by_key.pop(tomb_key, None)
        local_by_key.pop(tomb_key, None)

    wanted = normalize_repo(args.url)
    same_repo = next((m for m in merged if normalize_repo(str(m.get("repo", ""))) == wanted), None)
    tombstone_key = None
    if same_repo and is_tombstone(same_repo):
        # Re-adding a removed module: its tombstone is replaced.
        tombstone_key = same_repo["key"]
        drop_tombstone(tombstone_key)
        same_repo = None
    if same_repo and args.key != same_repo["key"]:
        where = "added locally" if same_repo.get("source") == "local" else "in the manifest"
        raise Refused(f"{args.url} is already {where} as {same_repo['key']}; "
                      f"enable it with {same_repo['key']}=1 in .env")

    name = repo_basename(args.url)
    _check_name(name, args.url)
    key = args.key or tombstone_key or repo_name_to_key(name)
    _check_key(key)
    if key in by_key and is_tombstone(by_key[key]):
        drop_tombstone(key)

    # A new entry (key not already in the merged manifest) targeting a folder name
    # that's already listed would clone a second module into that folder. This
    # never applies to an override of an existing key -- that key's own entry may
    # legitimately share its folder name with another, unrelated entry (several
    # upstream modules are listed twice, once under a fork's own key).
    if key not in by_key:
        same_name = next((m for m in merged if m.get("name") == name), None)
        if same_name:
            raise Refused(
                f"{name} is already the folder of {same_name['key']} ({same_name.get('repo')}). "
                f"To use your fork in place of it, run ./modules.sh add {args.url} --key {same_name['key']}"
            )

    is_override = key in upstream_keys
    if not args.key and key in by_key:
        raise Refused(f"Key {key} is already used by {by_key[key].get('repo')}; choose one with --key MODULE_...")

    with tempfile.TemporaryDirectory(prefix="realmmaster-probe-") as tmp:
        checkout = Path(tmp) / name
        try:
            probe_clone(args.url, args.ref, checkout)
        except ProbeError as exc:
            raise Refused(str(exc))
        detection = detect(checkout, by_key[key]["name"] if is_override else name)

    if is_override:
        listed = by_key[key]
        module_type = str(listed.get("type", "cpp"))
        requires = [str(r) for r in (listed.get("requires") or [])]

        if args.type:
            _warn_type_ignored(key, module_type)
        if detection.module_type and detection.module_type != module_type:
            print(f"WARNING: {args.url} looks like {detection.module_type}, but {key} is "
                  f"{module_type} upstream", file=sys.stderr)
        for warning in detection.warnings:
            print(f"WARNING: {warning}", file=sys.stderr)

        existing_override = local_by_key.get(key, {"key": key})
        new_entry = {**existing_override, "key": key, "repo": args.url}
        if args.ref:
            new_entry["ref"] = args.ref
    else:
        module_type = args.type or detection.module_type
        if module_type is None:
            raise Refused(f"Could not tell how to install {name}: {detection.reason}. "
                          "Pass --type cpp|lua|sql if you know better.")
        if detection.is_collection and args.type != "lua":
            raise Refused(f"{name} looks like a Lua script collection (many scripts or folders). "
                          "Staging all of it can break the worldserver; copy the scripts you want into "
                          "storage/lua_scripts/ yourself, or pass --type lua to stage everything.")
        for warning in detection.warnings:
            print(f"WARNING: {warning}", file=sys.stderr)

        hooks = detection.post_install_hooks if module_type == detection.module_type else []
        if module_type == "lua" and not hooks:
            hooks, requires = ["copy-standard-lua"], ["MODULE_ELUNA"]
        else:
            requires = detection.requires if module_type == detection.module_type else []

        new_entry = {"key": key, "name": name, "repo": args.url, "type": module_type,
                     "post_install_hooks": hooks, "requires": requires,
                     "description": f"User module from {args.url}", "category": "local"}
        if args.ref:
            new_entry["ref"] = args.ref

    print(json.dumps(new_entry, indent=2))
    if not _confirm(f"Add {key}?", args.yes):
        raise Refused("Nothing written. (Use --yes to skip the confirmation.)")
    write_local_entries(paths.local, [e for e in local if e["key"] != key] + [new_entry])
    print(f"✅ {key} written to {paths.local.name}")

    return _finish(paths, key, requires, module_type, is_override, args.no_enable)


def cmd_list(args: argparse.Namespace, paths: Paths) -> int:
    upstream, local, _merged = _load(paths)
    if not local:
        print("No user-defined modules (config/module-manifest.local.json is empty or missing).")
        return 0
    upstream_keys = {m["key"] for m in upstream}
    env = load_env_file(paths.env)
    rows = [("KEY", "KIND", "ENABLED", "REPO")]
    for item in local:
        key = item["key"]
        if key in upstream_keys:
            kind = "override"
        elif is_tombstone(item):
            kind = "removed"
        elif item.get("name") and item.get("repo"):
            kind = "local"
        else:
            kind = "orphaned"
        enabled = "yes" if parse_bool(env.get(key, "0")) else "no"
        repo = item.get("repo", "(upstream repo)")
        if item.get("ref"):
            repo = f"{repo}@{item['ref']}"
        rows.append((key, kind, enabled, repo))
    widths = [max(len(r[i]) for r in rows) for i in range(3)]
    for row in rows:
        print("  ".join(cell.ljust(widths[i]) if i < 3 else cell for i, cell in enumerate(row)))
    return 0


def cmd_remove(args: argparse.Namespace, paths: Paths) -> int:
    upstream, local, _merged = _load(paths)
    key = args.key
    item = next((e for e in local if e["key"] == key), None)
    if item is None:
        raise Refused(f"{key} has no entry in {paths.local.name}; ./modules.sh list shows the local entries")
    upstream_keys = {m["key"] for m in upstream}
    if key not in upstream_keys and is_tombstone(item):
        raise Refused(f"{key} is already removed; its disabled marker stays in {paths.local.name} "
                      f"so the next deploy cleans it up")
    if key in upstream_keys:
        write_local_entries(paths.local, [e for e in local if e["key"] != key])
        print(f"✅ Removed the local override for {key}; it goes back to its upstream repo/ref "
              f"on the next deploy. {key} in .env is unchanged.")
    elif item.get("name") and item.get("repo"):
        write_local_entries(paths.local, [tombstone_for(item) if e["key"] == key else e for e in local])
        set_env_value(paths.env, key, "0")
        print(f"✅ Removed {key} and set {key}=0 in .env. The next deploy removes its checkout "
              f"and staged Lua and stops staging its SQL.")
        print(f"   The removed entry stays in {paths.local.name} as a disabled marker "
              f"(shown by ./modules.sh list) so that deploy knows to clean it up.")
    else:
        # An orphaned override: nothing was installed from it.
        write_local_entries(paths.local, [e for e in local if e["key"] != key])
        set_env_value(paths.env, key, "0")
        print(f"✅ Removed {key} and set {key}=0 in .env.")
    print("   SQL the module already applied stays in the database.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="modules.sh", description="Manage user-defined modules")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="command", required=True)

    add = sub.add_parser("add", help="Add a module from a git URL, or pin/fork a listed one")
    add.add_argument("url", nargs="?", help="git URL (omit with --key and --ref to pin a listed module)")
    add.add_argument("--ref", help="branch, tag or commit to check out")
    add.add_argument("--type", choices=["cpp", "lua", "sql"], help="skip detection")
    add.add_argument("--key", help="MODULE_* key (to override a listed module, or on a key collision)")
    add.add_argument("--no-enable", action="store_true", help="don't set MODULE_*=1 in .env")
    add.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    add.set_defaults(func=cmd_add)

    lst = sub.add_parser("list", help="Show user-defined modules and overrides")
    lst.set_defaults(func=cmd_list)

    rm = sub.add_parser("remove", help="Remove a user-defined module or override")
    rm.add_argument("key", help="MODULE_* key")
    rm.set_defaults(func=cmd_remove)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    paths = Paths(Path(args.root))
    try:
        return args.func(args, paths)
    except Refused as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

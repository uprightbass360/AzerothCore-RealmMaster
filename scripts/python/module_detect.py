#!/usr/bin/env python3
"""
Work out how RealmMaster should install a checked-out module.

Mirrors what the pipeline does with each type (see docs/ADDING_MODULES.md):
C++ is compiled (AzerothCore calls Add<folder>Scripts(), '-' -> '_'), Lua is
staged by a post-install hook, and SQL in data/sql/<db> folders is applied.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional

COLLECTION_FILE_THRESHOLD = 20
COLLECTION_DIR_THRESHOLD = 3

# Folders stage-modules.sh reads SQL from, relative to data/sql/.
_SQL_DIRS = {
    f"{db}{suffix}"
    for db in ("db-world", "db-characters", "db-auth", "db-playerbots")
    for suffix in ("", "/base", "/updates")
} | {f"{db}{suffix}" for db in ("world", "characters", "auth") for suffix in ("", "/base")}

# Flat locations copy-standard-lua reads.
_STANDARD_LUA_DIRS = {".", "lua_scripts", "scripts", "Server Files/lua_scripts"}

_LOADER_RE = re.compile(r"void\s+(Add\w+Scripts)\s*\(")
_REQUIRE_RE = re.compile(r"""require\s*\(?\s*["']([\w./-]+)["']""")
_AIO_RE = re.compile(r"""require\s*\(?\s*["']AIO["']|\bAIO\.""")


@dataclass
class Detection:
    module_type: Optional[str]
    post_install_hooks: List[str] = field(default_factory=list)
    requires: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    is_collection: bool = False
    reason: str = ""


def _files(root: Path, pattern: str) -> Iterator[Path]:
    for path in root.rglob(pattern):
        if ".git" in path.relative_to(root).parts:
            continue
        if path.is_file():
            yield path


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _stray_sql_warnings(root: Path) -> List[str]:
    warnings = []
    for sql in _files(root, "*.sql"):
        rel = sql.relative_to(root)
        parts = rel.parts
        parent = "/".join(parts[2:-1]) if parts[:2] == ("data", "sql") else None
        if parent not in _SQL_DIRS:
            warnings.append(f"{rel.as_posix()} is outside data/sql/<db>/ and will not be imported")
    return warnings


def _detect_cpp(root: Path, folder_name: str) -> Detection:
    detection = Detection("cpp")
    sources = list(_files(root / "src", "*.cpp")) + list(_files(root / "src", "*.h"))
    text = "\n".join(_read(p) for p in sources)
    expected = f"Add{folder_name.replace('-', '_')}Scripts"
    found = sorted(set(_LOADER_RE.findall(text)))
    if expected not in found:
        detection.warnings.append(
            f"AzerothCore will call {expected}() for folder '{folder_name}', "
            f"but src/ defines {', '.join(found) if found else 'no Add...Scripts() function'}; "
            "the build may fail to link"
        )
    if "Playerbots.h" in text or "PlayerbotAI" in text:
        detection.requires.append("MODULE_PLAYERBOTS")
    detection.warnings.extend(_stray_sql_warnings(root))
    return detection


def _detect_lua(root: Path, lua_files: List[Path]) -> Detection:
    detection = Detection("lua")
    rels = [p.relative_to(root) for p in lua_files]
    top_dirs = {r.parts[0] for r in rels if len(r.parts) > 1}
    if len(rels) > COLLECTION_FILE_THRESHOLD or len(top_dirs) >= COLLECTION_DIR_THRESHOLD:
        detection.is_collection = True
    text = "\n".join(_read(p) for p in lua_files)

    if _AIO_RE.search(text):
        detection.post_install_hooks = ["copy-aio-lua"]
        detection.requires = ["MODULE_AIO"]
        return detection

    detection.requires = ["MODULE_ELUNA"]
    in_standard = {r for r in rels if (r.parent.as_posix() or ".") in _STANDARD_LUA_DIRS}
    standard_names = {r.stem for r in in_standard}
    all_names = {r.stem for r in rels}
    required = {name.replace(".", "/").split("/")[-1] for name in _REQUIRE_RE.findall(text)}
    needs_subfolder = any(name in all_names and name not in standard_names for name in required)
    if not in_standard or needs_subfolder:
        detection.post_install_hooks = ["copy-lua-tree"]
    else:
        detection.post_install_hooks = ["copy-standard-lua"]
    return detection


def detect(module_dir: Path, folder_name: str) -> Detection:
    root = Path(module_dir)
    src = root / "src"
    if src.is_dir() and (any(_files(src, "*.cpp")) or any(_files(src, "*.h"))):
        return _detect_cpp(root, folder_name)

    lua_files = list(_files(root, "*.lua"))
    if lua_files:
        return _detect_lua(root, lua_files)

    sql_dir = root / "data" / "sql"
    if sql_dir.is_dir() and any(_files(sql_dir, "*.sql")):
        detection = Detection("sql")
        detection.warnings.extend(_stray_sql_warnings(root))
        return detection

    return Detection(None, reason="no src/ with C++, no .lua files and no data/sql/*.sql; "
                                  "this looks like a tool or client patch")

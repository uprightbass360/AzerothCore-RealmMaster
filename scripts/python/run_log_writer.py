#!/usr/bin/env python3
"""Append a run's output to its log file: strip ANSI codes, mask secrets.

Reads stdin until EOF (every writer of the pipe has closed it) and appends
each line to the log file. Used by scripts/bash/lib/run-log.sh; see
docs/superpowers/specs/2026-10-05-script-logging-design.md.

Secrets are the values of .env variables whose name contains PASSWORD,
TOKEN, SECRET or KEY (case-insensitive) and that are at least 4 characters
long; they are replaced with *** wherever they appear. The .env is read again
at EOF: secrets that first appeared during the run (setup.sh writes a new
.env) are then masked in the whole file, which is rewritten in place.
"""
from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[ -/]*[0-~]")
SECRET_NAME_RE = re.compile(r"PASSWORD|TOKEN|SECRET|KEY", re.IGNORECASE)
MIN_SECRET_LEN = 4
INLINE_COMMENT_RE = re.compile(r"\s+#.*$")


def load_secrets(env_path: Path) -> list[str]:
    """Secret values from a .env file, longest first (so longer values win)."""
    secrets: set[str] = set()
    try:
        lines = env_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = name.strip()
        if name.startswith("export "):
            name = name[len("export "):].strip()
        if not SECRET_NAME_RE.search(name):
            continue
        value = value.strip()
        if value[:1] in ("'", '"') and value.find(value[0], 1) != -1:
            # Quoted: everything inside the quotes, nothing after them.
            value = value[1:value.find(value[0], 1)]
        else:
            # Unquoted: " # ..." starts a comment.
            value = INLINE_COMMENT_RE.sub("", value)
        if len(value) < MIN_SECRET_LEN or "${" in value:
            continue
        secrets.add(value)
    return sorted(secrets, key=len, reverse=True)


def clean_line(line: str, secrets: list[str]) -> str:
    """One output line as it should appear in the log file."""
    line = line.rstrip("\n")
    # A terminal redraws a line on \r (progress meters); keep what it ends on.
    if "\r" in line:
        parts = [p for p in line.split("\r") if p]
        line = parts[-1] if parts else ""
    line = ANSI_RE.sub("", line)
    for secret in secrets:
        line = line.replace(secret, "***")
    return line


def remask_file(log_path: Path, secrets: list[str]) -> None:
    """Mask SECRETS in every line of the log, replacing the file atomically.

    The new file keeps the old one's mode and (when allowed) owner. Raises
    OSError on failure; the original file is then left as it was.
    """
    st = os.stat(log_path)
    fd, tmp = tempfile.mkstemp(prefix=".run-log-", dir=str(log_path.parent))
    try:
        with open(fd, "w", encoding="utf-8", newline="\n") as out, \
                open(log_path, "r", encoding="utf-8", errors="replace", newline="\n") as src:
            for line in src:
                masked = line
                for secret in secrets:
                    masked = masked.replace(secret, "***")
                out.write(masked)
        os.chmod(tmp, st.st_mode & 0o7777)
        try:
            os.chown(tmp, st.st_uid, st.st_gid)
        except OSError:
            pass  # not root: the file is ours already
        os.replace(tmp, log_path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: run_log_writer.py <log-file> <env-file>", file=sys.stderr)
        return 2
    log_path, env_path = Path(argv[1]), Path(argv[2])
    secrets = load_secrets(env_path)
    stdin = open(sys.stdin.fileno(), "r", encoding="utf-8", errors="replace", newline="\n", closefd=False)
    out = None
    write_enabled = True
    try:
        out = open(log_path, "a", encoding="utf-8")
    except OSError as e:
        print(f"run_log_writer: cannot write {log_path}: {e}; continuing without the log", file=sys.stderr)
        write_enabled = False

    try:
        for raw in stdin:
            if write_enabled:
                try:
                    out.write(clean_line(raw, secrets) + "\n")
                    out.flush()
                except OSError as e:
                    print(f"run_log_writer: cannot write {log_path}: {e}; continuing without the log", file=sys.stderr)
                    write_enabled = False
    finally:
        if out is not None:
            out.close()

    if write_enabled:
        new_secrets = [s for s in load_secrets(env_path) if s not in secrets]
        if new_secrets:
            # Mask the old secrets too: a new secret may contain an old one.
            all_secrets = sorted(set(secrets) | set(new_secrets), key=len, reverse=True)
            try:
                remask_file(log_path, all_secrets)
            except OSError as e:
                print(f"run_log_writer: cannot mask new .env secrets in {log_path}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Propose stale catalogue entries for removal.

Reads config/module-manifest.json and config/module-sources.json. An entry is
a candidate when it is hosted on github.com, is not declined or kept, is not
referenced by a curated profile, and either its ``last_modified`` is older
than ``policy.stale_after_days`` or (with --check-archived) GitHub reports the
repository archived. Candidates are written into the ``declined`` section
with a reason, and a Markdown table of them is printed to stdout. Nothing is
printed when there are no candidates.

This script never touches the manifest. Run
``update_module_manifest.py --sources-only`` afterwards to apply the removals.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import date
from typing import List, Optional, Sequence, Set, Tuple
from urllib import request  # noqa: F401  (patched by tests to assert no network use)

from module_sources import DEFAULT_SOURCES_PATH, Sources, load_sources, profile_keys, save_sources
from update_module_manifest import GitHubClient, github_full_name, load_manifest

REASON_INACTIVE = "no upstream activity since {date}"
REASON_ARCHIVED = "archived upstream"

Candidate = Tuple[dict, str, str]  # (manifest entry, owner/repo, reason)


def parse_last_modified(value: object) -> Optional[date]:
    """Date part of an ISO timestamp, or None when missing or malformed."""
    if not isinstance(value, str):
        return None
    text = value.strip()
    if len(text) < 10:
        return None
    try:
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def find_stale_candidates(
    manifest: dict,
    sources: Sources,
    exempt_keys: Set[str],
    today: date,
    client: Optional[GitHubClient] = None,
) -> List[Candidate]:
    cutoff = sources.stale_cutoff(today)
    found: List[Candidate] = []
    for entry in manifest.get("modules", []):
        full_name = github_full_name(str(entry.get("repo", "")))
        if not full_name:
            continue
        if str(entry.get("key")) in exempt_keys:
            continue
        if sources.is_declined(full_name) or sources.is_kept(full_name):
            continue
        last = parse_last_modified(entry.get("last_modified"))
        if last is not None and last < cutoff:
            found.append((entry, full_name, REASON_INACTIVE.format(date=last.isoformat())))
            continue
        if client is not None:
            verdict, repo = client.check_repo(full_name)
            time.sleep(0.1)  # avoid secondary rate limits on long lists
            if verdict == "alive" and repo and repo.get("archived"):
                found.append((entry, full_name, REASON_ARCHIVED))
    return found


def format_table(candidates: Sequence[Candidate]) -> str:
    lines = ["| Key | Repository | Last push | Reason |", "|---|---|---|---|"]
    for entry, full_name, reason in candidates:
        last = parse_last_modified(entry.get("last_modified"))
        last_text = last.isoformat() if last else "unknown"
        lines.append(
            f"| `{entry.get('key')}` | [{full_name}](https://github.com/{full_name}) | {last_text} | {reason} |"
        )
    return "\n".join(lines) + "\n"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--manifest", default="config/module-manifest.json")
    parser.add_argument("--sources", default=DEFAULT_SOURCES_PATH)
    parser.add_argument("--profiles-dir", default="config/module-profiles")
    parser.add_argument("--today", default=None, help="ISO date to evaluate against (default: today)")
    parser.add_argument("--check-archived", action="store_true",
                        help="Also ask the GitHub API whether non-stale repos are archived")
    parser.add_argument("--token", default=None, help="GitHub token (default: $GITHUB_TOKEN)")
    parser.add_argument("--dry-run", action="store_true", help="Print the table without writing --sources")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    today = date.fromisoformat(args.today) if args.today else date.today()
    manifest = load_manifest(args.manifest)
    sources = load_sources(args.sources)
    exempt = profile_keys(args.profiles_dir, sources.ignore_profiles)

    client: Optional[GitHubClient] = None
    if args.check_archived:
        token = args.token or os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_API_TOKEN")
        client = GitHubClient(token)

    candidates = find_stale_candidates(manifest, sources, exempt, today, client)
    note = ""
    if client is not None and client.error_count:
        note = f"{client.error_count} GitHub API error(s); archived detection is incomplete"
        # GitHub Actions turns this into a run annotation even when stdout is redirected.
        print(f"::warning::{note}", file=sys.stderr)
    if not candidates:
        return 0

    for _entry, full_name, reason in candidates:
        sources.decline(full_name, reason, today)
    if not args.dry_run:
        save_sources(sources, args.sources)
    sys.stdout.write(format_table(candidates))
    if note:
        # Travels with the table into the PR body so the reviewer sees it.
        sys.stdout.write(f"\n> **Warning:** {note}.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

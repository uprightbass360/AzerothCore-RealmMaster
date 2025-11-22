#!/usr/bin/env python3
"""Generate a categorized list of GitHub modules missing from the manifest.

The script reuses the discovery logic from ``update_module_manifest.py`` to
fetch repositories by topic, filters out entries already tracked in
``config/module-manifest.json`` and writes the remainder (including type,
category, and inferred dependency hints) to a JSON file.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

from update_module_manifest import (  # type: ignore
    CATEGORY_BY_TYPE,
    DEFAULT_TOPICS,
    GitHubClient,
    collect_repositories,
    load_manifest,
    normalize_repo_url,
    repo_name_to_key,
)

# heuristics used to surface potential dependency hints
DEPENDENCY_KEYWORDS: Tuple[Tuple[str, str], ...] = (
    ("playerbot", "MODULE_PLAYERBOTS"),
    ("ah-bot", "MODULE_PLAYERBOTS"),
    ("eluna", "MODULE_ELUNA"),
)

# keywords that help categorize entries that should probably stay hidden by default
SUPPRESSION_KEYWORDS: Tuple[Tuple[str, str], ...] = (
    ("virtual machine", "vm"),
    (" vm ", "vm"),
    (" docker", "docker"),
    ("container", "docker"),
    ("vagrant", "vagrant"),
    ("ansible", "automation"),
    ("terraform", "automation"),
    ("client", "client-distribution"),
    ("launcher", "client-distribution"),
)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="config/module-manifest.json",
        help="Path to module manifest JSON (default: %(default)s)",
    )
    parser.add_argument(
        "--output",
        default="missing-modules.json",
        help="Path to write the missing-module report JSON (default: %(default)s)",
    )
    parser.add_argument(
        "--topic",
        action="append",
        default=[],
        dest="topics",
        help="GitHub topic (or '+' expression) to scan (defaults to built-in list).",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=10,
        help="Maximum pages (x100 results) to fetch per topic (default: %(default)s)",
    )
    parser.add_argument(
        "--token",
        help="GitHub API token (defaults to $GITHUB_TOKEN or $GITHUB_API_TOKEN)",
    )
    parser.add_argument(
        "--log",
        action="store_true",
        help="Print verbose progress information",
    )
    return parser.parse_args(argv)


def implied_dependencies(module_type: str, text: str) -> List[str]:
    deps: List[str] = []
    if module_type == "lua":
        deps.append("MODULE_ELUNA")
    normalized = text.lower()
    for keyword, dep in DEPENDENCY_KEYWORDS:
        if keyword in normalized and dep not in deps:
            deps.append(dep)
    return deps


def suppression_flags(category: str, text: str) -> List[str]:
    flags: List[str] = []
    if category == "tooling":
        flags.append("tooling")
    normalized = text.lower()
    for keyword, flag in SUPPRESSION_KEYWORDS:
        if keyword in normalized and flag not in flags:
            flags.append(flag)
    return flags


def make_missing_entries(
    manifest_modules: List[dict],
    repos: Iterable,
) -> List[dict]:
    by_key: Dict[str, dict] = {module.get("key"): module for module in manifest_modules if module.get("key")}
    by_repo: Dict[str, dict] = {
        normalize_repo_url(str(module.get("repo", ""))): module
        for module in manifest_modules
        if module.get("repo")
    }
    missing: List[dict] = []

    for record in repos:
        repo = record.data
        repo_url = normalize_repo_url(repo.get("clone_url") or repo.get("html_url") or "")
        existing = by_repo.get(repo_url)
        key = repo_name_to_key(repo.get("name", ""))
        if not existing:
            existing = by_key.get(key)
        if existing:
            continue
        module_type = record.module_type
        category = CATEGORY_BY_TYPE.get(module_type, "uncategorized")
        description = repo.get("description") or ""
        combined_text = " ".join(
            filter(
                None,
                [
                    repo.get("full_name"),
                    description,
                    " ".join(repo.get("topics") or []),
                ],
            )
        )
        entry = {
            "key": key,
            "repo_name": repo.get("full_name"),
            "topic": record.topic_expr,
            "repo_url": repo.get("html_url") or repo.get("clone_url"),
            "description": description,
            "topics": repo.get("topics") or [],
            "type": module_type,
            "category": category,
            "implied_dependencies": implied_dependencies(module_type, combined_text),
            "flags": suppression_flags(category, combined_text),
        }
        missing.append(entry)
    missing.sort(key=lambda item: item["key"])
    return missing


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    topics = args.topics or DEFAULT_TOPICS
    token = args.token or os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_API_TOKEN")
    if not token:
        print(
            "Warning: no GitHub token provided, falling back to anonymous rate limit",
            file=sys.stderr,
        )
    client = GitHubClient(token, verbose=args.log)

    manifest = load_manifest(args.manifest)
    repos = collect_repositories(client, topics, args.max_pages)
    missing = make_missing_entries(manifest.get("modules", []), repos)

    output_path = Path(args.output)
    output_path.write_text(json.dumps(missing, indent=2))
    print(f"Wrote {len(missing)} entries to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

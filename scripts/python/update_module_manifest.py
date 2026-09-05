#!/usr/bin/env python3
"""Generate or update config/module-manifest.json from GitHub topics.

The script queries the GitHub Search API for repositories tagged with
AzerothCore-specific topics (for example ``azerothcore-module`` or
``azerothcore-lua``) and merges the discovered projects into the existing
module manifest.  It intentionally keeps all user-defined fields intact so the
script can be run safely in CI or locally to add new repositories as they are
published.

With ``--prune-missing`` it also removes entries whose upstream repository has
been deleted.  Absence from the search results is never sufficient on its own --
a maintainer removing the topic drops a live repo from those results too -- so
each candidate is confirmed with a direct ``GET /repos/{owner}/{name}`` and only
a hard 404/451 is treated as dead.  Pruning is abandoned entirely if any API
error occurred during the run or if the number of dead entries exceeds
``--prune-max-fraction`` of the manifest.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence
from urllib import error, parse, request

API_ROOT = "https://api.github.com"
DEFAULT_TOPICS = [
    "azerothcore-module",
    "azerothcore-module+ac-premium",
    "azerothcore-tools",
    "azerothcore-lua",
    "azerothcore-sql",
]
# Map topic keywords to module ``type`` values used in the manifest.
TOPIC_TYPE_HINTS = {
    "azerothcore-lua": "lua",
    "lua": "lua",
    "azerothcore-sql": "sql",
    "sql": "sql",
    "azerothcore-tools": "tool",
    "tools": "tool",
}
CATEGORY_BY_TYPE = {
    "lua": "scripting",
    "sql": "database",
    "tool": "tooling",
    "data": "data",
    "cpp": "uncategorized",
}
USER_AGENT = "azerothcore-realmmaster-module-manifest"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="config/module-manifest.json",
        help="Path to manifest JSON file (default: %(default)s)",
    )
    parser.add_argument(
        "--topic",
        action="append",
        default=[],
        dest="topics",
        help="GitHub topic (or '+' separated topics) to scan. Defaults to core topics if not provided.",
    )
    parser.add_argument(
        "--token",
        help="GitHub API token (defaults to $GITHUB_TOKEN or $GITHUB_API_TOKEN)",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=10,
        help="Maximum pages (x100 results) to fetch per topic (default: %(default)s)",
    )
    parser.add_argument(
        "--refresh-existing",
        action="store_true",
        help="Refresh name/description/type for repos already present in manifest",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch and display the summary without writing to disk",
    )
    parser.add_argument(
        "--log",
        action="store_true",
        help="Print verbose progress information",
    )
    parser.add_argument(
        "--update-template",
        default=".env.template",
        help="Update .env.template with missing module variables (default: %(default)s)",
    )
    parser.add_argument(
        "--skip-template",
        action="store_true",
        help="Skip updating .env.template",
    )
    parser.add_argument(
        "--prune-missing",
        action="store_true",
        help="Remove manifest entries whose GitHub repository no longer exists (404/451)",
    )
    parser.add_argument(
        "--prune-max-fraction",
        type=float,
        default=0.10,
        help=(
            "Abort pruning if the confirmed-dead entries exceed this fraction of the "
            "manifest (default: %(default)s)"
        ),
    )
    return parser.parse_args(argv)


@dataclass
class RepoRecord:
    data: dict
    topic_expr: str
    module_type: str


class GitHubClient:
    def __init__(self, token: Optional[str], verbose: bool = False) -> None:
        self.token = token
        self.verbose = verbose
        # Incremented whenever an API call fails for a reason that is *not* a
        # definitive answer about a repository's existence (rate limits, 5xx,
        # network faults).  Pruning refuses to run when this is non-zero so a
        # partial view of GitHub can never delete live entries.
        self.error_count = 0

    def check_repo(self, full_name: str) -> str:
        """Return 'alive', 'dead' or 'error' for ``owner/name``.

        Only an unambiguous 404 (gone) or 451 (DMCA takedown) counts as dead.
        Anything else -- including rate limiting and transient server errors --
        is reported as an error so the caller can bail out instead of guessing.
        """
        url = f"{API_ROOT}/repos/{full_name}"
        req = request.Request(url)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("User-Agent", USER_AGENT)
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with request.urlopen(req):
                # Redirects (renamed repos) are followed transparently and land
                # here as 200 -- the project still exists, so keep it.
                return "alive"
        except error.HTTPError as exc:
            if exc.code in (404, 451):
                return "dead"
            self.error_count += 1
            if self.verbose:
                print(f"  ! {full_name}: HTTP {exc.code} {exc.reason}")
            return "error"
        except Exception as exc:  # network failure, DNS, timeout
            self.error_count += 1
            if self.verbose:
                print(f"  ! {full_name}: {exc}")
            return "error"

    def _request(self, url: str) -> dict:
        req = request.Request(url)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("User-Agent", USER_AGENT)
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with request.urlopen(req) as resp:
                payload = resp.read().decode("utf-8")
                return json.loads(payload)
        except error.HTTPError as exc:  # pragma: no cover - network failure path
            detail = exc.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"GitHub API request failed: {exc.code} {exc.reason}: {detail}") from exc

    def search_repositories(self, topic_expr: str, max_pages: int) -> List[dict]:
        query = build_topic_query(topic_expr)
        results: List[dict] = []
        for page in range(1, max_pages + 1):
            url = (
                f"{API_ROOT}/search/repositories?"
                f"q={parse.quote(query)}&per_page=100&page={page}&sort=updated&order=desc"
            )
            try:
                data = self._request(url)
            except RuntimeError as exc:
                # A partial result set is the dangerous case for pruning: the
                # repos we never saw would look "missing".  Record it and stop
                # paging this topic rather than pretending the list is whole.
                self.error_count += 1
                print(f"Warning: search for '{topic_expr}' failed on page {page}: {exc}")
                break
            items = data.get("items", [])
            if self.verbose:
                print(f"Fetched {len(items)} repos for '{topic_expr}' (page {page})")
            results.extend(items)
            if len(items) < 100:
                break
            # Avoid secondary rate-limits.
            time.sleep(0.5)
        return results


def build_topic_query(expr: str) -> str:
    """Build a search query for one '+'-separated topic expression.

    ``fork:true`` is essential rather than cosmetic: GitHub's search API omits
    forks by default, and the upstream ``azerothcore`` org maintains many of its
    modules as forks of the original community repos.  Without it, correctly
    tagged modules such as mod-solocraft and mod-solo-lfg never appear in the
    results at all.
    """
    parts = [part.strip() for part in expr.split("+") if part.strip()]
    if not parts:
        raise ValueError("Topic expression must contain at least one topic")
    # Qualifiers are joined with spaces, not '+': the caller percent-encodes the
    # query, and a literal '+' becomes %2B (a plus *character*) rather than a
    # separator, which GitHub then parses as one malformed term matching nothing.
    return " ".join(f"topic:{part}" for part in parts) + " fork:true"


def guess_module_type(expr: str) -> str:
    parts = [part.strip().lower() for part in expr.split("+") if part.strip()]
    for part in parts:
        hint = TOPIC_TYPE_HINTS.get(part)
        if hint:
            return hint
    return "cpp"


def normalize_repo_url(url: str) -> str:
    if url.endswith(".git"):
        return url[:-4]
    return url


def github_full_name(url: str) -> Optional[str]:
    """Extract ``owner/name`` from a github.com URL, or None if not GitHub.

    Entries pointing at other hosts (or with malformed URLs) return None and are
    never pruned -- we have no way to verify them via the GitHub API.
    """
    if not url:
        return None
    parsed = parse.urlparse(normalize_repo_url(url.strip()))
    host = parsed.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    if host not in ("github.com", "api.github.com"):
        return None
    parts = [segment for segment in parsed.path.split("/") if segment]
    if len(parts) < 2:
        return None
    return f"{parts[0]}/{parts[1]}"


def prune_missing_repositories(
    manifest: Dict[str, List[dict]],
    client: GitHubClient,
    seen_repo_urls: set,
    max_fraction: float,
    dry_run: bool = False,
    verbose: bool = False,
) -> List[dict]:
    """Delete manifest entries whose GitHub repository is gone.

    Only entries absent from this run's search results are checked, and only a
    definitive 404/451 from ``GET /repos/{owner}/{name}`` marks one for removal.
    Pruning is abandoned wholesale if any API error occurred (an incomplete view
    of GitHub must never delete anything) or if the number of dead entries
    exceeds ``max_fraction`` of the manifest.

    Returns the list of removed entries (empty if nothing was pruned).
    """
    modules = manifest.setdefault("modules", [])
    total = len(modules)
    if not total:
        return []

    candidates = []
    for entry in modules:
        repo_url = normalize_repo_url(str(entry.get("repo", "")))
        if not repo_url or repo_url in seen_repo_urls:
            continue
        full_name = github_full_name(repo_url)
        if not full_name:
            if verbose:
                print(f"  ~ skipping non-GitHub repo: {entry.get('key')} ({repo_url})")
            continue
        candidates.append((entry, full_name))

    if not candidates:
        print("✅ No manifest entries missing from search results; nothing to prune")
        return []

    print(f"🔍 Verifying {len(candidates)} manifest entr(ies) absent from search results...")
    dead: List[dict] = []
    for entry, full_name in candidates:
        verdict = client.check_repo(full_name)
        if verdict == "dead":
            dead.append(entry)
            print(f"   🗑️  {entry.get('key')} ({full_name}) — repository not found")
        elif verdict == "alive" and verbose:
            print(f"   ✓ {entry.get('key')} ({full_name}) — still exists, keeping")
        # Avoid secondary rate-limits on long candidate lists.
        time.sleep(0.1)

    if client.error_count:
        print(
            f"⚠️  Skipping prune: {client.error_count} GitHub API error(s) during this run. "
            "Refusing to delete entries based on an incomplete view."
        )
        return []

    if not dead:
        print("✅ All absent entries still exist upstream; nothing to prune")
        return []

    fraction = len(dead) / total
    if fraction > max_fraction:
        print(
            f"⚠️  Skipping prune: {len(dead)}/{total} entries ({fraction:.1%}) exceed the "
            f"--prune-max-fraction limit of {max_fraction:.1%}. Review the list above manually."
        )
        return []

    if dry_run:
        print(f"[dry-run] Would remove {len(dead)} entr(ies) from the manifest")
        return dead

    dead_ids = {id(entry) for entry in dead}
    manifest["modules"] = [entry for entry in modules if id(entry) not in dead_ids]
    print(f"🗑️  Removed {len(dead)} dead entr(ies) from the manifest")
    return dead


def repo_name_to_key(name: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")
    sanitized = sanitized.upper()
    if not sanitized:
        sanitized = "MODULE_UNKNOWN"
    if not sanitized.startswith("MODULE_"):
        sanitized = f"MODULE_{sanitized}"
    return sanitized


def load_manifest(path: str) -> Dict[str, List[dict]]:
    manifest_path = os.path.abspath(path)
    if not os.path.exists(manifest_path):
        return {"modules": []}
    try:
        with open(manifest_path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Unable to parse manifest {path}: {exc}") from exc


def ensure_defaults(entry: dict) -> None:
    entry.setdefault("type", "cpp")
    entry.setdefault("status", "active")
    entry.setdefault("order", 5000)
    entry.setdefault("requires", [])
    entry.setdefault("post_install_hooks", [])
    entry.setdefault("config_cleanup", [])


def update_entry_from_repo(entry: dict, repo: dict, repo_type: str, topic_expr: str, refresh: bool) -> None:
    # Only overwrite descriptive fields when refresh is enabled or when they are missing.
    if refresh or not entry.get("name"):
        entry["name"] = repo.get("name") or entry.get("name")
    if refresh or not entry.get("repo"):
        entry["repo"] = repo.get("clone_url") or repo.get("html_url", entry.get("repo"))
    if refresh or not entry.get("description"):
        entry["description"] = repo.get("description") or entry.get("description", "")
    if refresh or not entry.get("type"):
        entry["type"] = repo_type
    if refresh or not entry.get("category"):
        entry["category"] = CATEGORY_BY_TYPE.get(repo_type, entry.get("category", "uncategorized"))
    ensure_defaults(entry)
    notes = entry.get("notes") or ""
    tag_note = f"Discovered via GitHub topic '{topic_expr}'"
    if tag_note not in notes:
        entry["notes"] = (notes + " \n" + tag_note).strip()


def merge_repositories(
    manifest: Dict[str, List[dict]],
    repos: Iterable[RepoRecord],
    refresh_existing: bool,
) -> tuple[int, int]:
    modules = manifest.setdefault("modules", [])
    by_key = {module.get("key"): module for module in modules if module.get("key")}
    by_repo = {
        normalize_repo_url(str(module.get("repo", ""))): module
        for module in modules
        if module.get("repo")
    }
    added = 0
    updated = 0

    for record in repos:
        repo = record.data
        repo_url = normalize_repo_url(repo.get("clone_url") or repo.get("html_url") or "")
        existing = by_repo.get(repo_url)
        key = repo_name_to_key(repo.get("name", ""))
        if not existing:
            existing = by_key.get(key)
        if not existing:
            existing = {
                "key": key,
                "name": repo.get("name", key),
                "repo": repo.get("clone_url") or repo.get("html_url", ""),
                "description": repo.get("description") or "",
                "type": record.module_type,
                "category": CATEGORY_BY_TYPE.get(record.module_type, "uncategorized"),
                "notes": "",
            }
            ensure_defaults(existing)
            modules.append(existing)
            by_key[key] = existing
            if repo_url:
                by_repo[repo_url] = existing
            added += 1
        else:
            updated += 1
        update_entry_from_repo(existing, repo, record.module_type, record.topic_expr, refresh_existing)

    return added, updated


def collect_repositories(
    client: GitHubClient, topics: Sequence[str], max_pages: int
) -> List[RepoRecord]:
    seen: Dict[str, RepoRecord] = {}
    for expr in topics:
        repos = client.search_repositories(expr, max_pages)
        repo_type = guess_module_type(expr)
        for repo in repos:
            full_name = repo.get("full_name")
            if not full_name:
                continue
            record = seen.get(full_name)
            if record is None:
                seen[full_name] = RepoRecord(repo, expr, repo_type)
            else:
                # Prefer the most specific type (non-default) if available.
                if record.module_type == "cpp" and repo_type != "cpp":
                    record.module_type = repo_type
    return list(seen.values())


def update_env_template(manifest_path: str, template_path: str) -> bool:
    """Update .env.template with module variables for active modules only.

    Args:
        manifest_path: Path to the module manifest JSON file
        template_path: Path to .env.template file

    Returns:
        True if template was updated, False if no changes needed
    """
    # Load manifest to get all module keys
    manifest = load_manifest(manifest_path)
    modules = manifest.get("modules", [])
    if not modules:
        return False

    # Extract only active module keys
    active_module_keys = set()
    disabled_module_keys = set()
    for module in modules:
        key = module.get("key")
        status = module.get("status", "active")
        if key:
            if status == "active":
                active_module_keys.add(key)
            else:
                disabled_module_keys.add(key)

    if not active_module_keys and not disabled_module_keys:
        return False

    # Check if template file exists
    template_file = Path(template_path)
    if not template_file.exists():
        print(f"Warning: .env.template not found at {template_path}")
        return False

    # Read current template content
    try:
        current_content = template_file.read_text(encoding="utf-8")
        current_lines = current_content.splitlines()
    except Exception as exc:
        print(f"Error reading .env.template: {exc}")
        return False

    # Find which module variables are currently in the template
    existing_vars = set()
    current_module_lines = []
    non_module_lines = []

    for line in current_lines:
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#"):
            var_name = stripped.split("=", 1)[0].strip()
            if var_name.startswith("MODULE_"):
                existing_vars.add(var_name)
                current_module_lines.append((var_name, line))
            else:
                non_module_lines.append(line)
        else:
            non_module_lines.append(line)

    # Determine what needs to change
    missing_vars = active_module_keys - existing_vars
    # Any MODULE_* var that is not backed by an active manifest entry goes: that
    # covers both disabled modules and modules pruned out of the manifest
    # entirely (e.g. because the upstream repo was deleted).
    vars_to_remove = existing_vars - active_module_keys
    vars_to_keep = active_module_keys & existing_vars

    changes_made = False

    # Report what will be done
    if missing_vars:
        print(f"📝 Adding {len(missing_vars)} active module variable(s) to .env.template:")
        for var in sorted(missing_vars):
            print(f"   + {var}=0")
        changes_made = True

    if vars_to_remove:
        print(f"🗑️  Removing {len(vars_to_remove)} stale module variable(s) from .env.template:")
        for var in sorted(vars_to_remove):
            print(f"   - {var}")
        changes_made = True

    if not changes_made:
        print("✅ .env.template is up to date with active modules")
        return False

    # Build new content: non-module lines + active module lines
    new_lines = non_module_lines[:]

    # Add existing active module variables (preserve their current values)
    for var_name, original_line in current_module_lines:
        if var_name in vars_to_keep:
            new_lines.append(original_line)

    # Add new active module variables
    for var in sorted(missing_vars):
        new_lines.append(f"{var}=0")

    # Write updated content
    try:
        new_content = "\n".join(new_lines) + "\n"
        template_file.write_text(new_content, encoding="utf-8")
        print("✅ .env.template updated successfully")
        print(f"   Active modules: {len(active_module_keys)}")
        print(f"   Stale variables removed: {len(vars_to_remove)}")
        return True
    except Exception as exc:
        print(f"Error writing .env.template: {exc}")
        return False


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    topics = args.topics or DEFAULT_TOPICS
    token = args.token or os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_API_TOKEN")
    client = GitHubClient(token, verbose=args.log)

    manifest = load_manifest(args.manifest)
    repos = collect_repositories(client, topics, args.max_pages)
    added, updated = merge_repositories(manifest, repos, args.refresh_existing)

    removed: List[dict] = []
    if args.prune_missing:
        seen_repo_urls = {
            normalize_repo_url(
                record.data.get("clone_url") or record.data.get("html_url") or ""
            )
            for record in repos
        }
        seen_repo_urls.discard("")
        removed = prune_missing_repositories(
            manifest,
            client,
            seen_repo_urls,
            args.prune_max_fraction,
            dry_run=args.dry_run,
            verbose=args.log,
        )

    if args.dry_run:
        print(
            f"Discovered {len(repos)} repositories "
            f"(added={added}, updated={updated}, would remove={len(removed)})"
        )
        return 0

    with open(args.manifest, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")

    print(
        f"Updated manifest {args.manifest}: added {added}, refreshed {updated}, "
        f"removed {len(removed)}"
    )

    # Update .env.template if requested (always run to clean up disabled modules)
    if not args.skip_template:
        template_updated = update_env_template(args.manifest, args.update_template)
        if template_updated:
            print(f"Updated {args.update_template} with active modules only")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

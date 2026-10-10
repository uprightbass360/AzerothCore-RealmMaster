"""Sync behaviour driven by config/module-sources.json."""
import unittest
from datetime import date

import update_module_manifest as umm
from module_sources import Sources
from tests.helpers import entry
from update_module_manifest import MergeResult, RepoRecord, format_digest, merge_repositories


def repo(owner: str, name: str, description: str = "") -> dict:
    return {
        "name": name,
        "clone_url": f"https://github.com/{owner}/{name}.git",
        "html_url": f"https://github.com/{owner}/{name}",
        "description": description,
        "pushed_at": "2026-10-01T00:00:00Z",
    }


def record(data: dict) -> RepoRecord:
    return RepoRecord(data=data, topic_expr="azerothcore-module", module_type="cpp")


def declined(*patterns: str) -> Sources:
    sources = Sources()
    for pattern in patterns:
        sources.decline(pattern, "test", date(2026, 10, 10))
    return sources


class AdmissionTest(unittest.TestCase):
    def test_result_type_and_counts_without_sources(self):
        manifest = {"modules": []}
        result = merge_repositories(manifest, [record(repo("acme", "mod-a"))], refresh_existing=False)
        self.assertIsInstance(result, MergeResult)
        self.assertEqual((result.added, result.updated, result.skipped_declined), (1, 0, 0))
        self.assertEqual([e["key"] for e in result.added_entries], ["MODULE_MOD_A"])

    def test_declined_repo_is_not_added(self):
        manifest = {"modules": []}
        result = merge_repositories(
            manifest,
            [record(repo("buildthehomelab", "wow-mod-weather")), record(repo("acme", "mod-a"))],
            refresh_existing=False,
            sources=declined("buildthehomelab/*"),
        )
        self.assertEqual([e["key"] for e in manifest["modules"]], ["MODULE_MOD_A"])
        self.assertEqual((result.added, result.skipped_declined), (1, 1))

    def test_declined_existing_entry_is_not_refreshed(self):
        existing = entry("MODULE_MOD_OLD", repo="https://github.com/acme/mod-old.git",
                         description="hand-written", last_modified="2024-01-01T00:00:00Z")
        manifest = {"modules": [existing]}
        result = merge_repositories(manifest, [record(repo("acme", "mod-old"))],
                                    refresh_existing=True, sources=declined("acme/mod-old"))
        self.assertEqual(existing["last_modified"], "2024-01-01T00:00:00Z")
        self.assertEqual(existing["description"], "hand-written")
        self.assertEqual((result.updated, result.skipped_declined), (0, 1))

    def test_empty_sources_admits_everything(self):
        manifest = {"modules": []}
        result = merge_repositories(manifest, [record(repo("acme", "mod-a"))],
                                    refresh_existing=False, sources=Sources())
        self.assertEqual((result.added, result.skipped_declined), (1, 0))


class DigestTest(unittest.TestCase):
    def test_empty_digest(self):
        self.assertEqual(format_digest([]), "No new modules this run.\n")

    def test_groups_by_owner_largest_first_then_alphabetical(self):
        added = [
            entry("MODULE_B", repo="https://github.com/zed/b.git", description="B desc"),
            entry("MODULE_A", repo="https://github.com/zed/a.git", description=""),
            entry("MODULE_C", repo="https://github.com/alpha/c.git", description="C desc"),
            entry("MODULE_D", repo="https://gitlab.com/x/d.git", description="D desc"),
        ]
        text = format_digest(added)
        lines = text.splitlines()
        self.assertEqual(lines[0], "4 new module(s) from 3 owner(s):")
        self.assertEqual(lines[2], "- **zed** (2)")
        self.assertEqual(lines[3], "  - `MODULE_A`")
        self.assertEqual(lines[4], "  - `MODULE_B` B desc")
        self.assertEqual(lines[5], "- **alpha** (1)")
        self.assertEqual(lines[7], "- **other** (1)")
        self.assertTrue(text.endswith("\n"))


if __name__ == "__main__":
    unittest.main()

"""Sync behaviour driven by config/module-sources.json."""
import io
import json
import tempfile
import unittest
import unittest.mock
from contextlib import redirect_stdout
from datetime import date
from pathlib import Path

import update_module_manifest as umm
from module_sources import Sources
from tests.helpers import entry
from update_module_manifest import (
    MergeResult,
    RepoRecord,
    format_digest,
    merge_repositories,
    remove_declined_entries,
)


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


class RemoveDeclinedTest(unittest.TestCase):
    def test_removes_matching_entries_and_leaves_others(self):
        keep_me = entry("MODULE_KEEP", repo="https://github.com/acme/keep.git")
        gone = entry("MODULE_GONE", repo="https://github.com/buildthehomelab/wow-mod-x.git")
        not_github = entry("MODULE_GL", repo="https://gitlab.com/buildthehomelab/thing.git")
        manifest = {"modules": [keep_me, gone, not_github]}
        removed = remove_declined_entries(manifest, declined("buildthehomelab/*"))
        self.assertEqual([e["key"] for e in removed], ["MODULE_GONE"])
        self.assertEqual([e["key"] for e in manifest["modules"]], ["MODULE_KEEP", "MODULE_GL"])

    def test_dry_run_reports_but_keeps(self):
        gone = entry("MODULE_GONE", repo="https://github.com/acme/gone.git")
        manifest = {"modules": [gone]}
        out = io.StringIO()
        with redirect_stdout(out):
            removed = remove_declined_entries(manifest, declined("acme/gone"), dry_run=True)
        self.assertEqual(len(removed), 1)
        self.assertEqual(len(manifest["modules"]), 1)
        self.assertIn("[dry-run] Would remove MODULE_GONE", out.getvalue())

    def test_no_cap_on_large_removals(self):
        manifest = {"modules": [entry(f"MODULE_{i}", repo=f"https://github.com/bulk/m{i}.git") for i in range(50)]}
        removed = remove_declined_entries(manifest, declined("bulk/*"))
        self.assertEqual(len(removed), 50)
        self.assertEqual(manifest["modules"], [])


class SourcesOnlyMainTest(unittest.TestCase):
    """End-to-end offline run: --sources-only never touches the network."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.manifest = root / "module-manifest.json"
        self.sources = root / "module-sources.json"
        self.profiles = root / "profiles"
        self.template = root / ".env.template"
        self.digest = root / "digest.md"
        self.profiles.mkdir()
        self.manifest.write_text(json.dumps({"modules": [
            entry("MODULE_KEEP", repo="https://github.com/acme/keep.git", status="active"),
            entry("MODULE_GONE", repo="https://github.com/buildthehomelab/wow-mod-x.git", status="active"),
        ]}, indent=2) + "\n")
        (self.profiles / "curated.json").write_text(json.dumps(
            {"modules": ["MODULE_KEEP", "MODULE_GONE"], "label": "c", "description": "", "order": 1}, indent=2) + "\n")
        self.template.write_text("MODULE_KEEP=0\nMODULE_GONE=0\n")
        self.sources.write_text(json.dumps({
            "policy": {"stale_after_days": 1095, "ignore_profiles": []},
            "declined": {"buildthehomelab/*": {"reason": "bulk", "date": "2026-10-10"}},
            "keep": [],
        }))
        # Any network call is a test failure.
        self.patch = unittest.mock.patch.object(umm.request, "urlopen", side_effect=AssertionError("network"))
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def run_main(self, *extra):
        argv = ["--manifest", str(self.manifest), "--sources", str(self.sources),
                "--profiles-dir", str(self.profiles), "--update-template", str(self.template),
                "--digest-file", str(self.digest), "--sources-only", *extra]
        out = io.StringIO()
        with redirect_stdout(out):
            code = umm.main(argv)
        return code, out.getvalue()

    def test_sources_only_removes_declined_everywhere(self):
        code, out = self.run_main()
        self.assertEqual(code, 0)
        keys = [e["key"] for e in json.loads(self.manifest.read_text())["modules"]]
        self.assertEqual(keys, ["MODULE_KEEP"])
        self.assertEqual(json.loads((self.profiles / "curated.json").read_text())["modules"], ["MODULE_KEEP"])
        self.assertNotIn("MODULE_GONE", self.template.read_text())
        self.assertEqual(self.digest.read_text(), "No new modules this run.\n")
        self.assertIn("declined 1", out)

    def test_sources_only_dry_run_changes_nothing(self):
        before = self.manifest.read_text()
        code, out = self.run_main("--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual(self.manifest.read_text(), before)
        self.assertEqual(json.loads((self.profiles / "curated.json").read_text())["modules"],
                         ["MODULE_KEEP", "MODULE_GONE"])
        self.assertIn("would remove declined=1", out)
        self.assertIn("Would remove 1 unknown key(s) from curated.json: MODULE_GONE", out)

    def test_missing_sources_file_is_a_no_op(self):
        self.sources.unlink()
        before = self.manifest.read_text()
        code, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(self.manifest.read_text(), before)

    def test_malformed_sources_file_fails_loudly(self):
        self.sources.write_text("{broken")
        with self.assertRaises(umm.SourcesError):
            self.run_main()


if __name__ == "__main__":
    unittest.main()

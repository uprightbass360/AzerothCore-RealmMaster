"""last_modified tracks each module repo's last push (GitHub pushed_at)."""
import unittest
from unittest import mock

import update_module_manifest as umm
from update_module_manifest import RepoRecord, merge_repositories, prune_missing_repositories
from tests.helpers import entry


def repo(name: str, pushed_at=None, **fields) -> dict:
    data = {
        "name": name,
        "clone_url": f"https://github.com/example/{name}.git",
        "description": f"{name} description",
    }
    if pushed_at is not None:
        data["pushed_at"] = pushed_at
    data.update(fields)
    return data


def record(data: dict) -> RepoRecord:
    return RepoRecord(data=data, topic_expr="azerothcore-module", module_type="cpp")


class FakeClient:
    def __init__(self, answers: dict):
        self.answers = answers
        self.error_count = 0

    def check_repo(self, full_name: str):
        return self.answers[full_name]


class MergeDatesTest(unittest.TestCase):
    def test_new_entry_gets_pushed_at(self):
        manifest = {"modules": []}
        merge_repositories(manifest, [record(repo("mod-new", "2026-09-01T10:00:00Z"))], refresh_existing=False)
        self.assertEqual(manifest["modules"][0]["last_modified"], "2026-09-01T10:00:00Z")

    def test_existing_entry_is_refreshed_without_refresh_flag(self):
        existing = entry("MODULE_MOD_OLD", repo="https://github.com/example/mod-old.git",
                         description="hand-written", last_modified="2024-01-01T00:00:00Z")
        manifest = {"modules": [existing]}
        merge_repositories(manifest, [record(repo("mod-old", "2026-09-02T00:00:00Z"))], refresh_existing=False)
        self.assertEqual(existing["last_modified"], "2026-09-02T00:00:00Z")
        self.assertEqual(existing["description"], "hand-written")

    def test_missing_pushed_at_keeps_existing_date(self):
        existing = entry("MODULE_MOD_OLD", repo="https://github.com/example/mod-old.git",
                         last_modified="2024-01-01T00:00:00Z")
        manifest = {"modules": [existing]}
        merge_repositories(manifest, [record(repo("mod-old"))], refresh_existing=False)
        self.assertEqual(existing["last_modified"], "2024-01-01T00:00:00Z")


class PruneDatesTest(unittest.TestCase):
    def setUp(self):
        sleep = mock.patch.object(umm.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def test_alive_entry_absent_from_search_gets_pushed_at(self):
        absent = entry("MODULE_MOD_QUIET", repo="https://github.com/example/mod-quiet.git",
                       last_modified="2023-01-01T00:00:00Z")
        manifest = {"modules": [absent]}
        client = FakeClient({"example/mod-quiet": ("alive", {"pushed_at": "2026-08-30T00:00:00Z"})})
        removed = prune_missing_repositories(manifest, client, set(), max_fraction=0.5)
        self.assertEqual(removed, [])
        self.assertEqual(absent["last_modified"], "2026-08-30T00:00:00Z")

    def test_error_verdict_leaves_date_alone(self):
        absent = entry("MODULE_MOD_QUIET", repo="https://github.com/example/mod-quiet.git",
                       last_modified="2023-01-01T00:00:00Z")
        manifest = {"modules": [absent]}
        client = FakeClient({"example/mod-quiet": ("error", None)})
        prune_missing_repositories(manifest, client, set(), max_fraction=0.5)
        self.assertEqual(absent["last_modified"], "2023-01-01T00:00:00Z")


if __name__ == "__main__":
    unittest.main()

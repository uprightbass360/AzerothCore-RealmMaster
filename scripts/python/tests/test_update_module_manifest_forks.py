"""Fork flag, derive_key admission and collision digest in the nightly sync."""
import unittest
import unittest.mock
from datetime import date

from module_sources import Sources
from tests.helpers import entry
from update_module_manifest import (
    RepoRecord,
    format_digest,
    merge_repositories,
    prune_missing_repositories,
    update_fork,
)


def repo(owner: str, name: str, *, fork: bool = False, pushed_at: str = "2026-10-01T00:00:00Z") -> dict:
    return {
        "name": name,
        "full_name": f"{owner}/{name}",
        "clone_url": f"https://github.com/{owner}/{name}.git",
        "html_url": f"https://github.com/{owner}/{name}",
        "description": "",
        "pushed_at": pushed_at,
        "fork": fork,
    }


def record(data: dict) -> RepoRecord:
    return RepoRecord(data=data, topic_expr="azerothcore-module", module_type="cpp")


class FakeClient:
    def __init__(self, answers):
        self.answers = answers
        self.error_count = 0

    def check_repo(self, full_name: str):
        return self.answers[full_name]


class ForkFlagTest(unittest.TestCase):
    def test_update_fork_sets_boolean_when_present(self):
        e = {}
        update_fork(e, {"fork": 1})
        self.assertIs(e["fork"], True)
        update_fork(e, {"fork": False})
        self.assertIs(e["fork"], False)

    def test_update_fork_leaves_entry_alone_when_payload_lacks_field(self):
        e = {"fork": True}
        update_fork(e, {"pushed_at": "2026-01-01T00:00:00Z"})
        self.assertIs(e["fork"], True)
        e2 = {}
        update_fork(e2, {})
        self.assertNotIn("fork", e2)

    def test_new_entry_records_fork_flag(self):
        manifest = {"modules": []}
        merge_repositories(manifest, [record(repo("someone", "mod-a", fork=True)), record(repo("other", "mod-b"))], refresh_existing=False)
        by_name = {m["name"]: m for m in manifest["modules"]}
        self.assertIs(by_name["mod-a"]["fork"], True)
        self.assertIs(by_name["mod-b"]["fork"], False)

    def test_url_match_refreshes_fork_without_changing_key(self):
        existing = entry("MODULE_MOD_X", repo="https://github.com/someone/mod-x.git", fork=False)
        manifest = {"modules": [existing]}
        result = merge_repositories(manifest, [record(repo("someone", "mod-x", fork=True))], refresh_existing=False)
        self.assertEqual(result.updated, 1)
        self.assertEqual(existing["key"], "MODULE_MOD_X")
        self.assertIs(existing["fork"], True)


class VerifyLoopForkTest(unittest.TestCase):
    def setUp(self):
        sleep = unittest.mock.patch("update_module_manifest.time.sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def test_alive_entry_absent_from_search_gets_fork_flag(self):
        absent = entry("MODULE_MOD_QUIET", repo="https://github.com/example/mod-quiet.git")
        manifest = {"modules": [absent]}
        client = FakeClient({"example/mod-quiet": ("alive", {"pushed_at": "2026-08-30T00:00:00Z", "fork": True})})
        prune_missing_repositories(manifest, client, set(), max_fraction=0.5)
        self.assertIs(absent["fork"], True)

    def test_error_verdict_leaves_fork_alone(self):
        absent = entry("MODULE_MOD_QUIET", repo="https://github.com/example/mod-quiet.git", fork=False)
        manifest = {"modules": [absent]}
        client = FakeClient({"example/mod-quiet": ("error", None)})
        prune_missing_repositories(manifest, client, set(), max_fraction=0.5)
        self.assertIs(absent["fork"], False)


if __name__ == "__main__":
    unittest.main()

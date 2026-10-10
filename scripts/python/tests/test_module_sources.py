"""config/module-sources.json: declined patterns, keep list and staleness policy."""
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path

import module_sources as ms
from module_sources import Sources, SourcesError, load_sources, profile_keys, save_sources


class MatchingTest(unittest.TestCase):
    def setUp(self):
        self.sources = Sources(
            declined={"buildthehomelab/*": {"reason": "bulk", "date": "2026-10-10"},
                      "someone/dead": {"reason": "gone", "date": "2026-10-10"}},
            keep={"someone/old-but-fine"},
        )

    def test_exact_match_returns_pattern(self):
        self.assertEqual(self.sources.is_declined("someone/dead"), "someone/dead")

    def test_owner_wildcard_matches_any_repo_of_owner(self):
        self.assertEqual(self.sources.is_declined("buildthehomelab/wow-mod-weather"), "buildthehomelab/*")
        self.assertEqual(self.sources.is_declined("buildthehomelab/anything-new"), "buildthehomelab/*")

    def test_matching_is_case_insensitive_and_ignores_git_suffix(self):
        self.assertEqual(self.sources.is_declined("Someone/Dead.git"), "someone/dead")
        self.assertEqual(self.sources.is_declined("BuildTheHomelab/Wow-Mod-Weather"), "buildthehomelab/*")

    def test_unrelated_repo_is_not_declined(self):
        self.assertIsNone(self.sources.is_declined("azerothcore/mod-ah-bot"))

    def test_none_and_empty_are_not_declined(self):
        self.assertIsNone(self.sources.is_declined(None))
        self.assertIsNone(self.sources.is_declined(""))

    def test_keep_is_exact_and_case_insensitive(self):
        self.assertTrue(self.sources.is_kept("Someone/Old-But-Fine"))
        self.assertFalse(self.sources.is_kept("someone/other"))
        self.assertFalse(self.sources.is_kept(None))

    def test_declined_wins_over_keep(self):
        self.sources.keep.add("buildthehomelab/wow-mod-weather")
        self.assertEqual(self.sources.is_declined("buildthehomelab/wow-mod-weather"), "buildthehomelab/*")

    def test_decline_normalises_and_records_reason_and_date(self):
        self.sources.decline("New/Repo.git", "no upstream activity since 2020-01-01", date(2026, 10, 10))
        self.assertEqual(self.sources.declined["new/repo"],
                         {"reason": "no upstream activity since 2020-01-01", "date": "2026-10-10"})


class PolicyTest(unittest.TestCase):
    def test_default_window_is_1095_days(self):
        self.assertEqual(Sources().stale_after_days, 1095)
        self.assertEqual(Sources().stale_cutoff(date(2026, 10, 10)), date(2023, 10, 11))

    def test_custom_window(self):
        self.assertEqual(Sources(stale_after_days=30).stale_cutoff(date(2026, 3, 1)), date(2026, 1, 30))

    def test_default_ignore_profiles(self):
        self.assertEqual(Sources().ignore_profiles, ["all-modules.json"])


class LoadSaveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "module-sources.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_missing_file_yields_defaults(self):
        sources = load_sources(str(self.path))
        self.assertEqual(sources.stale_after_days, 1095)
        self.assertEqual(sources.declined, {})
        self.assertEqual(sources.keep, set())

    def test_load_normalises_keys(self):
        self.path.write_text(json.dumps({
            "policy": {"stale_after_days": 400, "ignore_profiles": []},
            "declined": {"Owner/*": {"reason": "r", "date": "2026-01-01"},
                         "Other/Repo.git": {"reason": "r2", "date": "2026-01-02"}},
            "keep": ["Keep/Me"],
        }))
        sources = load_sources(str(self.path))
        self.assertEqual(sources.stale_after_days, 400)
        self.assertEqual(sources.ignore_profiles, [])
        self.assertEqual(set(sources.declined), {"owner/*", "other/repo"})
        self.assertEqual(sources.keep, {"keep/me"})

    def test_malformed_json_raises(self):
        self.path.write_text("{not json")
        with self.assertRaises(SourcesError):
            load_sources(str(self.path))

    def test_wrong_shapes_raise(self):
        for bad in (
            [],                                              # not an object
            {"declined": []},                                # declined not a map
            {"declined": {"a/b": "reason as string"}},       # value not an object
            {"declined": {"a/b": {"date": "2026-01-01"}}},   # missing reason
            {"keep": "a/b"},                                 # keep not a list
            {"policy": {"stale_after_days": 0}},             # non-positive window
            {"policy": {"stale_after_days": "365"}},         # not an int
            {"declined": {"no-slash": {"reason": "r", "date": "2026-01-01"}}},  # not owner/repo
            {"keep": ["owner/*"]},                           # keep is exact names only
        ):
            self.path.write_text(json.dumps(bad))
            with self.assertRaises(SourcesError, msg=repr(bad)):
                load_sources(str(self.path))

    def test_save_is_sorted_and_round_trips(self):
        sources = Sources(stale_after_days=500, ignore_profiles=["x.json"])
        sources.decline("zeta/repo", "z", date(2026, 1, 1))
        sources.decline("alpha/*", "a", date(2026, 1, 2))
        sources.keep.update({"m/n", "a/b"})
        save_sources(sources, str(self.path))
        text = self.path.read_text()
        self.assertTrue(text.endswith("}\n"))
        data = json.loads(text)
        self.assertEqual(list(data), ["policy", "declined", "keep"])
        self.assertEqual(list(data["declined"]), ["alpha/*", "zeta/repo"])
        self.assertEqual(data["keep"], ["a/b", "m/n"])
        self.assertEqual(data["policy"], {"stale_after_days": 500, "ignore_profiles": ["x.json"]})
        self.assertEqual(load_sources(str(self.path)), sources)


class ProfileKeysTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        (self.dir / "curated.json").write_text(json.dumps({"modules": ["MODULE_A", "MODULE_B"]}))
        (self.dir / "all-modules.json").write_text(json.dumps({"modules": ["MODULE_C"]}))
        (self.dir / "broken.json").write_text("{nope")
        (self.dir / "notes.txt").write_text("ignored")

    def tearDown(self):
        self.tmp.cleanup()

    def test_union_of_curated_profiles_skipping_ignored_and_unreadable(self):
        self.assertEqual(profile_keys(str(self.dir), ["all-modules.json"]), {"MODULE_A", "MODULE_B"})

    def test_ignored_list_empty_includes_everything(self):
        self.assertEqual(profile_keys(str(self.dir), []), {"MODULE_A", "MODULE_B", "MODULE_C"})

    def test_missing_dir_is_empty(self):
        self.assertEqual(profile_keys(str(self.dir / "nope"), []), set())


if __name__ == "__main__":
    unittest.main()

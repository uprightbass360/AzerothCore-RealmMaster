import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import local_modules

WAVES = {
    "waves": [
        {"id": 1, "renames": {
            "MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS",
            "MODULE_MOD_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS_MALURAMICHAEL",
            "MODULE_ELUNA": "MODULE_MOD_ALE",
        }},
        {"id": 2, "renames": {"MODULE_MOD_STAT_BOOSTER": "MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH"}},
    ]
}


class MigrateCommandTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "config").mkdir()
        (self.root / "config" / "key-renames.json").write_text(json.dumps(WAVES))
        (self.root / "config" / "module-manifest.json").write_text(json.dumps({"modules": []}))

    def _run(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = local_modules.main(["--root", str(self.root), "migrate", *args])
        return code, out.getvalue()

    def test_rewrites_env_and_local_manifest_and_records_the_schema(self):
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\nX=2\n")
        (self.root / "config" / "module-manifest.local.json").write_text(
            json.dumps({"modules": [{"key": "MODULE_PLAYERBOTS", "ref": "abc"}]})
        )
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_PLAYERBOTS=1\nX=2\nMODULES_KEY_SCHEMA=2\n")
        local = json.loads((self.root / "config" / "module-manifest.local.json").read_text())
        self.assertEqual(local["modules"][0]["key"], "MODULE_MOD_PLAYERBOTS")
        self.assertIn("MODULE_PLAYERBOTS -> MODULE_MOD_PLAYERBOTS", out)
        self.assertIn("schema 2 recorded", out)
        self.assertEqual(len(list(self.root.glob(".env.bak-*"))), 1)

    def test_second_run_changes_nothing(self):
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\n")
        self._run()
        after_first = (self.root / ".env").read_text()
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env").read_text(), after_first)
        self.assertEqual(after_first, "MODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertIn("nothing to migrate", out)
        self.assertEqual(len(list(self.root.glob(".env.bak-*"))), 1)

    def test_env_at_an_older_schema_gets_only_the_newer_waves(self):
        (self.root / ".env").write_text("MODULES_KEY_SCHEMA=1\nMODULE_MOD_PLAYERBOTS=1\nMODULE_MOD_STAT_BOOSTER=1\n")
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual(
            (self.root / ".env").read_text(),
            "MODULES_KEY_SCHEMA=2\nMODULE_MOD_PLAYERBOTS=1\nMODULE_MOD_STAT_BOOSTER_BENNYBROSEPH=1\n",
        )
        self.assertNotIn("MALURAMICHAEL", out)

    def test_env_without_old_keys_still_gets_the_schema_recorded(self):
        (self.root / ".env").write_text("MODULE_MOD_UNRELATED=1\n")
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_UNRELATED=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertIn("no keys to rename", out)
        self.assertIn("schema 2 recorded", out)
        self.assertEqual(len(list(self.root.glob(".env.bak-*"))), 1)

    def test_current_schema_is_a_quiet_success(self):
        (self.root / ".env").write_text("MODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertIn("nothing to migrate", out)
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_profiles_passed_as_arguments_are_rewritten(self):
        profile = self.root / "mine.json"
        profile.write_text(json.dumps({"modules": ["MODULE_ELUNA", "MODULE_MOD_STAT_BOOSTER"]}))
        code, out = self._run(str(profile))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(profile.read_text())["modules"], ["MODULE_MOD_ALE", "MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH"])
        self.assertIn(str(profile), out)

    def test_env_override_flag(self):
        other = self.root / "custom.env"
        other.write_text("MODULE_ELUNA=1\n")
        code, _ = self._run("--env", str(other))
        self.assertEqual(code, 0)
        self.assertEqual(other.read_text(), "MODULE_MOD_ALE=1\nMODULES_KEY_SCHEMA=2\n")

    def test_missing_files_are_skipped(self):
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertIn("nothing to migrate", out)

    def test_bad_rename_map_fails(self):
        (self.root / "config" / "key-renames.json").write_text("{")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run()
        self.assertEqual(code, 1)
        self.assertIn("key-renames.json", err.getvalue())

    def test_missing_profile_fails_before_rewriting(self):
        (self.root / ".env").write_text("MODULE_ELUNA=1\n")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(self.root / "nope.json"))
        self.assertEqual(code, 1)
        self.assertIn("nope.json", err.getvalue())
        self.assertEqual((self.root / ".env").read_text(), "MODULE_ELUNA=1\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_local_manifest_is_migrated_against_its_own_schema_when_env_is_absent(self):
        local = self.root / "config" / "module-manifest.local.json"
        local.write_text(json.dumps({"modules": [{"key": "MODULE_PLAYERBOTS", "ref": "abc"}]}))
        code, out = self._run()
        self.assertEqual(code, 0)
        data = json.loads(local.read_text())
        self.assertEqual(data["modules"][0]["key"], "MODULE_MOD_PLAYERBOTS")
        self.assertEqual(data["key_schema"], 2)
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(local.read_text())["modules"][0]["key"], "MODULE_MOD_PLAYERBOTS")
        self.assertIn("nothing to migrate", out)
        self.assertEqual(len(list(self.root.glob("config/module-manifest.local.json.bak-*"))), 1)

    def test_profile_is_migrated_even_when_env_is_current(self):
        (self.root / ".env").write_text("MODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")
        profile = self.root / "old.json"
        profile.write_text(json.dumps({"modules": ["MODULE_PLAYERBOTS"]}))
        code, out = self._run(str(profile))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(profile.read_text()), {"modules": ["MODULE_MOD_PLAYERBOTS"], "key_schema": 2})
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_migrated_profile_is_not_re_renamed_by_an_older_env(self):
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\n")
        profile = self.root / "done.json"
        profile.write_text(json.dumps({"modules": ["MODULE_MOD_PLAYERBOTS"], "key_schema": 1}))
        code, _ = self._run(str(profile))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(profile.read_text()), {"modules": ["MODULE_MOD_PLAYERBOTS"], "key_schema": 2})
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")

    def test_unreadable_marker_is_an_error_and_writes_nothing(self):
        (self.root / ".env").write_text("MODULES_KEY_SCHEMA=two\nMODULE_MOD_PLAYERBOTS=1\n")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run()
        self.assertEqual(code, 1)
        self.assertIn("MODULES_KEY_SCHEMA", err.getvalue())
        self.assertEqual((self.root / ".env").read_text(), "MODULES_KEY_SCHEMA=two\nMODULE_MOD_PLAYERBOTS=1\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_malformed_profile_reports_an_error(self):
        profile = self.root / "broken.json"
        profile.write_text("{")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(profile))
        self.assertEqual(code, 1)
        self.assertIn(str(profile), err.getvalue())

    def test_non_utf8_profile_reports_an_error(self):
        profile = self.root / "binary.json"
        profile.write_bytes(b"\xff\xfe{")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(profile))
        self.assertEqual(code, 1)
        self.assertIn(str(profile), err.getvalue())

    def test_directory_as_profile_reports_an_error(self):
        directory = self.root / "profiles"
        directory.mkdir()
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(directory))
        self.assertEqual(code, 1)
        self.assertIn(str(directory), err.getvalue())


    def test_unmarked_env_already_past_wave_one_is_refused(self):
        (self.root / ".env").write_text("MODULE_MOD_ALE=0\nMODULE_MOD_PLAYERBOTS=1\n")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run()
        self.assertEqual(code, 1)
        self.assertIn("MODULES_KEY_SCHEMA=1", err.getvalue())
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_ALE=0\nMODULE_MOD_PLAYERBOTS=1\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_unmarked_profile_already_past_wave_one_is_refused(self):
        profile = self.root / "p.json"
        profile.write_text(json.dumps({"modules": ["MODULE_MOD_ALE"]}))
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(profile))
        self.assertEqual(code, 1)
        self.assertIn('"key_schema": 1', err.getvalue())
        self.assertEqual(json.loads(profile.read_text()), {"modules": ["MODULE_MOD_ALE"]})

    def test_unmarked_local_manifest_already_past_wave_one_is_refused(self):
        local = self.root / "config" / "module-manifest.local.json"
        local.write_text(json.dumps({"modules": [{"key": "MODULE_MOD_ALE", "ref": "x"}]}))
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run()
        self.assertEqual(code, 1)
        self.assertIn('"key_schema": 1', err.getvalue())
        self.assertIn("module-manifest.local.json", err.getvalue())

    def test_env_at_schema_one_holding_a_wave_two_key_is_refused_with_two(self):
        (self.root / ".env").write_text("MODULES_KEY_SCHEMA=1\nMODULE_MOD_STAT_BOOSTER_BENNYBROSEPH=1\n")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run()
        self.assertEqual(code, 1)
        self.assertIn("MODULES_KEY_SCHEMA=2", err.getvalue())

    def test_a_refusal_writes_no_file_at_all(self):
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\n")
        profile = self.root / "p.json"
        profile.write_text(json.dumps({"modules": ["MODULE_MOD_ALE"]}))
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(profile))
        self.assertEqual(code, 1)
        self.assertEqual((self.root / ".env").read_text(), "MODULE_PLAYERBOTS=1\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_marked_env_with_introduced_keys_migrates_normally(self):
        (self.root / ".env").write_text("MODULES_KEY_SCHEMA=1\nMODULE_MOD_ALE=0\nMODULE_MOD_STAT_BOOSTER=1\n")
        code, _ = self._run()
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env").read_text(), "MODULES_KEY_SCHEMA=2\nMODULE_MOD_ALE=0\nMODULE_MOD_STAT_BOOSTER_BENNYBROSEPH=1\n")


if __name__ == "__main__":
    unittest.main()

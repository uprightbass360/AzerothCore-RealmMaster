import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import local_modules

RENAMES = {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS", "MODULE_ELUNA": "MODULE_MOD_ALE"}


class MigrateCommandTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "config").mkdir()
        (self.root / "config" / "key-renames.json").write_text(json.dumps(RENAMES))
        (self.root / "config" / "module-manifest.json").write_text(json.dumps({"modules": []}))

    def _run(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = local_modules.main(["--root", str(self.root), "migrate", *args])
        return code, out.getvalue()

    def test_rewrites_env_and_local_manifest_and_reports(self):
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\nX=2\n")
        (self.root / "config" / "module-manifest.local.json").write_text(
            json.dumps({"modules": [{"key": "MODULE_PLAYERBOTS", "ref": "abc"}]})
        )
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env").read_text(), "MODULE_MOD_PLAYERBOTS=1\nX=2\n")
        local = json.loads((self.root / "config" / "module-manifest.local.json").read_text())
        self.assertEqual(local["modules"][0]["key"], "MODULE_MOD_PLAYERBOTS")
        self.assertIn("MODULE_PLAYERBOTS -> MODULE_MOD_PLAYERBOTS", out)
        backups = sorted(p.name for p in self.root.glob(".env.bak-*"))
        self.assertEqual(len(backups), 1)

    def test_profiles_passed_as_arguments_are_rewritten(self):
        profile = self.root / "mine.json"
        profile.write_text(json.dumps({"modules": ["MODULE_ELUNA"]}))
        code, out = self._run(str(profile))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(profile.read_text())["modules"], ["MODULE_MOD_ALE"])
        self.assertIn(str(profile), out)

    def test_env_override_flag(self):
        other = self.root / "custom.env"
        other.write_text("MODULE_ELUNA=1\n")
        code, _ = self._run("--env", str(other))
        self.assertEqual(code, 0)
        self.assertEqual(other.read_text(), "MODULE_MOD_ALE=1\n")

    def test_nothing_to_migrate_is_a_quiet_success(self):
        (self.root / ".env").write_text("MODULE_MOD_PLAYERBOTS=1\n")
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertIn("nothing to migrate", out)
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

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
        (self.root / ".env").write_text("MODULE_PLAYERBOTS=1\n")
        missing = str(self.root / "typo.json")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(missing)
        self.assertEqual(code, 1)
        self.assertIn(missing, err.getvalue())
        self.assertEqual((self.root / ".env").read_text(), "MODULE_PLAYERBOTS=1\n")
        self.assertEqual(list(self.root.glob(".env.bak-*")), [])

    def test_malformed_profile_reports_an_error(self):
        profile = self.root / "broken.json"
        profile.write_text("{")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self._run(str(profile))
        self.assertEqual(code, 1)
        self.assertIn(str(profile), err.getvalue())


if __name__ == "__main__":
    unittest.main()

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import rename_keys

WAVES = {
    "waves": [
        {"id": 1, "renames": {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS_FORK"}},
        {"id": 2, "renames": {"MODULE_MOD_STAT_BOOSTER": "MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH"}},
    ]
}


class RenameKeysCliTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "config" / "module-profiles").mkdir(parents=True)
        (self.root / "config" / "key-renames.json").write_text(json.dumps(WAVES))
        # The catalogue is already at wave 1: MODULE_MOD_PLAYERBOTS is the original's key.
        (self.root / "config" / "module-manifest.json").write_text(
            json.dumps({"modules": [{"key": "MODULE_MOD_PLAYERBOTS", "requires": []}, {"key": "MODULE_MOD_STAT_BOOSTER", "requires": ["MODULE_MOD_PLAYERBOTS"]}]})
        )
        (self.root / "config" / "module-profiles" / "a.json").write_text(json.dumps({"modules": ["MODULE_MOD_STAT_BOOSTER"]}))
        (self.root / ".env.template").write_text("MODULE_MOD_PLAYERBOTS=0\nMODULE_MOD_STAT_BOOSTER=0\nMODULES_KEY_SCHEMA=1\n")
        (self.root / ".env.prebuilt").write_text("MODULE_PROFILE=realmmaster\nMODULE_MOD_PLAYERBOTS=1\n")

    def _run(self, *args):
        out = io.StringIO()
        err = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rename_keys.main(["--root", str(self.root), *args])
        return code, out.getvalue() + err.getvalue()

    def test_applies_only_the_named_wave_and_stamps_the_templates(self):
        code, out = self._run("--wave", "2")
        self.assertEqual(code, 0)
        manifest = json.loads((self.root / "config" / "module-manifest.json").read_text())
        self.assertEqual([m["key"] for m in manifest["modules"]], ["MODULE_MOD_PLAYERBOTS", "MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH"])
        self.assertEqual(manifest["modules"][1]["requires"], ["MODULE_MOD_PLAYERBOTS"])
        self.assertEqual(json.loads((self.root / "config" / "module-profiles" / "a.json").read_text())["modules"], ["MODULE_MOD_STAT_BOOSTER_BENNYBROSEPH"])
        self.assertEqual((self.root / ".env.template").read_text(), "MODULE_MOD_PLAYERBOTS=0\nMODULE_MOD_STAT_BOOSTER_BENNYBROSEPH=0\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual((self.root / ".env.prebuilt").read_text(), "MODULE_PROFILE=realmmaster\nMODULE_MOD_PLAYERBOTS=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual(list(self.root.glob("**/*.bak-*")), [])
        self.assertIn("config/module-manifest.json: 1", out)
        self.assertIn("total renames applied: 3", out)

    def test_dry_run_writes_nothing(self):
        before = {p: p.read_text() for p in (self.root / ".env.template", self.root / ".env.prebuilt", self.root / "config" / "module-manifest.json")}
        code, out = self._run("--wave", "2", "--dry-run")
        self.assertEqual(code, 0)
        for p, text in before.items():
            self.assertEqual(p.read_text(), text)
        self.assertIn("[dry-run]", out)
        self.assertIn("total renames applied: 3", out)

    def test_unknown_wave_fails(self):
        code, out = self._run("--wave", "3")
        self.assertEqual(code, 1)
        self.assertIn("wave 3", out)

    def test_wave_is_required(self):
        with self.assertRaises(SystemExit):
            self._run()


if __name__ == "__main__":
    unittest.main()

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import rename_keys

RENAMES = {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS"}


class RenameKeysCliTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "config" / "module-profiles").mkdir(parents=True)
        (self.root / "config" / "key-renames.json").write_text(json.dumps(RENAMES))
        (self.root / "config" / "module-manifest.json").write_text(
            json.dumps({"modules": [{"key": "MODULE_PLAYERBOTS", "requires": []}, {"key": "MODULE_X", "requires": ["MODULE_PLAYERBOTS"]}]})
        )
        (self.root / "config" / "module-profiles" / "a.json").write_text(json.dumps({"modules": ["MODULE_PLAYERBOTS"]}))
        (self.root / ".env.template").write_text("MODULE_PLAYERBOTS=0\n")
        (self.root / ".env.prebuilt").write_text("MODULE_PROFILE=realmmaster\nMODULE_PLAYERBOTS=1\n")

    def _run(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rename_keys.main(["--root", str(self.root), *args])
        return code, out.getvalue()

    def test_rewrites_every_catalogue_file_without_backups(self):
        code, out = self._run()
        self.assertEqual(code, 0)
        manifest = json.loads((self.root / "config" / "module-manifest.json").read_text())
        self.assertEqual([m["key"] for m in manifest["modules"]], ["MODULE_MOD_PLAYERBOTS", "MODULE_X"])
        self.assertEqual(manifest["modules"][1]["requires"], ["MODULE_MOD_PLAYERBOTS"])
        self.assertEqual(json.loads((self.root / "config" / "module-profiles" / "a.json").read_text())["modules"], ["MODULE_MOD_PLAYERBOTS"])
        self.assertEqual((self.root / ".env.template").read_text(), "MODULE_MOD_PLAYERBOTS=0\n")
        self.assertEqual((self.root / ".env.prebuilt").read_text(), "MODULE_PROFILE=realmmaster\nMODULE_MOD_PLAYERBOTS=1\n")
        self.assertEqual(list(self.root.glob("**/*.bak-*")), [])
        self.assertIn("config/module-manifest.json: 2", out)

    def test_dry_run_writes_nothing(self):
        before = (self.root / ".env.template").read_text()
        code, out = self._run("--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual((self.root / ".env.template").read_text(), before)
        self.assertIn("[dry-run]", out)


if __name__ == "__main__":
    unittest.main()

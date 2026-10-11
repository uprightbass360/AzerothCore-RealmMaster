import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from update_module_manifest import main, prune_profiles
from tests.helpers import entry


class SyncKeepsKeySchemaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_manifest_save_keeps_the_top_level_key_schema(self):
        manifest = self.tmp / "module-manifest.json"
        manifest.write_text(json.dumps({"modules": [entry("MODULE_MOD_A")], "key_schema": 1}))  # compact: a rewrite re-indents it
        sources = self.tmp / "sources.json"
        sources.write_text(json.dumps({}))
        with contextlib.redirect_stdout(io.StringIO()):
            rc = main(["--manifest", str(manifest), "--sources", str(sources), "--sources-only", "--skip-template", "--skip-profiles"])
        self.assertEqual(rc, 0)
        self.assertIn("\n  ", manifest.read_text())  # proves the file was rewritten
        data = json.loads(manifest.read_text())
        self.assertEqual(data["key_schema"], 1)
        self.assertEqual([m["key"] for m in data["modules"]], ["MODULE_MOD_A"])

    def test_prune_profiles_keeps_key_schema(self):
        profiles = self.tmp / "profiles"
        profiles.mkdir()
        path = profiles / "p.json"
        path.write_text(json.dumps({"name": "p", "modules": ["MODULE_MOD_A", "MODULE_GONE"], "key_schema": 1}, indent=2) + "\n")
        with contextlib.redirect_stdout(io.StringIO()):
            changes = prune_profiles(str(profiles), {"MODULE_MOD_A"})
        self.assertEqual(len(changes), 1)
        data = json.loads(path.read_text())
        self.assertEqual(data["modules"], ["MODULE_MOD_A"])
        self.assertEqual(data["key_schema"], 1)


if __name__ == "__main__":
    unittest.main()

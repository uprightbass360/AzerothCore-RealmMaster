import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from modules import build_state
from manifest_overlay import local_manifest_path
from tests.helpers import entry, write_manifest

MODULES_PY = Path(__file__).resolve().parents[1] / "modules.py"


class BuildStateMergedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.manifest = write_manifest(
            self.tmp / "module-manifest.json",
            [entry("MODULE_A", type="cpp"), entry("MODULE_B", type="lua")],
        )
        self.env = self.tmp / ".env"
        self.env.write_text("MODULE_MINE=1\nMODULE_A=1\n")

    def test_local_module_is_enabled_and_compiled(self):
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE", type="cpp", name="mod-mine")])
        state = build_state(self.env, self.manifest)
        mine = next(m for m in state.modules if m.key == "MODULE_MINE")
        self.assertEqual(mine.source, "local")
        self.assertTrue(mine.enabled_effective)
        self.assertIn("mod-mine", [m.name for m in state.compile_modules()])
        self.assertFalse(any("MODULE_MINE" in w and "missing from the manifest" in w for w in state.warnings))

    def test_tombstone_is_disabled_even_if_env_enables_it(self):
        write_manifest(local_manifest_path(self.manifest), [{
            "key": "MODULE_MINE", "name": "mod-mine", "repo": "https://example.com/mod-mine.git",
            "status": "blocked", "block_reason": "removed with ./modules.sh remove",
        }])
        state = build_state(self.env, self.manifest)
        mine = next(m for m in state.modules if m.key == "MODULE_MINE")
        self.assertFalse(mine.enabled_effective)
        self.assertNotIn("mod-mine", [m.name for m in state.compile_modules()])

    def test_override_ref_reaches_module_state(self):
        write_manifest(local_manifest_path(self.manifest), [{"key": "MODULE_A", "ref": "v9"}])
        state = build_state(self.env, self.manifest)
        a = next(m for m in state.modules if m.key == "MODULE_A")
        self.assertEqual(a.ref, "v9")
        self.assertEqual(a.source, "override")

    def test_overlay_warnings_are_reported(self):
        write_manifest(local_manifest_path(self.manifest), [{"key": "MODULE_GONE", "ref": "v1"}])
        state = build_state(self.env, self.manifest)
        self.assertTrue(any("MODULE_GONE" in w for w in state.warnings))

    def test_no_local_file_is_unchanged_behaviour(self):
        state = build_state(self.env, self.manifest)
        self.assertEqual({m.source for m in state.modules}, {"upstream"})

    def test_manifest_merged_cli(self):
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE")])
        out = subprocess.run(
            [sys.executable, str(MODULES_PY), "--env-path", str(self.env), "--manifest", str(self.manifest), "manifest", "--merged"],
            capture_output=True, text=True, check=True,
        )
        data = json.loads(out.stdout)
        self.assertEqual([m["source"] for m in data["modules"]], ["upstream", "upstream", "local"])

    def test_manifest_merged_cli_invalid_local_file(self):
        local_manifest_path(self.manifest).write_text("{broken")
        out = subprocess.run(
            [sys.executable, str(MODULES_PY), "--manifest", str(self.manifest), "manifest", "--merged"],
            capture_output=True, text=True,
        )
        self.assertEqual(out.returncode, 1)
        self.assertIn("module-manifest.local.json", out.stderr)


if __name__ == "__main__":
    unittest.main()

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from manifest_overlay import local_manifest_path
from tests.helpers import entry, write_manifest

SETUP_MANIFEST = Path(__file__).resolve().parents[1] / "setup_manifest.py"


class SetupManifestMergedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.manifest = write_manifest(self.tmp / "module-manifest.json", [entry("MODULE_A")])
        write_manifest(local_manifest_path(self.manifest), [entry("MODULE_MINE")])

    def run_cmd(self, command):
        return subprocess.run([sys.executable, str(SETUP_MANIFEST), command, str(self.manifest)],
                              capture_output=True, text=True)

    def test_keys_include_local_modules(self):
        out = self.run_cmd("keys")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.split(), ["MODULE_A", "MODULE_MINE"])

    def test_metadata_includes_local_modules(self):
        out = self.run_cmd("metadata")
        self.assertIn("MODULE_MINE", out.stdout)

    def test_broken_local_file_fails_with_path(self):
        local_manifest_path(self.manifest).write_text("{broken")
        out = self.run_cmd("keys")
        self.assertEqual(out.returncode, 1)
        self.assertIn("module-manifest.local.json", out.stderr)


if __name__ == "__main__":
    unittest.main()

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from update_module_manifest import update_env_template
from tests.helpers import entry, write_manifest


class EnvTemplateKeepsSchemaTest(unittest.TestCase):
    def test_schema_marker_survives_a_sync_that_adds_and_removes_module_lines(self):
        tmp = Path(tempfile.mkdtemp())
        manifest = write_manifest(tmp / "module-manifest.json", [entry("MODULE_MOD_NEW")])
        template = tmp / ".env.template"
        template.write_text("A=1\nMODULES_KEY_SCHEMA=1\nMODULE_MOD_GONE=0\n")
        with contextlib.redirect_stdout(io.StringIO()):
            changed = update_env_template(str(manifest), str(template))
        self.assertTrue(changed)
        self.assertEqual(template.read_text(), "A=1\nMODULES_KEY_SCHEMA=1\nMODULE_MOD_NEW=0\n")


if __name__ == "__main__":
    unittest.main()

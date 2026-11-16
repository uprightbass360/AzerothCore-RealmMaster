import json
import tempfile
import unittest
from pathlib import Path

from modules import build_state
from tests.helpers import entry, write_manifest


class HardStopTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.manifest = write_manifest(
            self.tmp / "config" / "module-manifest.json",
            [entry("MODULE_MOD_PLAYERBOTS", type="cpp")],
        )
        self.env = self.tmp / ".env"

    def _state(self, env_text: str):
        self.env.write_text(env_text)
        return build_state(self.env, self.manifest)

    def test_enabled_unknown_key_is_an_error(self):
        state = self._state("MODULE_PLAYERBOTS=1\n")
        self.assertEqual(len(state.errors), 1)
        self.assertIn("MODULE_PLAYERBOTS", state.errors[0])
        self.assertIn("removed or mistyped", state.errors[0])

    def test_disabled_unknown_key_stays_a_warning(self):
        state = self._state("MODULE_PLAYERBOTS=0\n")
        self.assertEqual(state.errors, [])
        self.assertTrue(any("MODULE_PLAYERBOTS" in w for w in state.warnings))

    def test_truthy_words_are_errors_too(self):
        state = self._state("MODULE_PLAYERBOTS=true\n")
        self.assertEqual(len(state.errors), 1)
        self.assertIn("MODULE_PLAYERBOTS", state.errors[0])

    def test_falsy_words_are_warnings_only(self):
        state = self._state("MODULE_PLAYERBOTS=false\n")
        self.assertEqual(state.errors, [])
        self.assertTrue(any("MODULE_PLAYERBOTS" in w for w in state.warnings))

    def test_non_flag_module_setting_is_ignored(self):
        state = self._state("MODULE_PROFILE=realmmaster\n")
        self.assertEqual(state.errors, [])
        self.assertFalse(any("MODULE_PROFILE" in w for w in state.warnings))

    def test_hint_names_the_new_key_when_the_rename_map_knows_it(self):
        (self.tmp / "config" / "key-renames.json").write_text(
            json.dumps({"waves": [{"id": 1, "renames": {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS"}}]})
        )
        state = self._state("MODULE_PLAYERBOTS=1\n")
        self.assertEqual(len(state.errors), 1)
        self.assertIn("MODULE_MOD_PLAYERBOTS", state.errors[0])
        self.assertIn("./modules.sh migrate", state.errors[0])

    def test_hint_resolves_the_final_key_across_waves(self):
        (self.tmp / "config" / "key-renames.json").write_text(json.dumps({"waves": [
            {"id": 1, "renames": {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS_FORK"}},
            {"id": 2, "renames": {"MODULE_MOD_PLAYERBOTS_FORK": "MODULE_MOD_PLAYERBOTS_FORK_V2"}},
        ]}))
        state = self._state("MODULE_PLAYERBOTS=1\n")
        self.assertTrue(any("is now MODULE_MOD_PLAYERBOTS;" in e for e in state.errors), state.errors)
        state = self._state("MODULE_MOD_PLAYERBOTS_FORK=1\n")
        self.assertTrue(any("is now MODULE_MOD_PLAYERBOTS_FORK_V2;" in e for e in state.errors), state.errors)

    def test_schema_marker_is_not_a_module_key(self):
        state = self._state("MODULES_KEY_SCHEMA=2\nMODULE_MOD_PLAYERBOTS=1\n")
        self.assertEqual(state.errors, [])
        self.assertEqual([w for w in state.warnings if "MODULES_KEY_SCHEMA" in w], [])

    def test_stop_fires_when_the_rename_map_is_unreadable(self):
        (self.tmp / "config" / "key-renames.json").write_text("{")
        state = self._state("MODULE_PLAYERBOTS=1\n")
        self.assertEqual(len(state.errors), 1)
        self.assertNotIn("migrate", state.errors[0])

    def test_known_key_enabled_is_not_an_error(self):
        state = self._state("MODULE_MOD_PLAYERBOTS=1\n")
        self.assertEqual(state.errors, [])


if __name__ == "__main__":
    unittest.main()

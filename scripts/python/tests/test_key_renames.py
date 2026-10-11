import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from key_renames import (
    RenameError,
    backup_path,
    load_rename_map,
    rewrite_entries,
    rewrite_env_file,
    rewrite_env_text,
    rewrite_key_list,
    rewrite_manifest_file,
    rewrite_profile_file,
)

RENAMES = {
    "MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS",
    "MODULE_MOD_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS_MALURAMICHAEL",
    "MODULE_ELUNA": "MODULE_MOD_ALE",
}
NOW = datetime(2026, 10, 11, 9, 30, 0)


class RewriteEnvTextTest(unittest.TestCase):
    def test_renames_only_the_key_and_keeps_everything_else(self):
        text = "# header\nexport MODULE_PLAYERBOTS=1  # on\nMODULE_ELUNA=\"1\"\nOTHER=MODULE_ELUNA\n\n"
        out, changes = rewrite_env_text(text, RENAMES)
        self.assertEqual(
            out,
            "# header\nexport MODULE_MOD_PLAYERBOTS=1  # on\nMODULE_MOD_ALE=\"1\"\nOTHER=MODULE_ELUNA\n\n",
        )
        self.assertEqual(changes, [("MODULE_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS"), ("MODULE_ELUNA", "MODULE_MOD_ALE")])

    def test_preserves_crlf_line_endings(self):
        out, _ = rewrite_env_text("MODULE_ELUNA=1\r\nX=1\r\n", RENAMES)
        self.assertEqual(out, "MODULE_MOD_ALE=1\r\nX=1\r\n")

    def test_single_pass_never_chains(self):
        text = "MODULE_PLAYERBOTS=1\nMODULE_MOD_PLAYERBOTS=0\n"
        out, _ = rewrite_env_text(text, RENAMES)
        self.assertEqual(out, "MODULE_MOD_PLAYERBOTS=1\nMODULE_MOD_PLAYERBOTS_MALURAMICHAEL=0\n")

    def test_does_not_touch_longer_keys_sharing_a_prefix(self):
        out, changes = rewrite_env_text("MODULE_PLAYERBOTS_CHARACTERS=1\n", RENAMES)
        self.assertEqual(out, "MODULE_PLAYERBOTS_CHARACTERS=1\n")
        self.assertEqual(changes, [])

    def test_unchanged_text_reports_no_changes(self):
        out, changes = rewrite_env_text("A=1\n", RENAMES)
        self.assertEqual((out, changes), ("A=1\n", []))


class RewriteJsonTest(unittest.TestCase):
    def test_entries_rename_key_and_requires_in_place(self):
        entries = [
            {"key": "MODULE_PLAYERBOTS", "requires": []},
            {"key": "MODULE_X", "requires": ["MODULE_PLAYERBOTS", "MODULE_Y"]},
        ]
        changes = rewrite_entries(entries, RENAMES)
        self.assertEqual(entries[0]["key"], "MODULE_MOD_PLAYERBOTS")
        self.assertEqual(entries[1]["requires"], ["MODULE_MOD_PLAYERBOTS", "MODULE_Y"])
        self.assertEqual(changes, [("MODULE_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS")] * 2)

    def test_key_list(self):
        keys, changes = rewrite_key_list(["MODULE_ELUNA", "MODULE_Z"], RENAMES)
        self.assertEqual(keys, ["MODULE_MOD_ALE", "MODULE_Z"])
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])


class FileHelpersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_backup_path_format(self):
        self.assertEqual(backup_path(Path("/x/.env"), NOW).name, ".env.bak-20261011-093000")

    def test_env_file_rewritten_with_backup_only_when_changed(self):
        env = self.tmp / ".env"
        env.write_text("MODULE_ELUNA=1\n")
        changes = rewrite_env_file(env, RENAMES, now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])
        self.assertEqual(env.read_text(), "MODULE_MOD_ALE=1\n")
        self.assertEqual((self.tmp / ".env.bak-20261011-093000").read_text(), "MODULE_ELUNA=1\n")
        second = rewrite_env_file(env, RENAMES, now=datetime(2026, 10, 11, 9, 31, 0))
        self.assertEqual(second, [])
        self.assertFalse((self.tmp / ".env.bak-20261011-093100").exists())

    def test_crlf_env_file_keeps_crlf_in_file_and_backup(self):
        env = self.tmp / ".env"
        src = b"MODULE_PLAYERBOTS=1\r\nOTHER=2\r\n"
        env.write_bytes(src)
        rewrite_env_file(env, {"MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS"}, now=datetime(2026, 1, 2, 3, 4, 5))
        self.assertEqual(env.read_bytes(), b"MODULE_MOD_PLAYERBOTS=1\r\nOTHER=2\r\n")
        backups = [b for b in self.tmp.iterdir() if b.name != ".env"]
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), src)

    def test_env_file_without_backup(self):
        env = self.tmp / ".env.template"
        env.write_text("MODULE_ELUNA=1\n")
        rewrite_env_file(env, RENAMES, backup=False, now=NOW)
        self.assertEqual(list(self.tmp.iterdir()), [env])

    def test_manifest_file_rewrites_entries_and_keeps_layout(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text(json.dumps({"modules": [{"key": "MODULE_PLAYERBOTS", "ref": "abc"}]}, indent=2) + "\n")
        changes = rewrite_manifest_file(path, RENAMES, now=NOW)
        self.assertEqual(changes, [("MODULE_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS")])
        self.assertEqual(
            path.read_text(),
            json.dumps({"modules": [{"key": "MODULE_MOD_PLAYERBOTS", "ref": "abc"}]}, indent=2) + "\n",
        )

    def test_profile_file_rewrites_module_list_and_keeps_other_fields(self):
        path = self.tmp / "mine.json"
        path.write_text(json.dumps({"name": "mine", "modules": ["MODULE_ELUNA", "MODULE_Q"]}, indent=2) + "\n")
        changes = rewrite_profile_file(path, RENAMES, now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])
        self.assertEqual(json.loads(path.read_text()), {"name": "mine", "modules": ["MODULE_MOD_ALE", "MODULE_Q"]})


class LoadRenameMapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.path = self.tmp / "key-renames.json"

    def test_loads_flat_map(self):
        self.path.write_text(json.dumps(RENAMES))
        self.assertEqual(load_rename_map(self.path), RENAMES)

    def test_missing_file_raises(self):
        with self.assertRaises(RenameError):
            load_rename_map(self.path)

    def test_malformed_json_raises(self):
        self.path.write_text("{")
        with self.assertRaises(RenameError):
            load_rename_map(self.path)

    def test_rejects_non_module_keys_and_self_maps(self):
        self.path.write_text(json.dumps({"FOO": "MODULE_X"}))
        with self.assertRaises(RenameError):
            load_rename_map(self.path)
        self.path.write_text(json.dumps({"MODULE_X": "MODULE_X"}))
        with self.assertRaises(RenameError):
            load_rename_map(self.path)


if __name__ == "__main__":
    unittest.main()

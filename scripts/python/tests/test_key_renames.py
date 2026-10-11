import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from key_renames import (
    SCHEMA_FIELD,
    SCHEMA_KEY,
    RenameError,
    Wave,
    ahead_of_schema,
    backup_path,
    catalogue_schema,
    cumulative_map,
    document_keys,
    env_keys,
    introduced_keys,
    load_rename_waves,
    read_json_schema,
    read_schema,
    rewrite_entries,
    rewrite_env_file,
    rewrite_env_text,
    rewrite_key_list,
    rewrite_manifest_file,
    rewrite_profile_file,
    set_schema_text,
)

RENAMES = {
    "MODULE_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS",
    "MODULE_MOD_PLAYERBOTS": "MODULE_MOD_PLAYERBOTS_MALURAMICHAEL",
    "MODULE_ELUNA": "MODULE_MOD_ALE",
}
WAVE2 = {"MODULE_MOD_ALE": "MODULE_MOD_ALE_V2"}
NOW = datetime(2026, 10, 11, 9, 30, 0)


def waves_doc(*maps):
    return json.dumps({"waves": [{"id": i, "renames": m} for i, m in enumerate(maps, start=1)]})


class RewriteEnvTextTest(unittest.TestCase):
    def test_renames_only_the_key_and_keeps_everything_else(self):
        text = "# header\n  export MODULE_PLAYERBOTS=1 # on\nMODULE_OTHER=0\n\nMODULE_ELUNA = 0\n"
        out, changes = rewrite_env_text(text, RENAMES)
        self.assertEqual(
            out, "# header\n  export MODULE_MOD_PLAYERBOTS=1 # on\nMODULE_OTHER=0\n\nMODULE_MOD_ALE = 0\n"
        )
        self.assertEqual(changes, [("MODULE_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS"), ("MODULE_ELUNA", "MODULE_MOD_ALE")])

    def test_preserves_crlf_line_endings(self):
        out, _ = rewrite_env_text("MODULE_ELUNA=1\r\nX=1\r\n", RENAMES)
        self.assertEqual(out, "MODULE_MOD_ALE=1\r\nX=1\r\n")

    def test_single_pass_never_chains(self):
        out, changes = rewrite_env_text("MODULE_PLAYERBOTS=1\nMODULE_MOD_PLAYERBOTS=1\n", RENAMES)
        self.assertEqual(out, "MODULE_MOD_PLAYERBOTS=1\nMODULE_MOD_PLAYERBOTS_MALURAMICHAEL=1\n")
        self.assertEqual(len(changes), 2)

    def test_does_not_touch_longer_keys_sharing_a_prefix(self):
        out, changes = rewrite_env_text("MODULE_ELUNA_TS=1\n", RENAMES)
        self.assertEqual(out, "MODULE_ELUNA_TS=1\n")
        self.assertEqual(changes, [])

    def test_unchanged_text_reports_no_changes(self):
        out, changes = rewrite_env_text("A=1\n", RENAMES)
        self.assertEqual((out, changes), ("A=1\n", []))


class RewriteJsonTest(unittest.TestCase):
    def test_entries_rename_key_and_requires_in_place(self):
        entries = [
            {"key": "MODULE_PLAYERBOTS", "requires": ["MODULE_ELUNA", "MODULE_Q"]},
            {"key": "MODULE_Q"},
        ]
        changes = rewrite_entries(entries, RENAMES)
        self.assertEqual(entries[0], {"key": "MODULE_MOD_PLAYERBOTS", "requires": ["MODULE_MOD_ALE", "MODULE_Q"]})
        self.assertEqual(entries[1], {"key": "MODULE_Q"})
        self.assertEqual(changes, [("MODULE_PLAYERBOTS", "MODULE_MOD_PLAYERBOTS"), ("MODULE_ELUNA", "MODULE_MOD_ALE")])

    def test_key_list(self):
        keys, changes = rewrite_key_list(["MODULE_ELUNA", "MODULE_Q"], RENAMES)
        self.assertEqual(keys, ["MODULE_MOD_ALE", "MODULE_Q"])
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])


class SchemaMarkerTest(unittest.TestCase):
    def test_read_schema_absent_is_zero(self):
        self.assertEqual(read_schema("MODULE_X=1\n"), 0)

    def test_read_schema_reads_the_value(self):
        self.assertEqual(read_schema("A=1\n  export MODULES_KEY_SCHEMA = 3 # note\n"), 3)

    def test_read_schema_tolerates_quotes(self):
        self.assertEqual(read_schema('MODULES_KEY_SCHEMA="1"\n'), 1)
        self.assertEqual(read_schema("MODULES_KEY_SCHEMA='2'\n"), 2)

    def test_read_schema_present_but_unreadable_is_an_error(self):
        for bad in ("MODULES_KEY_SCHEMA=two\n", "MODULES_KEY_SCHEMA=\n", "MODULES_KEY_SCHEMA=-1\n"):
            with self.assertRaises(RenameError):
                read_schema(bad)

    def test_read_json_schema(self):
        self.assertEqual(read_json_schema({"modules": []}), 0)
        self.assertEqual(read_json_schema({"modules": [], "key_schema": 2}), 2)
        self.assertEqual(read_json_schema(["not", "a", "dict"]), 0)
        for bad in ({"key_schema": "2"}, {"key_schema": True}, {"key_schema": -1}, {"key_schema": 1.5}):
            with self.assertRaises(RenameError):
                read_json_schema(bad)

    def test_catalogue_schema_reads_the_manifest(self):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "m.json").write_text(json.dumps({"modules": []}))
        self.assertEqual(catalogue_schema(tmp / "m.json"), 0)
        (tmp / "m.json").write_text(json.dumps({"modules": [], "key_schema": 2}))
        self.assertEqual(catalogue_schema(tmp / "m.json"), 2)

    def test_set_schema_replaces_in_place_keeping_lead_and_comment(self):
        out = set_schema_text("A=1\n  export MODULES_KEY_SCHEMA=1 # keep\nB=2\n", 2)
        self.assertEqual(out, "A=1\n  export MODULES_KEY_SCHEMA=2 # keep\nB=2\n")

    def test_set_schema_appends_in_the_files_line_ending(self):
        self.assertEqual(set_schema_text("A=1\r\n", 2), "A=1\r\nMODULES_KEY_SCHEMA=2\r\n")
        self.assertEqual(set_schema_text("A=1\n", 2), "A=1\nMODULES_KEY_SCHEMA=2\n")

    def test_set_schema_terminates_an_unterminated_last_line_first(self):
        self.assertEqual(set_schema_text("A=1", 2), "A=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual(set_schema_text("", 2), "MODULES_KEY_SCHEMA=2\n")


class FileHelpersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_backup_path_format(self):
        self.assertEqual(backup_path(Path("/x/.env"), NOW).name, ".env.bak-20261011-093000")

    def test_env_file_rewritten_with_backup_only_when_changed(self):
        path = self.tmp / ".env"
        path.write_text("MODULE_ELUNA=1\n")
        changes = rewrite_env_file(path, [RENAMES], now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])
        self.assertEqual(path.read_text(), "MODULE_MOD_ALE=1\n")
        self.assertEqual((self.tmp / ".env.bak-20261011-093000").read_text(), "MODULE_ELUNA=1\n")
        later = datetime(2026, 10, 11, 9, 31, 0)
        self.assertEqual(rewrite_env_file(path, [RENAMES], now=later), [])
        self.assertFalse((self.tmp / ".env.bak-20261011-093100").exists())

    def test_env_file_applies_passes_in_order_with_one_backup(self):
        path = self.tmp / ".env"
        path.write_text("MODULE_ELUNA=1\n")
        changes = rewrite_env_file(path, [RENAMES, WAVE2], now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE"), ("MODULE_MOD_ALE", "MODULE_MOD_ALE_V2")])
        self.assertEqual(path.read_text(), "MODULE_MOD_ALE_V2=1\n")
        self.assertEqual(sorted(p.name for p in self.tmp.glob(".env.bak-*")), [".env.bak-20261011-093000"])
        self.assertEqual((self.tmp / ".env.bak-20261011-093000").read_text(), "MODULE_ELUNA=1\n")

    def test_env_file_records_schema_even_without_renames(self):
        path = self.tmp / ".env"
        path.write_text("A=1\n")
        self.assertEqual(rewrite_env_file(path, [RENAMES], schema=2, now=NOW), [])
        self.assertEqual(path.read_text(), "A=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual((self.tmp / ".env.bak-20261011-093000").read_text(), "A=1\n")

    def test_env_file_with_current_schema_and_no_renames_is_untouched(self):
        path = self.tmp / ".env"
        path.write_text("A=1\nMODULES_KEY_SCHEMA=2\n")
        self.assertEqual(rewrite_env_file(path, [RENAMES], schema=2, now=NOW), [])
        self.assertEqual(list(self.tmp.glob(".env.bak-*")), [])

    def test_crlf_env_file_keeps_crlf_in_file_and_backup(self):
        path = self.tmp / ".env"
        path.write_bytes(b"MODULE_ELUNA=1\r\nX=1\r\n")
        rewrite_env_file(path, [RENAMES], schema=1, now=NOW)
        self.assertEqual(path.read_bytes(), b"MODULE_MOD_ALE=1\r\nX=1\r\nMODULES_KEY_SCHEMA=1\r\n")
        self.assertEqual((self.tmp / ".env.bak-20261011-093000").read_bytes(), b"MODULE_ELUNA=1\r\nX=1\r\n")

    def test_env_file_without_backup(self):
        path = self.tmp / ".env.template"
        path.write_text("MODULE_ELUNA=0\n")
        rewrite_env_file(path, [RENAMES], backup=False, now=NOW)
        self.assertEqual(path.read_text(), "MODULE_MOD_ALE=0\n")
        self.assertEqual(list(self.tmp.glob("*.bak-*")), [])

    def test_manifest_file_rewrites_entries_and_keeps_layout(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text(json.dumps({"modules": [{"key": "MODULE_ELUNA", "ref": "x"}], "extra": 1}, indent=2) + "\n")
        changes = rewrite_manifest_file(path, [RENAMES], now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])
        data = json.loads(path.read_text())
        self.assertEqual(data["modules"][0]["key"], "MODULE_MOD_ALE")
        self.assertEqual(data["extra"], 1)
        self.assertTrue(path.read_text().endswith("}\n"))
        self.assertTrue((self.tmp / "module-manifest.local.json.bak-20261011-093000").exists())

    def test_manifest_file_without_changes_is_not_rewritten(self):
        path = self.tmp / "module-manifest.local.json"
        original = '{"modules": [{"key": "MODULE_Q"}]}'
        path.write_text(original)
        self.assertEqual(rewrite_manifest_file(path, [RENAMES], now=NOW), [])
        self.assertEqual(path.read_text(), original)
        self.assertEqual(list(self.tmp.glob("*.bak-*")), [])

    def test_manifest_file_stamps_schema_even_without_renames(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text(json.dumps({"modules": [{"key": "MODULE_Q"}]}))
        self.assertEqual(rewrite_manifest_file(path, [RENAMES], schema=2, now=NOW), [])
        data = json.loads(path.read_text())
        self.assertEqual(data, {"modules": [{"key": "MODULE_Q"}], "key_schema": 2})
        self.assertTrue((self.tmp / "module-manifest.local.json.bak-20261011-093000").exists())

    def test_manifest_file_with_current_schema_and_no_renames_is_untouched(self):
        path = self.tmp / "module-manifest.local.json"
        original = json.dumps({"modules": [{"key": "MODULE_Q"}], "key_schema": 2})
        path.write_text(original)
        self.assertEqual(rewrite_manifest_file(path, [RENAMES], schema=2, now=NOW), [])
        self.assertEqual(path.read_text(), original)
        self.assertEqual(list(self.tmp.glob("*.bak-*")), [])

    def test_profile_file_stamps_schema_and_keeps_other_fields(self):
        path = self.tmp / "mine.json"
        path.write_text(json.dumps({"name": "mine", "modules": ["MODULE_ELUNA"], "order": 5}))
        changes = rewrite_profile_file(path, [RENAMES], schema=1, now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE")])
        self.assertEqual(json.loads(path.read_text()), {"name": "mine", "modules": ["MODULE_MOD_ALE"], "order": 5, "key_schema": 1})

    def test_profile_file_rewrites_module_list_and_keeps_other_fields(self):
        path = self.tmp / "mine.json"
        path.write_text(json.dumps({"name": "mine", "modules": ["MODULE_ELUNA", "MODULE_Q"]}))
        changes = rewrite_profile_file(path, [RENAMES, WAVE2], now=NOW)
        self.assertEqual(changes, [("MODULE_ELUNA", "MODULE_MOD_ALE"), ("MODULE_MOD_ALE", "MODULE_MOD_ALE_V2")])
        self.assertEqual(json.loads(path.read_text()), {"name": "mine", "modules": ["MODULE_MOD_ALE_V2", "MODULE_Q"]})


class LoadRenameWavesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.path = self.tmp / "key-renames.json"

    def test_loads_waves_in_order(self):
        self.path.write_text(waves_doc(RENAMES, WAVE2))
        self.assertEqual(load_rename_waves(self.path), [Wave(1, RENAMES), Wave(2, WAVE2)])

    def test_missing_file_raises(self):
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)

    def test_malformed_json_raises(self):
        self.path.write_text("{")
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)

    def test_flat_map_is_rejected(self):
        self.path.write_text(json.dumps(RENAMES))
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)

    def test_ids_must_be_consecutive_from_one(self):
        self.path.write_text(json.dumps({"waves": [{"id": 2, "renames": RENAMES}]}))
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)
        self.path.write_text(json.dumps({"waves": [{"id": 1, "renames": RENAMES}, {"id": 3, "renames": WAVE2}]}))
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)

    def test_rejects_non_module_keys_self_maps_and_empty_waves(self):
        for bad in ({"FOO": "MODULE_X"}, {"MODULE_X": "MODULE_X"}, {}):
            self.path.write_text(waves_doc(bad))
            with self.assertRaises(RenameError):
                load_rename_waves(self.path)

    def test_ids_must_be_true_integers(self):
        for bad_id in (True, 1.0, "1"):
            self.path.write_text(json.dumps({"waves": [{"id": bad_id, "renames": RENAMES}]}))
            with self.assertRaises(RenameError):
                load_rename_waves(self.path)

    def test_an_old_key_may_not_reappear_as_an_old_key_in_a_later_wave(self):
        self.path.write_text(waves_doc(RENAMES, {"MODULE_ELUNA": "MODULE_ELSEWHERE"}))
        with self.assertRaises(RenameError):
            load_rename_waves(self.path)


class CumulativeMapTest(unittest.TestCase):
    def test_resolves_across_waves_but_never_inside_one(self):
        cum = cumulative_map([Wave(1, RENAMES), Wave(2, WAVE2)])
        self.assertEqual(cum["MODULE_ELUNA"], "MODULE_MOD_ALE_V2")
        self.assertEqual(cum["MODULE_MOD_ALE"], "MODULE_MOD_ALE_V2")
        self.assertEqual(cum["MODULE_PLAYERBOTS"], "MODULE_MOD_PLAYERBOTS")
        self.assertEqual(cum["MODULE_MOD_PLAYERBOTS"], "MODULE_MOD_PLAYERBOTS_MALURAMICHAEL")
        self.assertEqual(len(cum), 4)

    def test_schema_key_constant(self):
        self.assertEqual(SCHEMA_KEY, "MODULES_KEY_SCHEMA")


class AheadOfSchemaTest(unittest.TestCase):
    WAVES = [Wave(1, RENAMES), Wave(2, WAVE2)]

    def test_introduced_keys_exclude_dual_role_keys(self):
        self.assertEqual(introduced_keys(Wave(1, RENAMES)), {"MODULE_MOD_PLAYERBOTS_MALURAMICHAEL", "MODULE_MOD_ALE"})

    def test_schema_zero_holding_a_wave_one_key_is_ahead(self):
        self.assertEqual(ahead_of_schema(["MODULE_MOD_ALE", "MODULE_Q"], self.WAVES, 0), 1)

    def test_dual_role_key_alone_is_not_evidence(self):
        self.assertIsNone(ahead_of_schema(["MODULE_MOD_PLAYERBOTS"], self.WAVES, 0))

    def test_highest_wave_wins(self):
        self.assertEqual(ahead_of_schema(["MODULE_MOD_ALE", "MODULE_MOD_ALE_V2"], self.WAVES, 0), 2)

    def test_keys_of_applied_waves_are_fine(self):
        self.assertIsNone(ahead_of_schema(["MODULE_MOD_ALE"], self.WAVES, 1))

    def test_env_keys(self):
        self.assertEqual(env_keys("# c\nexport MODULE_A=1\nX=2\n  MODULE_B = 0\n"), ["MODULE_A", "MODULE_B"])

    def test_document_keys_manifest_and_profile(self):
        self.assertEqual(document_keys({"modules": [{"key": "MODULE_A", "requires": ["MODULE_B"]}, {"ref": "x"}]}), ["MODULE_A", "MODULE_B"])
        self.assertEqual(document_keys({"modules": ["MODULE_A", 3]}), ["MODULE_A"])
        self.assertEqual(document_keys({"modules": "no"}), [])
        self.assertEqual(document_keys([]), [])


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path

from manifest_overlay import (
    ManifestError,
    load_local_entries,
    load_merged_manifest,
    local_manifest_path,
    merge_manifest,
)
from tests.helpers import entry, write_manifest


class MergeManifestTest(unittest.TestCase):
    def test_upstream_only_gets_source_upstream(self):
        merged, warnings = merge_manifest([entry("MODULE_A")], [])
        self.assertEqual(merged[0]["source"], "upstream")
        self.assertEqual(warnings, [])

    def test_new_local_entry_is_appended(self):
        merged, _ = merge_manifest([entry("MODULE_A")], [entry("MODULE_MINE")])
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_MINE"])
        self.assertEqual(merged[1]["source"], "local")

    def test_override_is_per_field(self):
        up = entry("MODULE_A", description="upstream text", ref=None)
        merged, _ = merge_manifest([up], [{"key": "MODULE_A", "ref": "v1.2"}])
        self.assertEqual(merged[0]["ref"], "v1.2")
        self.assertEqual(merged[0]["description"], "upstream text")
        self.assertEqual(merged[0]["repo"], up["repo"])
        self.assertEqual(merged[0]["source"], "override")

    def test_override_replaces_lists(self):
        up = entry("MODULE_A", requires=["MODULE_X", "MODULE_Y"])
        merged, _ = merge_manifest([up], [{"key": "MODULE_A", "requires": ["MODULE_Z"]}])
        self.assertEqual(merged[0]["requires"], ["MODULE_Z"])

    def test_override_keeps_upstream_position(self):
        merged, _ = merge_manifest(
            [entry("MODULE_A"), entry("MODULE_B")], [{"key": "MODULE_A", "ref": "x"}]
        )
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_B"])

    def test_orphaned_partial_override_is_skipped_with_warning(self):
        merged, warnings = merge_manifest([entry("MODULE_A")], [{"key": "MODULE_GONE", "ref": "v1"}])
        self.assertEqual([m["key"] for m in merged], ["MODULE_A"])
        self.assertEqual(len(warnings), 1)
        self.assertIn("MODULE_GONE", warnings[0])

    def test_orphan_with_name_and_repo_becomes_local(self):
        merged, warnings = merge_manifest([], [entry("MODULE_GONE")])
        self.assertEqual(merged[0]["source"], "local")
        self.assertEqual(warnings, [])

    def test_unblocking_override_warns_with_reason(self):
        up = entry("MODULE_A", status="blocked", block_reason="breaks the build")
        merged, warnings = merge_manifest([up], [{"key": "MODULE_A", "status": "active"}])
        self.assertEqual(merged[0]["status"], "active")
        self.assertEqual(len(warnings), 1)
        self.assertIn("breaks the build", warnings[0])

    def test_local_source_field_is_ignored(self):
        merged, _ = merge_manifest([], [dict(entry("MODULE_MINE"), source="upstream")])
        self.assertEqual(merged[0]["source"], "local")

    def test_inputs_are_not_mutated(self):
        up = entry("MODULE_A")
        local = {"key": "MODULE_A", "ref": "v1"}
        merge_manifest([up], [local])
        self.assertNotIn("source", up)
        self.assertNotIn("ref", up)


class LoadLocalEntriesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_missing_file_is_empty(self):
        self.assertEqual(load_local_entries(self.tmp / "nope.json"), [])

    def test_invalid_json_names_the_file(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text("{not json")
        with self.assertRaises(ManifestError) as ctx:
            load_local_entries(path)
        self.assertIn(str(path), str(ctx.exception))

    def test_modules_must_be_a_list(self):
        path = self.tmp / "module-manifest.local.json"
        path.write_text('{"modules": {}}')
        with self.assertRaises(ManifestError):
            load_local_entries(path)

    def test_entry_needs_string_key(self):
        path = write_manifest(self.tmp / "module-manifest.local.json", [{"name": "x"}])
        with self.assertRaises(ManifestError):
            load_local_entries(path)

    def test_duplicate_keys_are_an_error(self):
        path = write_manifest(self.tmp / "module-manifest.local.json", [entry("MODULE_A"), {"key": "MODULE_A"}])
        with self.assertRaises(ManifestError) as ctx:
            load_local_entries(path)
        self.assertIn("MODULE_A", str(ctx.exception))

    def assert_rejected(self, item, needle):
        path = write_manifest(self.tmp / "module-manifest.local.json", [item])
        with self.assertRaises(ManifestError) as ctx:
            load_local_entries(path)
        self.assertIn(str(path), str(ctx.exception))
        self.assertIn(needle, str(ctx.exception))

    def test_key_must_look_like_module_key(self):
        self.assert_rejected(entry("mod_foo"), "mod_foo")

    def test_key_with_spaces_or_substitution_is_rejected(self):
        self.assert_rejected(entry("MODULE_FOO $(id)"), "MODULE_FOO $(id)")
        self.assert_rejected({"key": "MODULE_FOO BAR", "ref": "v1"}, "MODULE_FOO BAR")

    def test_name_dotdot_is_rejected(self):
        self.assert_rejected(entry("MODULE_FOO", name=".."), "..")

    def test_name_with_slash_is_rejected(self):
        self.assert_rejected(entry("MODULE_FOO", name="a/b"), "a/b")

    def test_valid_key_and_name_are_accepted(self):
        path = write_manifest(self.tmp / "module-manifest.local.json",
                              [entry("MODULE_FOO_2", name="mod-foo_2.x"), {"key": "MODULE_BAR", "ref": "v1"}])
        self.assertEqual(len(load_local_entries(path)), 2)


class LoadMergedManifestTest(unittest.TestCase):
    def test_reads_sibling_local_file(self):
        tmp = Path(tempfile.mkdtemp())
        manifest = write_manifest(tmp / "module-manifest.json", [entry("MODULE_A")])
        write_manifest(local_manifest_path(manifest), [entry("MODULE_MINE")])
        merged, warnings = load_merged_manifest(manifest)
        self.assertEqual([m["key"] for m in merged], ["MODULE_A", "MODULE_MINE"])
        self.assertEqual(warnings, [])

    def test_local_path_is_a_sibling(self):
        self.assertEqual(
            local_manifest_path(Path("/tmp/config/module-manifest.json")),
            Path("/tmp/config/module-manifest.local.json"),
        )


if __name__ == "__main__":
    unittest.main()

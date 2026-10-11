import json
import unittest
from collections import Counter
from pathlib import Path

from key_renames import DEFAULT_RENAMES_PATH, cumulative_map, load_rename_waves, read_schema
from module_sources import load_sources
from update_module_manifest import derive_key, github_full_name

ROOT = Path(__file__).resolve().parents[3]


class ManifestKeyInvariantsTest(unittest.TestCase):
    """Every manifest key follows the full derive_key rule, and every GitHub entry records a boolean ``fork``."""

    @classmethod
    def setUpClass(cls):
        cls.modules = json.loads((ROOT / "config" / "module-manifest.json").read_text())["modules"]
        cls.renames = cumulative_map(load_rename_waves(ROOT / DEFAULT_RENAMES_PATH))

    def test_every_github_key_follows_derive_key(self):
        sources = load_sources(str(ROOT / "config" / "module-sources.json"))
        taken_by = {
            e["key"]: github_full_name(e.get("repo", "")).lower()
            for e in self.modules
            if github_full_name(e.get("repo", ""))
        }
        checked = 0
        offenders = []
        for entry in self.modules:
            full = github_full_name(entry.get("repo", ""))
            if not full:
                continue
            owner, name = full.split("/", 1)
            others = {k: v for k, v in taken_by.items() if k != entry["key"]}
            expected = derive_key(name, owner, fork=bool(entry.get("fork")), fork_owners=sources.fork_owners, taken_by=others)
            checked += 1
            if entry["key"] != expected:
                offenders.append(f"{entry['key']} ({full}, fork={entry.get('fork')}) expected {expected}")
        self.assertGreater(checked, 0)
        self.assertEqual(offenders, [], "\n".join(offenders))

    def test_fork_field_is_a_boolean_on_every_github_entry_and_absent_elsewhere(self):
        bad = [e["key"] for e in self.modules if github_full_name(e.get("repo", "")) and not isinstance(e.get("fork"), bool)]
        self.assertEqual(bad, [], "GitHub entries without a boolean fork field")
        stray = [e["key"] for e in self.modules if not github_full_name(e.get("repo", "")) and "fork" in e]
        self.assertEqual(stray, [], "non-GitHub entries must not carry fork")

    def test_no_two_entries_share_a_repository(self):
        names = Counter(github_full_name(e.get("repo", "")).lower() for e in self.modules if github_full_name(e.get("repo", "")))
        self.assertEqual([n for n, c in names.items() if c > 1], [])

    def test_rename_map_old_keys_are_gone_and_new_keys_exist(self):
        # A map key that is also a map value (the 12 duplicate MODULE_MOD_* names) is
        # legitimately present: it now belongs to the original repo. Only pure old
        # keys must be absent.
        keys = {e["key"] for e in self.modules}
        pure_old = set(self.renames) - set(self.renames.values())
        self.assertEqual(sorted(pure_old & keys), [], "old keys still in the manifest")
        self.assertEqual(sorted(set(self.renames.values()) - keys), [], "renamed-to keys missing from the manifest")

    def test_catalogue_documents_are_at_the_latest_schema(self):
        latest = load_rename_waves(ROOT / DEFAULT_RENAMES_PATH)[-1].id
        manifest = json.loads((ROOT / "config" / "module-manifest.json").read_text())
        self.assertEqual(manifest.get("key_schema"), latest)
        for profile in sorted((ROOT / "config" / "module-profiles").glob("*.json")):
            self.assertEqual(json.loads(profile.read_text()).get("key_schema"), latest, profile.name)
        for name in (".env.template", ".env.prebuilt"):
            self.assertEqual(read_schema((ROOT / name).read_text()), latest, name)


if __name__ == "__main__":
    unittest.main()

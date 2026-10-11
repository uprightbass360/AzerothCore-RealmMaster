import json
import unittest
from collections import Counter
from pathlib import Path

from key_renames import DEFAULT_RENAMES_PATH, load_rename_map
from update_module_manifest import github_full_name, repo_name_to_key, sanitize_owner

ROOT = Path(__file__).resolve().parents[3]


class ManifestKeyInvariantsTest(unittest.TestCase):
    """Phase 1 form of the key rule. Phase 2 tightens this to the full derive_key
    assertion once every entry records ``fork``."""

    @classmethod
    def setUpClass(cls):
        cls.modules = json.loads((ROOT / "config" / "module-manifest.json").read_text())["modules"]
        cls.renames = load_rename_map(ROOT / DEFAULT_RENAMES_PATH)

    def test_every_github_key_is_bare_or_owner_suffixed_for_its_own_repo(self):
        offenders = []
        for entry in self.modules:
            full = github_full_name(entry.get("repo", ""))
            if not full:
                continue
            owner, name = full.split("/", 1)
            base = repo_name_to_key(name)
            if entry["key"] not in {base, f"{base}_{sanitize_owner(owner)}"}:
                offenders.append(f"{entry['key']} ({full}) expected {base} or {base}_{sanitize_owner(owner)}")
        self.assertEqual(offenders, [], "\n".join(offenders))

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


if __name__ == "__main__":
    unittest.main()

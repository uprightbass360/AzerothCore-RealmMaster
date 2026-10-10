"""The committed manifest must not contain any repo declined in config/module-sources.json.

Fails a hand edit that reintroduces a declined repo. Fix with:
    python3 scripts/python/update_module_manifest.py --sources-only
"""
import json
import unittest
from pathlib import Path

from module_sources import load_sources
from update_module_manifest import github_full_name

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "config" / "module-manifest.json"
SOURCES = ROOT / "config" / "module-sources.json"


class ManifestSourcesConsistencyTest(unittest.TestCase):
    def test_sources_file_parses(self):
        self.assertTrue(SOURCES.exists(), f"{SOURCES} is missing")
        load_sources(str(SOURCES))  # raises SourcesError on a bad file

    def test_no_declined_repo_in_manifest(self):
        sources = load_sources(str(SOURCES))
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        offenders = []
        for entry in manifest.get("modules", []):
            pattern = sources.is_declined(github_full_name(str(entry.get("repo", ""))))
            if pattern:
                offenders.append(f"{entry.get('key')} (declined by {pattern})")
        self.assertEqual(
            offenders, [],
            "Declined repos present in the manifest; run "
            "`python3 scripts/python/update_module_manifest.py --sources-only`:\n" + "\n".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()

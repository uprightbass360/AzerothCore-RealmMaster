"""review_stale_modules: find entries past the staleness window and decline them."""
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import date
from pathlib import Path
from unittest import mock

import review_stale_modules as rsm
from module_sources import Sources, load_sources
from tests.helpers import entry

TODAY = date(2026, 10, 10)          # cutoff with 1095 days: 2023-10-11
OLD = "2020-03-14T12:00:00Z"
RECENT = "2026-09-01T00:00:00Z"


class FakeClient:
    def __init__(self, answers: dict):
        self.answers = answers
        self.calls = []
        self.error_count = 0

    def check_repo(self, full_name: str):
        self.calls.append(full_name)
        return self.answers[full_name]


class ParseLastModifiedTest(unittest.TestCase):
    def test_iso_timestamp(self):
        self.assertEqual(rsm.parse_last_modified(OLD), date(2020, 3, 14))

    def test_bare_date(self):
        self.assertEqual(rsm.parse_last_modified("2021-01-02"), date(2021, 1, 2))

    def test_missing_or_garbage_is_none(self):
        for bad in (None, "", "yesterday", "2021-13-45T00:00:00Z", 12345):
            self.assertIsNone(rsm.parse_last_modified(bad), repr(bad))


class FindStaleTest(unittest.TestCase):
    def setUp(self):
        mock.patch.object(rsm.time, "sleep").start()
        self.addCleanup(mock.patch.stopall)

    def candidates(self, modules, sources=None, exempt=frozenset(), client=None):
        return rsm.find_stale_candidates({"modules": modules}, sources or Sources(), set(exempt), TODAY, client)

    def test_old_entry_is_flagged_with_date_reason(self):
        old = entry("MODULE_OLD", repo="https://github.com/acme/old.git", last_modified=OLD)
        found = self.candidates([old])
        self.assertEqual([(e["key"], name, reason) for e, name, reason in found],
                         [("MODULE_OLD", "acme/old", "no upstream activity since 2020-03-14")])

    def test_boundary_day_is_not_stale(self):
        edge = entry("MODULE_EDGE", repo="https://github.com/acme/edge.git", last_modified="2023-10-11T00:00:00Z")
        self.assertEqual(self.candidates([edge]), [])

    def test_recent_entry_is_not_flagged(self):
        self.assertEqual(self.candidates([entry("MODULE_NEW", last_modified=RECENT)]), [])

    def test_missing_or_bad_last_modified_is_skipped(self):
        self.assertEqual(self.candidates([entry("MODULE_A"), entry("MODULE_B", last_modified="n/a")]), [])

    def test_non_github_repo_is_skipped(self):
        gl = entry("MODULE_GL", repo="https://gitlab.com/acme/old.git", last_modified=OLD)
        self.assertEqual(self.candidates([gl]), [])

    def test_kept_declined_and_profile_entries_are_exempt(self):
        kept = entry("MODULE_KEPT", repo="https://github.com/acme/kept.git", last_modified=OLD)
        already = entry("MODULE_DECL", repo="https://github.com/bulk/x.git", last_modified=OLD)
        in_profile = entry("MODULE_PROF", repo="https://github.com/acme/prof.git", last_modified=OLD)
        sources = Sources(keep={"acme/kept"})
        sources.decline("bulk/*", "bulk", TODAY)
        self.assertEqual(self.candidates([kept, already, in_profile], sources, exempt={"MODULE_PROF"}), [])

    def test_archived_detection_only_for_entries_not_already_stale(self):
        old = entry("MODULE_OLD", repo="https://github.com/acme/old.git", last_modified=OLD)
        archived = entry("MODULE_ARC", repo="https://github.com/acme/arc.git", last_modified=RECENT)
        live = entry("MODULE_LIVE", repo="https://github.com/acme/live.git", last_modified=RECENT)
        gone = entry("MODULE_GONE", repo="https://github.com/acme/gone.git", last_modified=RECENT)
        client = FakeClient({
            "acme/arc": ("alive", {"archived": True}),
            "acme/live": ("alive", {"archived": False}),
            "acme/gone": ("dead", None),
        })
        found = self.candidates([old, archived, live, gone], client=client)
        self.assertEqual([(e["key"], reason) for e, _, reason in found],
                         [("MODULE_OLD", "no upstream activity since 2020-03-14"),
                          ("MODULE_ARC", "archived upstream")])
        self.assertEqual(sorted(client.calls), ["acme/arc", "acme/gone", "acme/live"])

    def test_without_client_no_archived_detection(self):
        archived = entry("MODULE_ARC", repo="https://github.com/acme/arc.git", last_modified=RECENT)
        self.assertEqual(self.candidates([archived]), [])


class FormatTableTest(unittest.TestCase):
    def test_table_layout(self):
        e = entry("MODULE_OLD", repo="https://github.com/acme/old.git", last_modified=OLD)
        text = rsm.format_table([(e, "acme/old", "no upstream activity since 2020-03-14")])
        self.assertEqual(text.splitlines(), [
            "| Key | Repository | Last push | Reason |",
            "|---|---|---|---|",
            "| `MODULE_OLD` | [acme/old](https://github.com/acme/old) | 2020-03-14 | no upstream activity since 2020-03-14 |",
        ])
        self.assertTrue(text.endswith("\n"))


class MainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.manifest = root / "module-manifest.json"
        self.sources = root / "module-sources.json"
        self.profiles = root / "profiles"
        self.profiles.mkdir()
        self.manifest.write_text(json.dumps({"modules": [
            entry("MODULE_OLD", repo="https://github.com/acme/old.git", last_modified=OLD),
            entry("MODULE_PROF", repo="https://github.com/acme/prof.git", last_modified=OLD),
            entry("MODULE_ALL", repo="https://github.com/acme/all.git", last_modified=OLD),
            entry("MODULE_NEW", repo="https://github.com/acme/new.git", last_modified=RECENT),
        ]}) + "\n")
        (self.profiles / "curated.json").write_text(json.dumps({"modules": ["MODULE_PROF"]}))
        (self.profiles / "all-modules.json").write_text(json.dumps({"modules": ["MODULE_ALL"]}))
        mock.patch.object(rsm.request, "urlopen", side_effect=AssertionError("network")).start()
        self.addCleanup(mock.patch.stopall)

    def run_main(self, *extra):
        argv = ["--manifest", str(self.manifest), "--sources", str(self.sources),
                "--profiles-dir", str(self.profiles), "--today", "2026-10-10", *extra]
        out = io.StringIO()
        with redirect_stdout(out):
            code = rsm.main(argv)
        return code, out.getvalue()

    def test_writes_declined_and_prints_table(self):
        code, out = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("| `MODULE_OLD` |", out)
        self.assertIn("| `MODULE_ALL` |", out)      # all-modules.json is not curation
        self.assertNotIn("MODULE_PROF", out)
        self.assertNotIn("MODULE_NEW", out)
        saved = load_sources(str(self.sources))
        self.assertEqual(set(saved.declined), {"acme/old", "acme/all"})
        self.assertEqual(saved.declined["acme/old"],
                         {"reason": "no upstream activity since 2020-03-14", "date": "2026-10-10"})

    def test_dry_run_prints_but_does_not_write(self):
        code, out = self.run_main("--dry-run")
        self.assertEqual(code, 0)
        self.assertIn("| `MODULE_OLD` |", out)
        self.assertFalse(self.sources.exists())

    def test_nothing_to_do_prints_nothing(self):
        self.manifest.write_text(json.dumps({"modules": [
            entry("MODULE_NEW", repo="https://github.com/acme/new.git", last_modified=RECENT)]}) + "\n")
        code, out = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(out, "")
        self.assertFalse(self.sources.exists())

    def test_api_errors_are_surfaced_in_table_and_as_warning(self):
        class ErroringClient:
            def __init__(self, *args, **kwargs):
                self.error_count = 0

            def check_repo(self, full_name):
                self.error_count += 1
                return ("error", None)

        err = io.StringIO()
        with mock.patch.object(rsm, "GitHubClient", ErroringClient), \
                mock.patch.object(rsm.time, "sleep"), redirect_stderr(err):
            code, out = self.run_main("--check-archived")
        self.assertEqual(code, 0)
        self.assertIn("| `MODULE_OLD` |", out)
        self.assertIn("1 GitHub API error(s); archived detection is incomplete", out)
        self.assertIn("::warning::", err.getvalue())

    def test_second_run_does_not_reflag(self):
        self.run_main()
        code, out = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(out, "")


if __name__ == "__main__":
    unittest.main()

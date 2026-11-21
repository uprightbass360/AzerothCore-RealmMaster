import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from run_log_writer import clean_line, load_secrets

WRITER = Path(__file__).resolve().parents[1] / "run_log_writer.py"


def wait_for_content(path, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.stat().st_size > 0:
            return
        time.sleep(0.02)
    raise AssertionError(f"{path} stayed empty")


class LoadSecretsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = self.tmp / ".env"

    def write_env(self, text):
        self.env.write_text(text)
        return load_secrets(self.env)

    def test_secret_names_are_matched_case_insensitively(self):
        secrets = self.write_env(
            "MYSQL_ROOT_PASSWORD=hunter22\nGH_TOKEN=tok-1234\nApi_Secret=s3cr3t!\n"
            "SSH_KEY=key-5678\nSERVER_ADDRESS=10.0.0.5\n"
        )
        self.assertEqual(set(secrets), {"hunter22", "tok-1234", "s3cr3t!", "key-5678"})

    def test_short_values_references_and_comments_are_skipped(self):
        secrets = self.write_env(
            "SHORT_TOKEN=abc\nREF_PASSWORD=${MYSQL_ROOT_PASSWORD}\n# OLD_PASSWORD=commented\nEMPTY_KEY=\n"
        )
        self.assertEqual(secrets, [])

    def test_quotes_and_export_are_handled(self):
        secrets = self.write_env("export DB_PASSWORD=\"quoted pw\"\nX_TOKEN='single'\n")
        self.assertEqual(set(secrets), {"quoted pw", "single"})

    def test_longest_first(self):
        secrets = self.write_env("A_PASSWORD=abcd\nB_PASSWORD=abcdefgh\n")
        self.assertEqual(secrets, ["abcdefgh", "abcd"])

    def test_inline_comment_after_an_unquoted_value_is_dropped(self):
        secrets = self.write_env("MYSQL_ROOT_PASSWORD=foo1234 # note\nB_PASSWORD=foo#bar9\n")
        self.assertEqual(set(secrets), {"foo1234", "foo#bar9"})

    def test_quoted_values_keep_everything_inside_the_quotes(self):
        secrets = self.write_env("A_PASSWORD=\"pa ss # in\" # note\nB_TOKEN='tok # x'\n")
        self.assertEqual(set(secrets), {"pa ss # in", "tok # x"})

    def test_missing_env_file(self):
        self.assertEqual(load_secrets(self.tmp / "nope.env"), [])


class CleanLineTest(unittest.TestCase):
    def test_ansi_codes_are_removed(self):
        self.assertEqual(clean_line("\x1b[0;32mok\x1b[0m done\n", []), "ok done")
        self.assertEqual(clean_line("\x1b[1;33m⚠️  warn\x1b[0m", []), "⚠️  warn")

    def test_carriage_return_keeps_the_final_state(self):
        self.assertEqual(clean_line("10%\r50%\r100%\n", []), "100%")
        self.assertEqual(clean_line("done\r\n", []), "done")

    def test_secrets_are_masked_everywhere_on_the_line(self):
        line = clean_line("mysql -phunter22 -e x; echo hunter22", ["hunter22"])
        self.assertEqual(line, "mysql -p*** -e x; echo ***")

    def test_overlapping_secrets_mask_the_longest(self):
        self.assertEqual(clean_line("pw=abcdefgh", ["abcdefgh", "abcd"]), "pw=***")

    def test_single_char_escapes_are_removed(self):
        self.assertEqual(clean_line("\x1bcreset", []), "reset")
        self.assertEqual(clean_line("a\x1b=b\x1b>c", []), "abc")

    def test_charset_designation_escapes_are_removed(self):
        self.assertEqual(clean_line("\x1b(Btext", []), "text")


class WriterProcessTest(unittest.TestCase):
    def test_appends_cleaned_lines_until_eof(self):
        tmp = Path(tempfile.mkdtemp())
        env = tmp / ".env"
        env.write_text("MYSQL_ROOT_PASSWORD=hunter22\n")
        log = tmp / "run.log"
        log.write_text("header\n")
        subprocess.run(
            [sys.executable, str(WRITER), str(log), str(env)],
            input="\x1b[0;32mone\x1b[0m\ntwo hunter22\nno newline at end",
            text=True, check=True,
        )
        self.assertEqual(log.read_text(), "header\none\ntwo ***\nno newline at end\n")

    def test_write_error_continues_without_log(self):
        tmp = Path(tempfile.mkdtemp())
        env = tmp / ".env"
        env.write_text("")
        # Path to log in non-existent parent directory
        log = tmp / "nonexistent" / "run.log"
        # Send enough data to exceed pipe buffer (200 KB)
        large_input = "x" * 200000 + "\n"
        result = subprocess.run(
            [sys.executable, str(WRITER), str(log), str(env)],
            input=large_input,
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("cannot write", result.stderr)
        self.assertIn(str(log), result.stderr)

    def test_secrets_written_to_env_during_the_run_are_masked_at_eof(self):
        tmp = Path(tempfile.mkdtemp())
        env = tmp / ".env"  # does not exist yet
        log = tmp / "run.log"
        log.write_text("")
        log.chmod(0o600)
        proc = subprocess.Popen(
            [sys.executable, str(WRITER), str(log), str(env)],
            stdin=subprocess.PIPE, text=True,
        )
        proc.stdin.write("Command:   setup --mysql-password Hunter2Secret\n")
        proc.stdin.write("Enter MySQL root password [Hunter2Secret]:\n")
        proc.stdin.flush()
        wait_for_content(log)  # the writer has read the (missing) .env by now
        env.write_text("MYSQL_ROOT_PASSWORD=Hunter2Secret\n")
        proc.stdin.write("done\n")
        proc.stdin.close()
        self.assertEqual(proc.wait(timeout=10), 0)
        text = log.read_text()
        self.assertNotIn("Hunter2Secret", text)
        self.assertIn("Enter MySQL root password [***]:", text)
        self.assertIn("done", text)
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertEqual([p.name for p in tmp.iterdir() if p.name not in (".env", "run.log")], [])

    def test_eof_remask_failure_is_tolerated(self):
        tmp = Path(tempfile.mkdtemp())
        env = tmp / ".env"
        log = tmp / "run.log"
        log.write_text("")
        proc = subprocess.Popen(
            [sys.executable, str(WRITER), str(log), str(env)],
            stdin=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        proc.stdin.write("pw Hunter2Secret\n")
        proc.stdin.flush()
        wait_for_content(log)
        env.write_text("MYSQL_ROOT_PASSWORD=Hunter2Secret\n")
        # The rewrite needs a temp file next to the log; make that impossible.
        tmp.chmod(0o500)
        try:
            _, err = proc.communicate("", timeout=10)
        finally:
            tmp.chmod(0o700)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(len(err.strip().splitlines()), 1)
        self.assertIn("run_log_writer:", err)

    def test_usage_error(self):
        result = subprocess.run([sys.executable, str(WRITER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

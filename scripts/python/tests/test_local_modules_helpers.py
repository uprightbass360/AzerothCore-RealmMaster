import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from local_modules import (
    ProbeError,
    normalize_repo,
    probe_clone,
    repo_basename,
    set_env_value,
    write_local_entries,
)
import local_modules

GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull)


def make_repo(root: Path, files: dict, branch: str = "main") -> Path:
    root.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", "-b", branch, str(root)], check=True, env=GIT_ENV)
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True, env=GIT_ENV)
    subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", "init"], check=True, env=GIT_ENV)
    return root


class NormalizeTest(unittest.TestCase):
    def test_normalize_repo_variants(self):
        variants = [
            "https://github.com/Foo/mod-bar.git",
            "https://github.com/foo/mod-bar",
            "https://github.com/foo/mod-bar/",
            "http://github.com/foo/mod-bar.git",
            "  https://GitHub.com/foo/mod-bar.git/ ",
        ]
        self.assertEqual(len({normalize_repo(v) for v in variants}), 1)

    def test_different_repos_differ(self):
        self.assertNotEqual(normalize_repo("https://github.com/a/x"), normalize_repo("https://github.com/b/x"))

    def test_repo_basename(self):
        self.assertEqual(repo_basename("https://gitlab.com/me/Mod-Thing.git/"), "Mod-Thing")
        self.assertEqual(repo_basename("/srv/git/lua-ah-bot"), "lua-ah-bot")


class EnvFileTest(unittest.TestCase):
    def setUp(self):
        self.env = Path(tempfile.mkdtemp()) / ".env"

    def test_creates_missing_file(self):
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X=1\n")

    def test_replaces_in_place(self):
        self.env.write_text("A=1\nMODULE_X=0\nB=2\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "A=1\nMODULE_X=1\nB=2\n")

    def test_appends_when_absent_without_trailing_newline(self):
        self.env.write_text("A=1")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "A=1\nMODULE_X=1\n")

    def test_export_prefix_and_duplicates(self):
        self.env.write_text("export MODULE_X=0\nA=1\nMODULE_X=0\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X=1\nA=1\n")

    def test_does_not_touch_similar_keys(self):
        self.env.write_text("MODULE_X_EXTRA=0\n")
        set_env_value(self.env, "MODULE_X", "1")
        self.assertEqual(self.env.read_text(), "MODULE_X_EXTRA=0\nMODULE_X=1\n")


class WriteLocalEntriesTest(unittest.TestCase):
    def test_atomic_write(self):
        path = Path(tempfile.mkdtemp()) / "config" / "module-manifest.local.json"
        write_local_entries(path, [{"key": "MODULE_X", "name": "x", "repo": "r"}])
        self.assertEqual(json.loads(path.read_text())["modules"][0]["key"], "MODULE_X")
        self.assertEqual([p.name for p in path.parent.iterdir()], ["module-manifest.local.json"])
        # Verify file is readable by all (0o644)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)


class ProbeCloneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.repo = make_repo(self.tmp / "src", {"a.lua": "print(1)"})
        subprocess.run(["git", "-C", str(self.repo), "tag", "v1"], check=True, env=GIT_ENV)

    def test_probe_clone_default_branch(self):
        probe_clone(str(self.repo), None, self.tmp / "out1")
        self.assertTrue((self.tmp / "out1" / "a.lua").exists())

    def test_probe_clone_tag(self):
        probe_clone(str(self.repo), "v1", self.tmp / "out2")
        self.assertTrue((self.tmp / "out2" / "a.lua").exists())

    def test_probe_clone_commit_sha(self):
        sha = subprocess.run(["git", "-C", str(self.repo), "rev-parse", "HEAD"], capture_output=True,
                             text=True, check=True).stdout.strip()
        probe_clone(str(self.repo), sha, self.tmp / "out3")
        head = subprocess.run(["git", "-C", str(self.tmp / "out3"), "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
        self.assertEqual(head, sha)

    def test_probe_clone_bad_url(self):
        with self.assertRaises(ProbeError):
            probe_clone(str(self.tmp / "does-not-exist"), None, self.tmp / "out4")

    def test_probe_clone_bad_ref(self):
        with self.assertRaises(ProbeError):
            probe_clone(str(self.repo), "no-such-ref", self.tmp / "out5")

    def test_probe_clone_timeout_raises_probe_error(self):
        def mock_run_timeout(*args, **kwargs):
            # Extract the git command list: args[0] = ["git", "clone", "--quiet", "--depth", "1", url, dest]
            cmd_list = args[0]
            if len(cmd_list) >= 7 and cmd_list[1] == "clone":
                dest_path = Path(cmd_list[-1])  # Last element is the destination
                dest_path.mkdir(parents=True, exist_ok=True)
                (dest_path / "file.txt").write_text("test")
            raise subprocess.TimeoutExpired(cmd="git", timeout=1)

        with mock.patch("subprocess.run", side_effect=mock_run_timeout):
            dest = self.tmp / "out_timeout"
            with self.assertRaises(ProbeError) as cm:
                probe_clone("https://example.com/repo.git", None, dest)
            self.assertIn("timed out", str(cm.exception))
            self.assertFalse(dest.exists(), "Destination directory should be cleaned up on timeout")

    def test_probe_clone_timeout_cleanup_on_full_clone(self):
        def mock_run_side_effect(*args, **kwargs):
            # First call (shallow clone): return error
            if len(mock_run_side_effect.calls) == 0:
                mock_run_side_effect.calls.append(1)
                return mock.MagicMock(returncode=1, stderr="fatal: error")
            # Second call (full clone): create dest and timeout
            cmd_list = args[0]
            if len(cmd_list) >= 4 and cmd_list[1] == "clone":
                dest_path = Path(cmd_list[-1])  # Last element is the destination
                dest_path.mkdir(parents=True, exist_ok=True)
                (dest_path / "file.txt").write_text("test")
            raise subprocess.TimeoutExpired(cmd="git", timeout=1)
        mock_run_side_effect.calls = []

        with mock.patch("subprocess.run", side_effect=mock_run_side_effect):
            dest = self.tmp / "out_timeout_full"
            with self.assertRaises(ProbeError):
                probe_clone("https://example.com/repo.git", "somehash", dest)
            self.assertFalse(dest.exists(), "Destination directory should be cleaned up on timeout during full clone")

    def test_git_ssh_command_is_batch_mode_by_default(self):
        # Ensure we're testing with clean environment (no ambient GIT_SSH_COMMAND)
        clean_env = dict(os.environ)
        clean_env.pop("GIT_SSH_COMMAND", None)

        with mock.patch.dict(os.environ, clean_env, clear=True):
            with mock.patch("subprocess.run") as mock_run:
                mock_run.return_value = mock.MagicMock(returncode=0)
                probe_clone(str(self.repo), None, self.tmp / "out_ssh_default")
                # Check that GIT_SSH_COMMAND is set to batch mode
                call_args = mock_run.call_args
                env = call_args.kwargs.get("env", {})
                self.assertEqual(env.get("GIT_SSH_COMMAND"), "ssh -o BatchMode=yes")

    def test_git_ssh_command_is_preserved_when_set(self):
        custom_ssh_cmd = "ssh -i /custom/key"
        with mock.patch.dict(os.environ, {"GIT_SSH_COMMAND": custom_ssh_cmd}):
            with mock.patch("subprocess.run") as mock_run:
                mock_run.return_value = mock.MagicMock(returncode=0)
                probe_clone(str(self.repo), None, self.tmp / "out_ssh_custom")
                # Check that GIT_SSH_COMMAND is preserved
                call_args = mock_run.call_args
                env = call_args.kwargs.get("env", {})
                self.assertEqual(env.get("GIT_SSH_COMMAND"), custom_ssh_cmd)


if __name__ == "__main__":
    unittest.main()

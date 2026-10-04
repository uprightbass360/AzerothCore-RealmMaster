import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from local_modules import main
from manifest_overlay import LOCAL_MANIFEST_NAME
from tests.helpers import entry, write_manifest
from tests.test_local_modules_helpers import make_repo


class CliCase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.repos = Path(tempfile.mkdtemp())
        (self.root / "config").mkdir()
        self.upstream_repo = "https://github.com/azerothcore/mod-up.git"
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
        ])
        (self.root / ".env").write_text("MODULE_ELUNA=1\n")

    def run_cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = main(["--root", str(self.root), *args])
        return rc, out.getvalue(), err.getvalue()

    def local_entries(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        return json.loads(path.read_text())["modules"] if path.exists() else []

    def env(self):
        return (self.root / ".env").read_text()


class AddTest(CliCase):
    def test_add_lua_module(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual((e["key"], e["name"], e["type"]), ("MODULE_LUA_THING", "lua-thing", "lua"))
        self.assertEqual(e["post_install_hooks"], ["copy-standard-lua"])
        self.assertEqual(e["requires"], ["MODULE_ELUNA"])
        self.assertIn("MODULE_LUA_THING=1", self.env())
        self.assertIn("run inside your worldserver", out)
        self.assertIn("./deploy.sh", out)

    def test_add_enables_requires(self):
        repo = make_repo(self.repos / "aio-thing", {"Server/s.lua": 'local AIO = require("AIO")'})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("MODULE_AIO=1", self.env())
        self.assertIn("MODULE_AIO", out)

    def test_add_cpp_says_build(self):
        repo = make_repo(self.repos / "mod-mine", {"src/l.cpp": "void Addmod_mineScripts(){}"})
        rc, out, _ = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("./build.sh", out)

    def test_add_no_enable(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        rc, _, _ = self.run_cli("add", str(repo), "--yes", "--no-enable")
        self.assertEqual(rc, 0)
        self.assertNotIn("MODULE_LUA_THING", self.env())

    def test_add_records_ref(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        import subprocess
        from tests.test_local_modules_helpers import GIT_ENV
        subprocess.run(["git", "-C", str(repo), "tag", "v2"], check=True, env=GIT_ENV)
        rc, _, _ = self.run_cli("add", str(repo), "--ref", "v2", "--yes")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries()[0]["ref"], "v2")

    def test_add_rejects_upstream_repo_with_git_suffix(self):
        rc, _, err = self.run_cli("add", "https://github.com/AzerothCore/mod-up/", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_UP=1", err)
        self.assertEqual(self.local_entries(), [])

    def test_add_rejects_upstream_repo_http_scheme_with_git_suffix(self):
        rc, _, err = self.run_cli("add", "http://github.com/AzerothCore/mod-up.git", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_UP=1", err)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_add_twice_same_url_is_rejected(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        self.assertEqual(self.run_cli("add", str(repo), "--yes")[0], 0)
        rc, _, err = self.run_cli("add", str(repo) + "/", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_LUA_THING", err)
        self.assertEqual(len(self.local_entries()), 1)

    def test_add_key_collision_needs_explicit_key(self):
        repo = make_repo(self.repos / "mod-up", {"thing.lua": ""})  # derives MODULE_MOD_UP; force a clash:
        write_manifest(self.root / "config" / "module-manifest.json",
                       [entry("MODULE_MOD_UP", name="mod-up-other", repo="https://example.com/other.git")])
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--key", err)

    def test_add_same_folder_name_needs_explicit_key(self):
        # Folder name "mod-playerbots" already matches the upstream MODULE_PLAYERBOTS
        # entry's "name", even though the derived key would differ.
        repo = make_repo(self.repos / "mod-playerbots", {"README.md": "x"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--key MODULE_PLAYERBOTS", err)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_add_same_folder_new_key_still_refused(self):
        # Even with an explicit --key, a *different* key targeting a folder that's
        # already listed would clone a second module into the same folder.
        repo = make_repo(self.repos / "mod-playerbots", {"README.md": "x"})
        rc, _, err = self.run_cli("add", str(repo), "--key", "MODULE_MY_BOTS", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--key MODULE_PLAYERBOTS", err)
        self.assertEqual(self.local_entries(), [])

    def _write_transmog_manifest(self):
        # Two upstream entries legitimately share the "mod-transmog" folder name
        # (a fork listed alongside the original) -- the real manifest has 17 such
        # pairs. Overriding either existing key must not trip the folder guard.
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
            entry("MODULE_TRANSMOG", name="mod-transmog",
                  repo="https://github.com/example/mod-transmog.git", type="cpp"),
            entry("MODULE_MOD_TRANSMOG", name="mod-transmog",
                  repo="https://github.com/example/mod-transmog-fork.git", type="cpp"),
        ])

    def test_fork_override_of_second_entry_sharing_a_folder(self):
        self._write_transmog_manifest()
        fork = make_repo(self.repos / "mod-transmog", {"src/l.cpp": "void Addmod_transmogScripts(){}"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_MOD_TRANSMOG", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual(e["key"], "MODULE_MOD_TRANSMOG")

    def test_fork_override_of_first_entry_sharing_a_folder(self):
        self._write_transmog_manifest()
        fork = make_repo(self.repos / "mod-transmog", {"src/l.cpp": "void Addmod_transmogScripts(){}"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_TRANSMOG", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual(e["key"], "MODULE_TRANSMOG")

    def test_fork_new_key_sharing_a_listed_folder_is_refused(self):
        self._write_transmog_manifest()
        fork = make_repo(self.repos / "mod-transmog", {"src/l.cpp": "void Addmod_transmogScripts(){}"})
        rc, _, err = self.run_cli("add", str(fork), "--key", "MODULE_NEW_TRANSMOG", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--key MODULE_TRANSMOG", err)
        self.assertEqual(self.local_entries(), [])

    def test_add_collection_refused_without_type(self):
        files = {f"s{i}.lua": "" for i in range(25)}
        repo = make_repo(self.repos / "scripts", files)
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--type lua", err)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_add_collection_with_type_lua(self):
        files = {f"s{i}.lua": "" for i in range(25)}
        repo = make_repo(self.repos / "scripts", files)
        rc, _, _ = self.run_cli("add", str(repo), "--type", "lua", "--yes")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries()[0]["post_install_hooks"], ["copy-standard-lua"])

    def test_add_undetectable_refused(self):
        repo = make_repo(self.repos / "tool", {"README.md": "x"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("--type", err)

    def test_add_bad_url_writes_nothing(self):
        rc, _, err = self.run_cli("add", str(self.repos / "missing"), "--yes")
        self.assertEqual(rc, 1)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_add_refuses_when_local_file_is_invalid(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        path.write_text("{broken")
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn(LOCAL_MANIFEST_NAME, err)
        self.assertEqual(path.read_text(), "{broken")

    def test_ref_only_override(self):
        rc, out, _ = self.run_cli("add", "--key", "MODULE_UP", "--ref", "v1.2", "--yes")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.local_entries(), [{"key": "MODULE_UP", "ref": "v1.2"}])
        self.assertIn("MODULE_UP=1", self.env())
        self.assertIn("run inside your worldserver", out)
        self.assertIn("./build.sh --force", out)

    def test_ref_only_override_no_enable(self):
        rc, _, _ = self.run_cli("add", "--key", "MODULE_UP", "--ref", "v1.2", "--yes", "--no-enable")
        self.assertEqual(rc, 0)
        self.assertNotIn("MODULE_UP", self.env())

    def test_fork_override(self):
        fork = make_repo(self.repos / "mod-up", {"src/l.cpp": "void Addmod_upScripts(){}"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual((e["key"], e["repo"]), ("MODULE_UP", str(fork)))
        self.assertNotIn("description", e)

    def test_fork_override_uses_listed_type_and_requires(self):
        # MODULE_UP is upstream cpp with a requires; the fork's content looks like
        # AIO Lua, but that's advisory only -- the listed entry's type/requires win.
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream",
                  requires=["MODULE_PLAYERBOTS"]),
        ])
        fork = make_repo(self.repos / "mod-up", {"Server/s.lua": 'local AIO = require("AIO")'})
        rc, out, err = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual(e["repo"], str(fork))
        self.assertNotIn("type", e)
        self.assertNotIn("requires", e)
        self.assertNotIn("post_install_hooks", e)
        self.assertNotIn("MODULE_AIO", self.env())
        self.assertIn("MODULE_PLAYERBOTS=1", self.env())
        self.assertIn("./build.sh --force", out)
        self.assertIn("WARNING", err)

    def test_fork_override_detection_finds_nothing_still_ok(self):
        fork = make_repo(self.repos / "mod-up", {"README.md": "x"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual(e["repo"], str(fork))

    def test_fork_override_type_flag_is_ignored_with_warning(self):
        fork = make_repo(self.repos / "mod-up", {"src/l.cpp": "void Addmod_upScripts(){}"})
        rc, _, err = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--type", "lua", "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("ignored", err)

    def test_ref_only_override_type_flag_is_ignored_with_warning(self):
        rc, _, err = self.run_cli("add", "--key", "MODULE_UP", "--ref", "v1", "--type", "lua", "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("ignored", err)
        [e] = self.local_entries()
        self.assertEqual(e, {"key": "MODULE_UP", "ref": "v1"})

    def test_refork_keeps_existing_override_fields(self):
        self.assertEqual(self.run_cli("add", "--key", "MODULE_UP", "--ref", "v1", "--yes")[0], 0)
        fork = make_repo(self.repos / "mod-up", {"src/l.cpp": "void Addmod_upScripts(){}"})
        rc, _, _ = self.run_cli("add", str(fork), "--key", "MODULE_UP", "--yes")
        self.assertEqual(rc, 0)
        [e] = self.local_entries()
        self.assertEqual(e, {"key": "MODULE_UP", "ref": "v1", "repo": str(fork)})

    def test_unrelated_manifest_errors_do_not_block(self):
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
            entry("MODULE_BROKEN", name="mod-broken", type="cpp", requires=["MODULE_GHOST"]),
        ])
        (self.root / ".env").write_text("MODULE_ELUNA=1\nMODULE_BROKEN=1\n")
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("WARNING", err)

    def test_unrelated_error_from_key_sharing_a_prefix_does_not_block(self):
        # MODULE_ELUNA_TS shares the "MODULE_ELUNA" prefix with the module our add
        # requires; a substring match would misfire on its unrelated error.
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_ELUNA_TS", name="mod-eluna-ts", type="cpp", requires=["MODULE_GHOST"]),
            entry("MODULE_AIO", name="mod-aio", type="lua"),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
        ])
        (self.root / ".env").write_text("MODULE_ELUNA=1\nMODULE_ELUNA_TS=1\n")
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0)
        self.assertIn("WARNING", err)
        self.assertIn("MODULE_ELUNA_TS", err)

    def test_no_enable_excludes_requires_from_error_relevance(self):
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua", requires=["MODULE_MISSING"]),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
        ])
        (self.root / ".env").write_text("MODULE_ELUNA=1\nMODULE_AIO=1\n")
        repo = make_repo(self.repos / "aio-thing", {"Server/s.lua": 'local AIO = require("AIO")'})
        rc, _, err = self.run_cli("add", str(repo), "--yes", "--no-enable")
        self.assertEqual(rc, 0)
        self.assertIn("WARNING", err)
        self.assertNotIn("MODULE_AIO_THING=1", self.env())

    def test_blocking_error_from_enabled_requirement_keeps_entry_and_reports_removal(self):
        write_manifest(self.root / "config" / "module-manifest.json", [
            entry("MODULE_ELUNA", name="mod-ale", type="cpp"),
            entry("MODULE_AIO", name="mod-aio", type="lua", requires=["MODULE_MISSING"]),
            entry("MODULE_PLAYERBOTS", name="mod-playerbots", type="cpp"),
            entry("MODULE_UP", name="mod-up", repo=self.upstream_repo, type="cpp", description="upstream"),
        ])
        repo = make_repo(self.repos / "aio-thing", {"Server/s.lua": 'local AIO = require("AIO")'})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_AIO", err)
        self.assertIn("./modules.sh remove", err)
        self.assertEqual(len(self.local_entries()), 1)

    def test_add_bad_key_refused(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        for bad in ("MODULE_FOO $(id)", "mod_foo", "MODULE_"):
            rc, _, err = self.run_cli("add", str(repo), "--key", bad, "--yes")
            self.assertEqual(rc, 1, bad)
            self.assertIn("capitals, digits and underscores", err)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_add_url_with_invalid_folder_name_refused(self):
        repo = make_repo(self.repos / "bad name", {"thing.lua": ""})
        rc, _, err = self.run_cli("add", str(repo), "--key", "MODULE_BAD_NAME", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("bad name", err)
        self.assertEqual(self.local_entries(), [])
        self.assertEqual(self.env(), "MODULE_ELUNA=1\n")

    def test_ref_starting_with_dash_refused(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        from unittest import mock
        import local_modules
        with mock.patch.object(local_modules, "_git") as git:
            rc, _, err = self.run_cli("add", str(repo), "--ref=-x", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("-x", err)
        git.assert_not_called()
        self.assertEqual(self.local_entries(), [])

    def test_clone_args_end_options_before_url(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        import local_modules
        calls = []
        real_git = local_modules._git

        def spy(args, url=None):
            calls.append(args)
            return real_git(args, url=url)

        from unittest import mock
        with mock.patch.object(local_modules, "_git", side_effect=spy):
            self.assertEqual(self.run_cli("add", str(repo), "--yes")[0], 0)
        clones = [c for c in calls if c[0] == "clone"]
        self.assertTrue(clones)
        for c in clones:
            self.assertEqual(c[-3], "--", c)

    def test_missing_upstream_manifest_refused(self):
        (self.root / "config" / "module-manifest.json").unlink()
        rc, _, err = self.run_cli("list")
        self.assertEqual(rc, 1)
        self.assertIn("module-manifest.json", err)

    def test_corrupt_upstream_manifest_refused(self):
        (self.root / "config" / "module-manifest.json").write_text("{broken")
        rc, _, err = self.run_cli("list")
        self.assertEqual(rc, 1)
        self.assertIn("module-manifest.json", err)

    def test_declined_prompt_writes_nothing(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": ""})
        import builtins
        from unittest import mock
        with mock.patch.object(builtins, "input", return_value="n"):
            rc, _, err = self.run_cli("add", str(repo))
        self.assertEqual(rc, 1)
        self.assertEqual(self.local_entries(), [])
        self.assertIn("Nothing written. (Use --yes", err)


class ListRemoveTest(CliCase):
    def seed(self, entries, env="MODULE_ELUNA=1\n"):
        write_manifest(self.root / "config" / LOCAL_MANIFEST_NAME, entries)
        (self.root / ".env").write_text(env)

    def test_list_shows_kinds_and_enabled(self):
        self.seed([entry("MODULE_MINE", name="mine", repo="https://x/mine.git"),
                   {"key": "MODULE_UP", "ref": "v1"},
                   {"key": "MODULE_GONE", "ref": "v1"}], env="MODULE_MINE=1\n")
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        lines = {line.split()[0]: line.split() for line in out.strip().splitlines()[1:]}
        self.assertEqual(lines["MODULE_MINE"][1:3], ["added", "yes"])
        self.assertEqual(lines["MODULE_UP"][1], "override")
        self.assertEqual(lines["MODULE_GONE"][1], "orphaned")

    def test_list_empty(self):
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        self.assertIn("No user-defined modules", out)

    def test_remove_local_module_leaves_tombstone_and_disables_it(self):
        mine = entry("MODULE_MINE", name="mine", type="lua", post_install_hooks=["copy-standard-lua"])
        self.seed([mine], env="MODULE_MINE=1\nA=1\n")
        rc, out, _ = self.run_cli("remove", "MODULE_MINE")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries(), [{
            "key": "MODULE_MINE", "name": "mine", "repo": mine["repo"],
            "status": "blocked", "block_reason": "removed with ./modules.sh remove",
        }])
        self.assertIn("MODULE_MINE=0", self.env())
        self.assertIn("A=1", self.env())
        self.assertIn("stays in the database", out)
        self.assertIn("disabled marker", out)

    def test_list_shows_removed_tombstone(self):
        self.seed([entry("MODULE_MINE", name="mine")], env="MODULE_MINE=1\n")
        self.assertEqual(self.run_cli("remove", "MODULE_MINE")[0], 0)
        rc, out, _ = self.run_cli("list")
        self.assertEqual(rc, 0)
        lines = {line.split()[0]: line.split() for line in out.strip().splitlines()[1:]}
        self.assertEqual(lines["MODULE_MINE"][1:3], ["removed", "no"])

    def test_remove_twice_refused(self):
        self.seed([entry("MODULE_MINE", name="mine")], env="MODULE_MINE=1\n")
        self.assertEqual(self.run_cli("remove", "MODULE_MINE")[0], 0)
        before = self.local_entries()
        rc, _, err = self.run_cli("remove", "MODULE_MINE")
        self.assertEqual(rc, 1)
        self.assertIn("already removed", err)
        self.assertEqual(self.local_entries(), before)

    def test_add_same_url_after_remove_replaces_tombstone(self):
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        self.assertEqual(self.run_cli("add", str(repo), "--yes")[0], 0)
        self.assertEqual(self.run_cli("remove", "MODULE_LUA_THING")[0], 0)
        self.assertIn("MODULE_LUA_THING=0", self.env())
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0, err)
        [e] = self.local_entries()
        self.assertEqual(e["key"], "MODULE_LUA_THING")
        self.assertNotIn("status", e)
        self.assertEqual(e["type"], "lua")
        self.assertIn("MODULE_LUA_THING=1", self.env())
        self.assertNotIn("MODULE_LUA_THING=0", self.env())

    def test_add_new_url_with_tombstoned_key_replaces_tombstone(self):
        self.seed([entry("MODULE_LUA_THING", name="old-thing")], env="MODULE_LUA_THING=1\n")
        self.assertEqual(self.run_cli("remove", "MODULE_LUA_THING")[0], 0)
        repo = make_repo(self.repos / "lua-thing", {"thing.lua": "print(1)"})
        rc, _, err = self.run_cli("add", str(repo), "--yes")
        self.assertEqual(rc, 0, err)
        [e] = self.local_entries()
        self.assertEqual((e["key"], e["name"], e["repo"]), ("MODULE_LUA_THING", "lua-thing", str(repo)))
        self.assertIn("MODULE_LUA_THING=1", self.env())

    def test_pin_of_tombstone_refused(self):
        self.seed([entry("MODULE_MINE", name="mine")], env="MODULE_MINE=1\n")
        self.assertEqual(self.run_cli("remove", "MODULE_MINE")[0], 0)
        before = self.local_entries()
        rc, _, err = self.run_cli("add", "--key", "MODULE_MINE", "--ref", "v1", "--yes")
        self.assertEqual(rc, 1)
        self.assertIn("was removed", err)
        self.assertEqual(self.local_entries(), before)

    def test_remove_override_keeps_env(self):
        self.seed([{"key": "MODULE_UP", "ref": "v1"}], env="MODULE_UP=1\n")
        rc, out, _ = self.run_cli("remove", "MODULE_UP")
        self.assertEqual(rc, 0)
        self.assertEqual(self.local_entries(), [])
        self.assertIn("MODULE_UP=1", self.env())
        self.assertIn("upstream", out)

    def test_remove_unknown_key(self):
        rc, _, err = self.run_cli("remove", "MODULE_NOPE")
        self.assertEqual(rc, 1)
        self.assertIn("MODULE_NOPE", err)

    def test_remove_refuses_invalid_local_file(self):
        path = self.root / "config" / LOCAL_MANIFEST_NAME
        path.write_text("{broken")
        rc, _, err = self.run_cli("remove", "MODULE_X")
        self.assertEqual(rc, 1)
        self.assertEqual(path.read_text(), "{broken")


if __name__ == "__main__":
    unittest.main()

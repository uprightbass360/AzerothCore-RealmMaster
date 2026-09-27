import tempfile
import unittest
from pathlib import Path

from module_detect import COLLECTION_FILE_THRESHOLD, detect


def make(root: Path, files: dict) -> Path:
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    return root


class DetectTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def mod(self, files):
        return make(self.tmp / "mod", files)

    # C++
    def test_cpp_with_matching_loader(self):
        d = detect(self.mod({"src/loader.cpp": "void Addmod_fooScripts() {}"}), "mod-foo")
        self.assertEqual(d.module_type, "cpp")
        self.assertEqual(d.warnings, [])

    def test_cpp_loader_mismatch_warns(self):
        d = detect(self.mod({"src/x.cpp": "void AddFooScripts() {}"}), "mod-foo")
        self.assertEqual(d.module_type, "cpp")
        self.assertTrue(any("Addmod_fooScripts" in w for w in d.warnings))

    def test_cpp_no_loader_warns(self):
        d = detect(self.mod({"src/x.h": "// nothing"}), "mod-foo")
        self.assertTrue(any("Addmod_fooScripts" in w for w in d.warnings))

    def test_cpp_playerbots_dependency(self):
        d = detect(self.mod({"src/x.cpp": '#include "Playerbots.h"\nvoid Addmod_fooScripts(){}'}), "mod-foo")
        self.assertIn("MODULE_PLAYERBOTS", d.requires)

    def test_cpp_stray_sql_warns(self):
        d = detect(self.mod({"src/x.cpp": "void Addmod_fooScripts(){}", "sql/world.sql": "SELECT 1;"}), "mod-foo")
        self.assertTrue(any("sql/world.sql" in w for w in d.warnings))

    def test_cpp_sql_in_staged_dirs_is_quiet(self):
        d = detect(self.mod({"src/x.cpp": "void Addmod_fooScripts(){}",
                             "data/sql/db-world/a.sql": "SELECT 1;",
                             "data/sql/db-characters/updates/b.sql": "SELECT 1;",
                             "data/sql/world/base/c.sql": "SELECT 1;"}), "mod-foo")
        self.assertEqual(d.warnings, [])

    # Lua
    def test_lua_standard(self):
        d = detect(self.mod({"script.lua": "print(1)"}), "lua-thing")
        self.assertEqual((d.module_type, d.post_install_hooks, d.requires), ("lua", ["copy-standard-lua"], ["MODULE_ELUNA"]))

    def test_lua_aio(self):
        d = detect(self.mod({"Server/s.lua": 'local AIO = AIO or require("AIO")'}), "aio-thing")
        self.assertEqual((d.post_install_hooks, d.requires), (["copy-aio-lua"], ["MODULE_AIO"]))

    def test_lua_require_from_subfolder_uses_tree(self):
        d = detect(self.mod({"Bot.lua": 'local E = require("EnchantmentModule")',
                             "Bot/EnchantmentModule.lua": "return {}"}), "lua-bot")
        self.assertEqual(d.post_install_hooks, ["copy-lua-tree"])

    def test_lua_only_in_subfolder_uses_tree(self):
        d = detect(self.mod({"thing/Main.lua": "print(1)"}), "lua-thing")
        self.assertEqual(d.post_install_hooks, ["copy-lua-tree"])

    def test_lua_collection_by_count(self):
        files = {f"s{i}.lua": "print(1)" for i in range(COLLECTION_FILE_THRESHOLD + 1)}
        d = detect(self.mod(files), "scripts")
        self.assertTrue(d.is_collection)

    def test_lua_collection_by_folders(self):
        d = detect(self.mod({"A/a.lua": "", "B/b.lua": "", "C/c.lua": ""}), "scripts")
        self.assertTrue(d.is_collection)

    def test_git_dir_is_ignored(self):
        d = detect(self.mod({".git/hooks/x.lua": "", "main.lua": ""}), "lua-thing")
        self.assertEqual(d.post_install_hooks, ["copy-standard-lua"])

    # SQL / other
    def test_sql_only(self):
        d = detect(self.mod({"data/sql/db-world/a.sql": "SELECT 1;"}), "sql-thing")
        self.assertEqual((d.module_type, d.post_install_hooks), ("sql", []))

    def test_nothing_recognisable(self):
        d = detect(self.mod({"README.md": "hi", "tool.py": ""}), "tool")
        self.assertIsNone(d.module_type)
        self.assertIn("no src/", d.reason)


if __name__ == "__main__":
    unittest.main()

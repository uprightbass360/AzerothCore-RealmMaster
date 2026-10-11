import unittest

from update_module_manifest import derive_key, sanitize_owner

EXEMPT = {"azerothcore"}


class SanitizeOwnerTest(unittest.TestCase):
    def test_non_alphanumerics_collapse_to_underscore_and_upper(self):
        self.assertEqual(sanitize_owner("valsan-azerty-boi"), "VALSAN_AZERTY_BOI")
        self.assertEqual(sanitize_owner("Brian-Aldridge"), "BRIAN_ALDRIDGE")
        self.assertEqual(sanitize_owner("TerraByte-tbwps"), "TERRABYTE_TBWPS")


class DeriveKeyTest(unittest.TestCase):
    def test_non_fork_with_free_key_gets_bare_key(self):
        key = derive_key("mod-aoe-loot", "azerothcore", fork=False, fork_owners=EXEMPT, taken_by={})
        self.assertEqual(key, "MODULE_MOD_AOE_LOOT")

    def test_third_party_fork_gets_owner_suffix(self):
        key = derive_key("mod-playerbots", "maluramichael", fork=True, fork_owners=EXEMPT, taken_by={})
        self.assertEqual(key, "MODULE_MOD_PLAYERBOTS_MALURAMICHAEL")

    def test_exempt_owner_fork_keeps_bare_key_case_insensitively(self):
        key = derive_key("mod-guildhouse", "AzerothCore", fork=True, fork_owners=EXEMPT, taken_by={})
        self.assertEqual(key, "MODULE_MOD_GUILDHOUSE")

    def test_non_fork_whose_key_is_held_by_another_repo_gets_suffix(self):
        taken = {"MODULE_MOD_AOE_LOOT": "azerothcore/mod-aoe-loot"}
        key = derive_key("mod-aoe-loot", "TerraByte-tbwps", fork=False, fork_owners=EXEMPT, taken_by=taken)
        self.assertEqual(key, "MODULE_MOD_AOE_LOOT_TERRABYTE_TBWPS")

    def test_same_repo_rederives_its_bare_key(self):
        taken = {"MODULE_MOD_AOE_LOOT": "azerothcore/mod-aoe-loot"}
        key = derive_key("mod-aoe-loot", "AzerothCore", fork=False, fork_owners=EXEMPT, taken_by=taken)
        self.assertEqual(key, "MODULE_MOD_AOE_LOOT")

    def test_exempt_owner_still_gets_collision_suffix(self):
        taken = {"MODULE_MOD_PTR_TEMPLATE": "heyitsbench/mod-ptr-template"}
        key = derive_key("mod-ptr-template", "azerothcore", fork=True, fork_owners=EXEMPT, taken_by=taken)
        self.assertEqual(key, "MODULE_MOD_PTR_TEMPLATE_AZEROTHCORE")

    def test_sanitised_key_collision_is_detected(self):
        taken = {"MODULE_MOD_REWARD_SHOP": "azerothcore/mod-reward-shop"}
        key = derive_key("mod_reward_shop", "talamortis", fork=False, fork_owners=EXEMPT, taken_by=taken)
        self.assertEqual(key, "MODULE_MOD_REWARD_SHOP_TALAMORTIS")


if __name__ == "__main__":
    unittest.main()

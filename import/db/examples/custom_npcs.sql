-- Example: Add a custom NPC vendor
-- This file demonstrates how to add a custom NPC to your world database

-- Add the NPC template
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `scale`, `unit_class`, `unit_flags`, `type`, `type_flags`, `InhabitType`, `RegenHealth`, `flags_extra`, `ScriptName`) 
VALUES 
(900000, 'Custom Vendor', 'Example NPC', 80, 80, 35, 128, 1, 1, 0, 7, 0, 3, 1, 2, '');

-- Add the NPC spawn location (Stormwind Trade District)
INSERT INTO `creature` (`guid`, `id1`, `map`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `MovementType`) 
VALUES 
(900000, 900000, 0, -8833.38, 628.628, 94.0066, 0.715585, 300, 0);

-- Add some items to sell (optional)
-- INSERT INTO `npc_vendor` (`entry`, `item`, `maxcount`, `incrtime`, `ExtendedCost`)
-- VALUES 
-- (900000, 2901, 0, 0, 0),  -- Mining Pick
-- (900000, 5956, 0, 0, 0);  -- Blacksmith Hammer

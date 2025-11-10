-- Replace Eye of the Storm Envoys and spawn all custom NPCs in Silvermoon Walk of Elders District
-- Base location: x:~9514, y:~-7300, z:~14.5
-- Map: 530 (Outland), Zone: 3487 (Eversong Woods), Area: 3431 (Silvermoon City)

-- Remove the existing Eye of the Storm Envoys (already done, but included for completeness)
DELETE FROM creature WHERE guid IN (208304, 208305);

-- Core Service NPCs (Central placement)
-- Kaylub - Free Professions (replaces first envoy)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(208304, 199999, 0, 0, 530, 3487, 3431, 1, 1, 0, 9513.94, -7302.81, 14.5485, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Kaylub - Free Professions - Walk of Elders');

-- Beauregard Boneglitter - Enchanter (replaces second envoy)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(208305, 601015, 0, 0, 530, 3487, 3431, 1, 1, 1, 9514.06, -7298.59, 14.5415, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Beauregard Boneglitter - Enchanter - Walk of Elders');

-- Enhancement & Utility NPCs (Arranged in a circle around the center)
-- Buffmaster Hasselhoof - Buffer (North)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999911, 601016, 0, 0, 530, 3487, 3431, 1, 1, 1, 9514.0, -7295.0, 14.5, 4.71, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Buffmaster Hasselhoof - Buffer - Walk of Elders');

-- White Fang - BeastMaster (Northeast)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999912, 601026, 0, 0, 530, 3487, 3431, 1, 1, 1, 9518.0, -7297.0, 14.5, 3.93, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'White Fang - BeastMaster - Walk of Elders');

-- Cet Keres - Polymorphologist (East)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999913, 601072, 0, 0, 530, 3487, 3431, 1, 1, 0, 9519.0, -7300.5, 14.5, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Cet Keres - Polymorphologist - Walk of Elders');

-- Transmog NPCs (Southeast)
-- Warpweaver - Transmogrifier
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999914, 190010, 0, 0, 530, 3487, 3431, 1, 1, 0, 9518.0, -7304.0, 14.5, 2.36, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Warpweaver - Transmogrifier - Walk of Elders');

-- Ethereal Warpweaver - Transmogrifier (South)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999915, 190011, 0, 0, 530, 3487, 3431, 1, 1, 0, 9514.0, -7306.0, 14.5, 1.57, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Ethereal Warpweaver - Transmogrifier - Walk of Elders');

-- Utility NPCs (Southwest)
-- Ling - Reagent Banker
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999916, 290011, 0, 0, 530, 3487, 3431, 1, 1, 0, 9510.0, -7304.0, 14.5, 0.79, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Ling - Reagent Banker - Walk of Elders');

-- Cromi - Instance Reset (West)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999917, 300000, 0, 0, 530, 3487, 3431, 1, 1, 0, 9509.0, -7300.5, 14.5, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Cromi - Instance Reset - Walk of Elders');

-- PvP & Arena NPC (Northwest)
-- Arena Battlemaster 1v1
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999918, 999991, 0, 0, 530, 3487, 3431, 1, 1, 0, 9510.0, -7297.0, 14.5, 5.50, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Arena Battlemaster 1v1 - Arena - Walk of Elders');

-- Assistant NPC (Center-North)
-- Gabriella - The Assistant
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999919, 9000000, 0, 0, 530, 3487, 3431, 1, 1, 0, 9514.0, -7292.0, 14.5, 4.71, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Gabriella - The Assistant - Walk of Elders');

-- Guild House NPCs (Outer ring - slightly further from center)
-- Talamortis - Guild House Seller (Far East)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999920, 500030, 0, 0, 530, 3487, 3431, 1, 1, 0, 9522.0, -7300.5, 14.5, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Talamortis - Guild House Seller - Walk of Elders');

-- Xrispins - Guild House Butler (Far South)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999921, 500031, 0, 0, 530, 3487, 3431, 1, 1, 0, 9514.0, -7310.0, 14.5, 1.57, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Xrispins - Guild House Butler - Walk of Elders');

-- Innkeeper Monica - Guild House Innkeeper (Far West)
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999922, 500032, 0, 0, 530, 3487, 3431, 1, 1, 0, 9506.0, -7300.5, 14.5, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Innkeeper Monica - Guild House Innkeeper - Walk of Elders');

-- Reload creatures to apply changes
-- Execute in-game: .reload creature
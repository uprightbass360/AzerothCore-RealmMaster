-- Replace Eye of the Storm Envoys in Silvermoon Walk of Elders District
-- with Custom NPCs from AzerothCore modules

-- Remove existing Eye of the Storm Envoy spawns in likely Walk of Elders area
-- Based on coordinates, these appear to be in central Silvermoon districts

-- Delete Eye of the Storm Envoys that appear to be in pairs in central areas
DELETE FROM creature WHERE id1 = 22015 AND map = 530 AND
  ((position_x BETWEEN -1670 AND -1665 AND position_y BETWEEN 5188 AND 5193) OR
   (position_x BETWEEN -1870 AND -1865 AND position_y BETWEEN 5144 AND 5150));

-- Add Kaylub (Professions NPC) - First location in central area
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999901, 199999, 0, 0, 530, 3487, 3487, 1, 1, 0, -1668.0, 5190.0, -42.0, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Kaylub - Free Professions NPC - Silvermoon Walk of Elders');

-- Add Beauregard Boneglitter (Enchanter) - Second location in central area
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(999902, 601015, 0, 0, 530, 3487, 3487, 1, 1, 1, -1866.5, 5146.5, -42.8, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Beauregard Boneglitter - Enchanter - Silvermoon Walk of Elders');

-- Alternative: If you want different NPCs, uncomment these and comment out above

-- Add White Fang (BeastMaster) instead of Kaylub
-- INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
-- (999901, 601026, 0, 0, 530, 3487, 3487, 1, 1, 1, -1668.0, 5190.0, -42.0, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'White Fang - BeastMaster - Silvermoon Walk of Elders');

-- Add Buffmaster Hasselhoof (Buffer) instead of Beauregard
-- INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
-- (999902, 601016, 0, 0, 530, 3487, 3487, 1, 1, 1, -1866.5, 5146.5, -42.8, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Buffmaster Hasselhoof - Buffer - Silvermoon Walk of Elders');

-- Reload creature spawns to apply changes
-- Note: You may need to restart the worldserver or use .reload creature command
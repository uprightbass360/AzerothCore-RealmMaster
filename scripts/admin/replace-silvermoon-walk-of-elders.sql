-- Replace Eye of the Storm Envoys in Silvermoon Walk of Elders District
-- Location: Eastern Silvermoon (x:~9514, y:~-7300)
-- GUID: 208304 and 208305

-- Remove the specific Eye of the Storm Envoys at Walk of Elders
DELETE FROM creature WHERE guid IN (208304, 208305);

-- Replace with Kaylub (Free Professions NPC) at first location
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(208304, 199999, 0, 0, 530, 3487, 3431, 1, 1, 0, 9513.94, -7302.81, 14.5485, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Kaylub - Free Professions - Silvermoon Walk of Elders');

-- Replace with Beauregard Boneglitter (Enchanter) at second location
INSERT INTO creature (guid, id1, id2, id3, map, zoneId, areaId, spawnMask, phaseMask, equipment_id, position_x, position_y, position_z, orientation, spawntimesecs, wander_distance, currentwaypoint, curhealth, curmana, MovementType, npcflag, unit_flags, dynamicflags, ScriptName, VerifiedBuild, CreateObject, Comment) VALUES
(208305, 601015, 0, 0, 530, 3487, 3431, 1, 1, 1, 9514.06, -7298.59, 14.5415, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Beauregard Boneglitter - Enchanter - Silvermoon Walk of Elders');

-- Alternative NPC combinations (uncomment desired option and comment above):

-- Option 2: Professions + Buffer
-- INSERT INTO creature VALUES (208304, 199999, 0, 0, 530, 3487, 3431, 1, 1, 0, 9513.94, -7302.81, 14.5485, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Kaylub - Free Professions');
-- INSERT INTO creature VALUES (208305, 601016, 0, 0, 530, 3487, 3431, 1, 1, 1, 9514.06, -7298.59, 14.5415, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Buffmaster Hasselhoof - Buffer');

-- Option 3: Enchanter + Transmog
-- INSERT INTO creature VALUES (208304, 601015, 0, 0, 530, 3487, 3431, 1, 1, 1, 9513.94, -7302.81, 14.5485, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Beauregard Boneglitter - Enchanter');
-- INSERT INTO creature VALUES (208305, 190011, 0, 0, 530, 3487, 3431, 1, 1, 0, 9514.06, -7298.59, 14.5415, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Ethereal Warpweaver - Transmog');

-- Option 4: BeastMaster + Assistant
-- INSERT INTO creature VALUES (208304, 601026, 0, 0, 530, 3487, 3431, 1, 1, 1, 9513.94, -7302.81, 14.5485, 3.14, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'White Fang - BeastMaster');
-- INSERT INTO creature VALUES (208305, 9000000, 0, 0, 530, 3487, 3431, 1, 1, 0, 9514.06, -7298.59, 14.5415, 0.0, 300, 0, 0, 42750, 0, 0, 0, 0, 0, '', 0, 0, 'Gabriella - The Assistant');

-- Execute this to apply changes immediately (run in-game):
-- .reload creature
-- Spawn 11 Custom NPCs in a line in Silvermoon Walk of Elders
-- Center Point: x:9507.111, y:-7301.0264, z:14.117673
-- Line extends 15 units each direction from center (30 units total)
-- 3 unit spacing between each NPC

-- Clear the area first (remove any existing NPCs in this line)
DELETE FROM creature WHERE map = 530 AND position_x BETWEEN 9492 AND 9522 AND position_y BETWEEN -7316 AND -7286;

-- NPC Line Layout (West to East, 11 NPCs total)
-- Position 1: x:9492.111 (center - 15)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800001, 199999, 530, 9492.111, -7301.0264, 14.117673, 3.060474, 300); -- Kaylub (Professions)

-- Position 2: x:9495.111 (center - 12)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800002, 290011, 530, 9495.111, -7301.0264, 14.117673, 3.060474, 300); -- Ling (Reagent Banker)

-- Position 3: x:9498.111 (center - 9)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800003, 300000, 530, 9498.111, -7301.0264, 14.117673, 3.060474, 300); -- Cromi (Instance Reset)

-- Position 4: x:9501.111 (center - 6)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800004, 601015, 530, 9501.111, -7301.0264, 14.117673, 3.060474, 300); -- Beauregard Boneglitter (Enchanter)

-- Position 5: x:9504.111 (center - 3)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800005, 601016, 530, 9504.111, -7301.0264, 14.117673, 3.060474, 300); -- Buffmaster Hasselhoof (Buffer)

-- Position 6: x:9507.111 (CENTER POINT)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800006, 601026, 530, 9507.111, -7301.0264, 14.117673, 3.060474, 300); -- White Fang (BeastMaster)

-- Position 7: x:9510.111 (center + 3)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800007, 601072, 530, 9510.111, -7301.0264, 14.117673, 3.060474, 300); -- Cet Keres (Polymorphologist)

-- Position 8: x:9513.111 (center + 6)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800008, 190010, 530, 9513.111, -7301.0264, 14.117673, 3.060474, 300); -- Warpweaver (Transmog)

-- Position 9: x:9516.111 (center + 9)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800009, 190011, 530, 9516.111, -7301.0264, 14.117673, 3.060474, 300); -- Ethereal Warpweaver (Transmog)

-- Position 10: x:9519.111 (center + 12)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800010, 999991, 530, 9519.111, -7301.0264, 14.117673, 3.060474, 300); -- Arena Battlemaster 1v1

-- Position 11: x:9522.111 (center + 15)
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(800011, 9000000, 530, 9522.111, -7301.0264, 14.117673, 3.060474, 300); -- Gabriella (The Assistant)
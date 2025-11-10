-- Fix Silvermoon Walk of Elders NPCs - Step by step approach

-- Remove old Eye of the Storm Envoys
DELETE FROM creature WHERE guid IN (208304, 208305);

-- Add the two main NPCs first
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(208304, 199999, 530, 9513.94, -7302.81, 14.5485, 3.14, 300),
(208305, 601015, 530, 9514.06, -7298.59, 14.5415, 0.0, 300);

-- Add remaining NPCs with new GUIDs
INSERT INTO creature (guid, id1, map, position_x, position_y, position_z, orientation, spawntimesecs) VALUES
(999911, 601016, 530, 9514.0, -7295.0, 14.5, 4.71, 300),
(999912, 601026, 530, 9518.0, -7297.0, 14.5, 3.93, 300),
(999913, 601072, 530, 9519.0, -7300.5, 14.5, 3.14, 300),
(999914, 190010, 530, 9518.0, -7304.0, 14.5, 2.36, 300),
(999915, 190011, 530, 9514.0, -7306.0, 14.5, 1.57, 300),
(999916, 290011, 530, 9510.0, -7304.0, 14.5, 0.79, 300),
(999917, 300000, 530, 9509.0, -7300.5, 14.5, 0.0, 300),
(999918, 999991, 530, 9510.0, -7297.0, 14.5, 5.50, 300),
(999919, 9000000, 530, 9514.0, -7292.0, 14.5, 4.71, 300),
(999920, 500030, 530, 9522.0, -7300.5, 14.5, 3.14, 300),
(999921, 500031, 530, 9514.0, -7310.0, 14.5, 1.57, 300),
(999922, 500032, 530, 9506.0, -7300.5, 14.5, 0.0, 300);
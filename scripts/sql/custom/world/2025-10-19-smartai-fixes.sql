
-- Normalize Start Waypoint boolean flags that were set to invalid values (e.g., 2 instead of 0/1).
UPDATE smart_scripts
SET action_param1 = 1
WHERE action_type = 53
  AND source_type IN (0, 9)
  AND action_param1 NOT IN (0, 1);

UPDATE smart_scripts
SET action_param1 = 1
WHERE source_type = 9
  AND action_type = 53
  AND action_param1 = 2
  AND entryorguid IN (
    2576200, 2658200, 2658201, 2681404, 2740900, 2741100,
    2748001, 2762600, 2819200, 2821700, 2821701, 2830800,
    2866500, 2866900
  );

-- Remove obsolete “Set Active” actions linked to event 12 that generate SmartAI warnings.
DELETE FROM smart_scripts
WHERE source_type = 0
  AND entryorguid IN (18948, 18950, 18965, 18970, 18972, 18986)
  AND event_type IN (11, 36)
  AND id IN (42, 43)
  AND action_type = 48;

-- Clear dangling linked events for Dalaran Pilgrims to silence "Link Event 3" warnings.
UPDATE smart_scripts
SET link = 0
WHERE source_type = 0
  AND entryorguid IN (32596, 32597, 32598, 32600, 32601, 32602)
  AND id = 2
  AND link = 3;

-- Remove Link Event 12 references on the Darkshore defenders to avoid fallback errors.
UPDATE smart_scripts
SET link = 0
WHERE source_type = 0
  AND entryorguid IN (18948, 18950, 18965, 18970, 18972, 18986)
  AND id = 2
  AND link = 12;

-- Clear Link Event 6 usage for entry 31702, which produces log spam.
UPDATE smart_scripts
SET link = 0
WHERE source_type = 0
  AND entryorguid = 31702
  AND id = 5
  AND link = 6;

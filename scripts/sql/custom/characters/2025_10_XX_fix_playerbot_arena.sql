DELETE FROM arena_team_member
WHERE guid IN (
    SELECT guid
    FROM arena_team_member atm
    JOIN arena_team ate ON atm.arenaTeamId = ate.arenaTeamId
    JOIN characters c ON c.guid = atm.guid
    WHERE ate.type = 5
      AND c.deleteInfos_Account IS NULL
      AND c.name IN (
          SELECT p.name
          FROM playerbots p
          WHERE p.bot = 1
      )
      AND EXISTS (
          SELECT 1
          FROM arena_team_member atm2
          JOIN characters c2 ON atm2.guid = c2.guid
          WHERE atm2.arenaTeamId = atm.arenaTeamId
            AND c2.deleteInfos_Account IS NULL
            AND c2.guid != c.guid
      )
);

DELETE atm
FROM arena_team_member atm
JOIN characters c ON c.guid = atm.guid
WHERE atm.guid IN (
    SELECT guid
    FROM (
        SELECT guid, COUNT(*) AS cnt
        FROM arena_team_member
        GROUP BY guid
        HAVING cnt > 1
    ) dup
)
AND c.deleteInfos_Account IS NULL;

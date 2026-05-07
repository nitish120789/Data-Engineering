-- Oracle and Aurora PostgreSQL reconciliation templates
-- Author: Nitish Anand Srivastava

-- Replace placeholders before execution:
--   <TABLE_NAME>
--   <PK_COL>
--   <DATE_COL>
--   <WINDOW_START>
--   <WINDOW_END>
--   <COL1>, <COL2>, <COL3>

-- ORACLE
SELECT COUNT(*) AS row_count
FROM <TABLE_NAME>;

SELECT MIN(<PK_COL>) AS min_pk,
       MAX(<PK_COL>) AS max_pk,
       COUNT(*) AS rows_in_window
FROM <TABLE_NAME>
WHERE <DATE_COL> >= TO_TIMESTAMP('<WINDOW_START>', 'YYYY-MM-DD HH24:MI:SS')
  AND <DATE_COL> <  TO_TIMESTAMP('<WINDOW_END>', 'YYYY-MM-DD HH24:MI:SS');

SELECT STANDARD_HASH(
         LISTAGG(
           NVL(TO_CHAR(<COL1>), '<null>') || '|' ||
           NVL(TO_CHAR(<COL2>), '<null>') || '|' ||
           NVL(TO_CHAR(<COL3>), '<null>'),
           '||'
         ) WITHIN GROUP (ORDER BY <PK_COL>),
         'SHA256'
       ) AS checksum_hash
FROM <TABLE_NAME>;

SELECT <PK_COL>, COUNT(*) AS dup_count
FROM <TABLE_NAME>
GROUP BY <PK_COL>
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- AURORA POSTGRESQL
SELECT COUNT(*) AS row_count
FROM <TABLE_NAME>;

SELECT MIN(<PK_COL>) AS min_pk,
       MAX(<PK_COL>) AS max_pk,
       COUNT(*) AS rows_in_window
FROM <TABLE_NAME>
WHERE <DATE_COL> >= TIMESTAMP '<WINDOW_START>'
  AND <DATE_COL> <  TIMESTAMP '<WINDOW_END>';

SELECT MD5(STRING_AGG(
             COALESCE(CAST(<COL1> AS TEXT), '<null>') || '|' ||
             COALESCE(CAST(<COL2> AS TEXT), '<null>') || '|' ||
             COALESCE(CAST(<COL3> AS TEXT), '<null>'),
             '||' ORDER BY <PK_COL>
           )) AS checksum_hash
FROM <TABLE_NAME>;

SELECT <PK_COL>, COUNT(*) AS dup_count
FROM <TABLE_NAME>
GROUP BY <PK_COL>
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

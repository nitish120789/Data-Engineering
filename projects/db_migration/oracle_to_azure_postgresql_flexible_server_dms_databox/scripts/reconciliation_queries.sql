-- Cross-engine reconciliation query set
-- Author: Nitish Anand Srivastava

-- Run source and target variants from orchestrator and store output in reconciliation schema.
-- Replace placeholders before execution:
--   <TABLE_NAME>  : fully qualified table name (owner.table for Oracle, schema.table for PostgreSQL)
--   <PK_COL>      : primary key column
--   <DATE_COL>    : time partitioning column
--   <WINDOW_START>: timestamp literal
--   <WINDOW_END>  : timestamp literal
--   <COL1..COL3>  : canonical columns for deterministic checksum

-- ============================================================================
-- ORACLE QUERIES
-- ============================================================================

-- 1) Table row counts
SELECT COUNT(*) AS row_count
FROM <TABLE_NAME>;

-- 2) Key-range coverage sample (replace PK and date filter)
SELECT MIN(<PK_COL>) AS min_pk,
       MAX(<PK_COL>) AS max_pk,
       COUNT(*) AS rows_in_window
FROM <TABLE_NAME>
WHERE <DATE_COL> >= TO_TIMESTAMP('<WINDOW_START>', 'YYYY-MM-DD HH24:MI:SS')
  AND <DATE_COL> <  TO_TIMESTAMP('<WINDOW_END>', 'YYYY-MM-DD HH24:MI:SS');

-- 3) Deterministic checksum over canonical columns (Oracle standard_hash)
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

-- 4) Nullability drift check
SELECT SUM(CASE WHEN <COL1> IS NULL THEN 1 ELSE 0 END) AS null_rows
FROM <TABLE_NAME>;

-- 5) Duplicate PK check
SELECT <PK_COL>, COUNT(*) AS dup_count
FROM <TABLE_NAME>
GROUP BY <PK_COL>
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- ============================================================================
-- POSTGRESQL QUERIES
-- ============================================================================

-- 1) Table row counts
SELECT COUNT(*) AS row_count
FROM <TABLE_NAME>;

-- 2) Key-range coverage sample
SELECT MIN(<PK_COL>) AS min_pk,
       MAX(<PK_COL>) AS max_pk,
       COUNT(*) AS rows_in_window
FROM <TABLE_NAME>
WHERE <DATE_COL> >= TIMESTAMP '<WINDOW_START>'
  AND <DATE_COL> <  TIMESTAMP '<WINDOW_END>';

-- 3) Deterministic checksum over canonical columns
SELECT MD5(STRING_AGG(
             COALESCE(CAST(<COL1> AS TEXT), '<null>') || '|' ||
             COALESCE(CAST(<COL2> AS TEXT), '<null>') || '|' ||
             COALESCE(CAST(<COL3> AS TEXT), '<null>'),
             '||' ORDER BY <PK_COL>
           )) AS checksum_hash
FROM <TABLE_NAME>;

-- 4) Nullability drift check
SELECT SUM(CASE WHEN <COL1> IS NULL THEN 1 ELSE 0 END) AS null_rows
FROM <TABLE_NAME>;

-- 5) Duplicate PK check
SELECT <PK_COL>, COUNT(*) AS dup_count
FROM <TABLE_NAME>
GROUP BY <PK_COL>
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

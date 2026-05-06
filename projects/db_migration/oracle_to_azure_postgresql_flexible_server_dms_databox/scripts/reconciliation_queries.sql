-- Cross-engine reconciliation query set
-- Author: Nitish Anand Srivastava

-- Run source and target variants from orchestrator and store output in reconciliation schema.

-- 1) Table row counts
-- Oracle variant should replace owner/table selector accordingly.
SELECT table_name, COUNT(*) AS row_count
FROM %TABLE_NAME%
GROUP BY table_name;

-- 2) Key-range coverage sample (replace PK and date filter)
SELECT MIN(%PK_COL%) AS min_pk,
       MAX(%PK_COL%) AS max_pk,
       COUNT(*) AS rows_in_window
FROM %TABLE_NAME%
WHERE %DATE_COL% >= %WINDOW_START%
  AND %DATE_COL% <  %WINDOW_END%;

-- 3) Deterministic checksum over canonical columns
SELECT MD5(STRING_AGG(COALESCE(CAST(%COL1% AS TEXT), '<null>') || '|' ||
                      COALESCE(CAST(%COL2% AS TEXT), '<null>') || '|' ||
                      COALESCE(CAST(%COL3% AS TEXT), '<null>'),
                      '||' ORDER BY %PK_COL%)) AS checksum_hash
FROM %TABLE_NAME%
WHERE %FILTER_PREDICATE%;

-- 4) Nullability drift check
SELECT SUM(CASE WHEN %CRITICAL_COL% IS NULL THEN 1 ELSE 0 END) AS null_rows
FROM %TABLE_NAME%;

-- 5) Duplicate PK check
SELECT %PK_COL%, COUNT(*) AS dup_count
FROM %TABLE_NAME%
GROUP BY %PK_COL%
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

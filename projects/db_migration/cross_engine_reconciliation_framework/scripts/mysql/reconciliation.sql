-- MySQL reconciliation template
-- Author: Nitish Anand Srivastava
-- Execute with parameter substitution in your shell wrapper.

-- Set these in client session before execution:
-- SET @schema_name='salesdb';
-- SET @table_name='orders';
-- SET @pk_col='id';
-- SET @updated_col='updated_at';
-- SET @deleted_flag_col='is_deleted';
-- SET @window_start='2026-05-01 00:00:00';
-- SET @window_end='2026-05-01 01:00:00';

SELECT
  table_schema AS schema_name,
  SUM(CASE WHEN table_type='BASE TABLE' THEN 1 ELSE 0 END) AS table_count,
  SUM(CASE WHEN table_type='VIEW' THEN 1 ELSE 0 END) AS view_count
FROM information_schema.tables
WHERE table_schema = @schema_name
GROUP BY table_schema;

SELECT
  @schema_name AS schema_name,
  SUM(CASE WHEN constraint_type='PRIMARY KEY' THEN 1 ELSE 0 END) AS pk_count,
  SUM(CASE WHEN constraint_type='FOREIGN KEY' THEN 1 ELSE 0 END) AS fk_count,
  SUM(CASE WHEN constraint_type='UNIQUE' THEN 1 ELSE 0 END) AS uk_count,
  SUM(CASE WHEN constraint_type='CHECK' THEN 1 ELSE 0 END) AS check_count
FROM information_schema.table_constraints
WHERE table_schema = @schema_name;

SET @q = CONCAT(
' SELECT ''', @schema_name, ''' AS schema_name,
         ''', @table_name, ''' AS table_name,
         COUNT(*) AS row_count,
         SUM(CAST(CONV(SUBSTRING(SHA2(CONCAT_WS(''|'', CAST(', @pk_col, ' AS CHAR), IFNULL(CAST(', @updated_col, ' AS CHAR), ''~''), IFNULL(CAST(', @deleted_flag_col, ' AS CHAR), ''~'')),256),1,16),16,10) AS UNSIGNED)) AS hash_sum,
         SUM(CASE WHEN ', @updated_col, ' >= ''', @window_start, ''' AND ', @updated_col, ' < ''', @window_end, ''' THEN 1 ELSE 0 END) AS updated_count,
         SUM(CASE WHEN IFNULL(', @deleted_flag_col, ',0) IN (1, ''1'', ''Y'') THEN 1 ELSE 0 END) AS deleted_count,
         NOW(6) AS run_ts
  FROM ', @schema_name, '.', @table_name
);

PREPARE stmt FROM @q;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

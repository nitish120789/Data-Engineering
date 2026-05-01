-- Oracle reconciliation template
-- Author: Nitish Anand Srivastava
-- Usage example:
-- sqlplus user/pass@db @scripts/oracle/reconciliation.sql APP ORDERS ID UPDATED_AT IS_DELETED "2026-05-01 00:00:00" "2026-05-01 01:00:00"

SET PAGESIZE 2000 LINESIZE 300 FEEDBACK ON VERIFY OFF TRIMSPOOL ON

DEFINE schema_name = '&1'
DEFINE table_name = '&2'
DEFINE pk_col = '&3'
DEFINE updated_col = '&4'
DEFINE deleted_flag_col = '&5'
DEFINE window_start = '&6'
DEFINE window_end = '&7'

PROMPT === OBJECT COUNT (SCHEMA) ===
SELECT owner AS schema_name,
       SUM(CASE WHEN object_type = 'TABLE' THEN 1 ELSE 0 END) AS table_count,
       SUM(CASE WHEN object_type = 'VIEW' THEN 1 ELSE 0 END) AS view_count,
       SUM(CASE WHEN object_type = 'INDEX' THEN 1 ELSE 0 END) AS index_count,
       SUM(CASE WHEN object_type = 'TRIGGER' THEN 1 ELSE 0 END) AS trigger_count
FROM all_objects
WHERE owner = UPPER('&schema_name')
GROUP BY owner;

PROMPT === CONSTRAINT COUNT (SCHEMA) ===
SELECT owner AS schema_name,
       SUM(CASE WHEN constraint_type = 'P' THEN 1 ELSE 0 END) AS pk_count,
       SUM(CASE WHEN constraint_type = 'R' THEN 1 ELSE 0 END) AS fk_count,
       SUM(CASE WHEN constraint_type = 'U' THEN 1 ELSE 0 END) AS uk_count,
       SUM(CASE WHEN constraint_type = 'C' THEN 1 ELSE 0 END) AS check_count,
       SUM(CASE WHEN status <> 'ENABLED' THEN 1 ELSE 0 END) AS non_enabled_count
FROM all_constraints
WHERE owner = UPPER('&schema_name')
GROUP BY owner;

PROMPT === TABLE COUNT + HASH + UPDATE/DELETE WINDOW ===
SELECT '&schema_name' AS schema_name,
       '&table_name' AS table_name,
       COUNT(*) AS row_count,
       SUM(ORA_HASH(
           TO_CHAR("&pk_col") || '|' ||
           NVL(TO_CHAR("&updated_col", 'YYYY-MM-DD HH24:MI:SS'), '~') || '|' ||
           NVL(TO_CHAR("&deleted_flag_col"), '~')
       )) AS hash_sum,
       SUM(CASE
             WHEN "&updated_col" >= TO_TIMESTAMP('&window_start', 'YYYY-MM-DD HH24:MI:SS')
              AND "&updated_col" < TO_TIMESTAMP('&window_end', 'YYYY-MM-DD HH24:MI:SS')
             THEN 1 ELSE 0
           END) AS updated_count,
       SUM(CASE WHEN NVL("&deleted_flag_col", 0) IN (1, '1', 'Y') THEN 1 ELSE 0 END) AS deleted_count,
       SYSTIMESTAMP AS run_ts
FROM "&schema_name"."&table_name";

PROMPT === OPTIONAL HARD-DELETE SIGNAL (FLASHBACK/AUDIT SOURCE REQUIRED) ===
PROMPT Provide hard-delete counts from CDC/Audit source table if available.

-- Pre-migration assessment for Oracle source
-- Author: Nitish Anand Srivastava

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

SET PAGESIZE 200
SET LINESIZE 240
SET FEEDBACK ON

PROMPT
PROMPT === Usage ===
PROMPT sqlplus system@ORCLP01 @scripts/pre_migration_assessment.sql
PROMPT

PROMPT === Oracle Version and Character Set ===
SELECT * FROM v$version;
SELECT parameter, value
FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');

PROMPT === Top 50 Largest Tables ===
SELECT owner,
       segment_name AS table_name,
       ROUND(bytes / 1024 / 1024 / 1024, 2) AS size_gb
FROM dba_segments
WHERE segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
ORDER BY bytes DESC
FETCH FIRST 50 ROWS ONLY;

PROMPT === LOB Footprint by Schema ===
SELECT owner,
       SUM(bytes) / 1024 / 1024 / 1024 AS lob_size_gb
FROM dba_segments
WHERE segment_type IN ('LOBSEGMENT', 'LOBINDEX')
GROUP BY owner
ORDER BY lob_size_gb DESC;

PROMPT === Objects Potentially Requiring Manual Conversion ===
SELECT owner, object_type, COUNT(*) AS object_count
FROM dba_objects
WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TYPE', 'TYPE BODY', 'TRIGGER', 'MATERIALIZED VIEW')
GROUP BY owner, object_type
ORDER BY owner, object_type;

PROMPT === Invalid Objects ===
SELECT owner, object_type, object_name, status
FROM dba_objects
WHERE status <> 'VALID'
ORDER BY owner, object_type, object_name;

PROMPT === Redo Generation (Past 7 Days) ===
SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hour_bucket,
       ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS redo_gb
FROM v$archived_log
WHERE first_time >= SYSDATE - 7
    AND archived = 'YES'
GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD HH24')
ORDER BY hour_bucket;

PROMPT
PROMPT Assessment completed successfully.
EXIT SUCCESS

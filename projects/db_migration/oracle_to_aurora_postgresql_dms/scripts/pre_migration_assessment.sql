-- Pre-migration assessment for Oracle to Aurora PostgreSQL
-- Author: Nitish Anand Srivastava

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

SET PAGESIZE 200
SET LINESIZE 240
SET FEEDBACK ON

PROMPT
PROMPT === Usage ===
PROMPT sqlplus system@ORCLPRD @scripts/pre_migration_assessment.sql
PROMPT

PROMPT === Oracle Version and Character Set ===
SELECT * FROM v$version;
SELECT parameter, value
FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET');

PROMPT === Largest Tables Including Partitions ===
SELECT owner,
       segment_name AS table_name,
       ROUND(bytes / 1024 / 1024, 2) AS size_mb
FROM dba_segments
WHERE segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
ORDER BY bytes DESC
FETCH FIRST 30 ROWS ONLY;

PROMPT === LOB Footprint by Schema ===
SELECT owner,
       ROUND(SUM(bytes) / 1024 / 1024, 2) AS lob_size_mb
FROM dba_segments
WHERE segment_type IN ('LOBSEGMENT', 'LOBINDEX')
GROUP BY owner
ORDER BY lob_size_mb DESC;

PROMPT === Objects Likely Requiring Manual Conversion ===
SELECT owner, object_type, COUNT(*) AS object_count
FROM dba_objects
WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'TYPE', 'TYPE BODY', 'MATERIALIZED VIEW', 'DATABASE LINK')
GROUP BY owner, object_type
ORDER BY owner, object_type;

PROMPT === Invalid Objects ===
SELECT owner, object_type, object_name, status
FROM dba_objects
WHERE status <> 'VALID'
ORDER BY owner, object_type, object_name;

PROMPT === Redo Generation Last 3 Days ===
SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hour_bucket,
       ROUND(SUM(blocks * block_size) / 1024 / 1024, 2) AS redo_mb
FROM v$archived_log
WHERE first_time >= SYSDATE - 3
  AND archived = 'YES'
GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD HH24')
ORDER BY hour_bucket;

PROMPT
PROMPT Assessment completed successfully.
EXIT SUCCESS

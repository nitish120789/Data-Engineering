-- DMS preflight checks on Oracle source
-- Author: Nitish Anand Srivastava

WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE

SET PAGESIZE 200
SET LINESIZE 240
SET VERIFY OFF

DEFINE DMS_USER='&1'
DEFINE SCHEMA_NAME='&2'

PROMPT
PROMPT === Usage ===
PROMPT sqlplus system@ORCLP01 @scripts/dms_preflight_checks.sql dms_user ERP
PROMPT

PROMPT === ARCHIVELOG Mode ===
SELECT log_mode FROM v$database;

PROMPT === FORCE LOGGING ===
SELECT force_logging FROM v$database;

PROMPT === Supplemental Logging ===
SELECT supplemental_log_data_min,
       supplemental_log_data_pk,
       supplemental_log_data_ui,
       supplemental_log_data_fk,
       supplemental_log_data_all
FROM v$database;

PROMPT === Supplemental Logging Count in Scope Schema ===
SELECT owner,
       COUNT(*) AS tables_with_all_cols_logging
FROM dba_log_groups
WHERE owner = UPPER('&&SCHEMA_NAME')
GROUP BY owner;

PROMPT === Source Privileges for DMS User ===
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee = UPPER('&&DMS_USER')
ORDER BY privilege;

PROMPT === Object Privileges for DMS User (sample) ===
SELECT owner, table_name, privilege
FROM dba_tab_privs
WHERE grantee = UPPER('&&DMS_USER')
  AND owner = UPPER('&&SCHEMA_NAME')
ORDER BY owner, table_name, privilege;

PROMPT === Active Transactions (long running) ===
SELECT s.sid,
       s.serial#,
       s.username,
       t.start_time,
       t.used_ublk,
       t.used_urec
FROM v$session s
JOIN v$transaction t ON s.saddr = t.ses_addr
ORDER BY t.start_time;

PROMPT === Tables Without Primary Key (risk for update/delete apply) ===
SELECT owner, table_name
FROM dba_tables t
WHERE owner = UPPER('&&SCHEMA_NAME')
AND NOT EXISTS (
    SELECT 1
    FROM dba_constraints c
    WHERE c.owner = t.owner
      AND c.table_name = t.table_name
      AND c.constraint_type = 'P'
)
ORDER BY table_name;

PROMPT
PROMPT DMS preflight checks completed successfully.
EXIT SUCCESS

-- AWS DMS preflight checks for Oracle source
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
PROMPT sqlplus system@ORCLPRD @scripts/dms_preflight_checks.sql dms_user APP_SCHEMA
PROMPT

PROMPT === ARCHIVELOG and FORCE LOGGING ===
SELECT log_mode, force_logging
FROM v$database;

PROMPT === Supplemental Logging State ===
SELECT supplemental_log_data_min,
       supplemental_log_data_pk,
       supplemental_log_data_ui,
       supplemental_log_data_fk,
       supplemental_log_data_all
FROM v$database;

PROMPT === DMS User System Privileges ===
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee = UPPER('&&DMS_USER')
ORDER BY privilege;

PROMPT === DMS User Object Privileges in Scope Schema ===
SELECT owner, table_name, privilege
FROM dba_tab_privs
WHERE grantee = UPPER('&&DMS_USER')
  AND owner = UPPER('&&SCHEMA_NAME')
ORDER BY owner, table_name, privilege;

PROMPT === Long Running Transactions ===
SELECT s.sid,
       s.serial#,
       s.username,
       t.start_time,
       t.used_ublk,
       t.used_urec
FROM v$session s
JOIN v$transaction t ON s.saddr = t.ses_addr
ORDER BY t.start_time;

PROMPT === Tables Without Primary Key ===
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
PROMPT AWS DMS preflight completed successfully.
EXIT SUCCESS

-- DMS preflight checks on Oracle source
-- Author: Nitish Anand Srivastava

PROMPT === ARCHIVELOG Mode ===
SELECT log_mode FROM v$database;

PROMPT === Supplemental Logging ===
SELECT supplemental_log_data_min,
       supplemental_log_data_pk,
       supplemental_log_data_ui,
       supplemental_log_data_fk,
       supplemental_log_data_all
FROM v$database;

PROMPT === Source Privileges for DMS User ===
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee = UPPER('&DMS_USER')
ORDER BY privilege;

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
WHERE owner = UPPER('&SCHEMA_NAME')
AND NOT EXISTS (
    SELECT 1
    FROM dba_constraints c
    WHERE c.owner = t.owner
      AND c.table_name = t.table_name
      AND c.constraint_type = 'P'
)
ORDER BY table_name;

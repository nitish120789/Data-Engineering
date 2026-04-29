-- Oracle CPF_Observability snapshot dataset
SELECT SYSTIMESTAMP AS captured_at,
       i.host_name,
       i.instance_name,
       i.version,
       i.status,
       d.name AS db_name,
       d.open_mode,
       d.log_mode
FROM v$instance i
CROSS JOIN v$database d;

SELECT resource_name, current_utilization, max_utilization, limit_value
FROM v$resource_limit
WHERE resource_name IN ('processes','sessions','transactions')
ORDER BY resource_name;

SELECT * FROM (
  SELECT sql_id,
         executions,
         elapsed_time/1e6 AS elapsed_s,
         cpu_time/1e6 AS cpu_s,
         buffer_gets,
         disk_reads,
         rows_processed,
         SUBSTR(sql_text,1,300) AS sql_text
  FROM v$sqlstats
  ORDER BY elapsed_time DESC
) WHERE ROWNUM <= 50;

SELECT event,
       wait_class,
       total_waits,
       time_waited
FROM v$system_event
WHERE wait_class <> 'Idle'
ORDER BY time_waited_micro DESC FETCH FIRST 30 ROWS ONLY;

SELECT df.file_id,
       df.file_name,
       fs.phyrds,
       fs.phywrts,
       fs.readtim,
       fs.writetim,
       CASE WHEN fs.phyrds = 0 THEN NULL ELSE ROUND(fs.readtim/fs.phyrds,3) END AS avg_read_ms,
       CASE WHEN fs.phywrts = 0 THEN NULL ELSE ROUND(fs.writetim/fs.phywrts,3) END AS avg_write_ms
FROM v$filestat fs
JOIN dba_data_files df ON fs.file# = df.file_id
ORDER BY (NVL(fs.readtim,0) + NVL(fs.writetim,0)) DESC FETCH FIRST 30 ROWS ONLY;

SELECT s.sid blocked_sid, s.blocking_session blocker_sid, s.seconds_in_wait, s.event
FROM v$session s
WHERE s.blocking_session IS NOT NULL
ORDER BY s.seconds_in_wait DESC;

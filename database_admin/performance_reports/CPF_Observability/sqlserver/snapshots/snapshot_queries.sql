-- SQL Server CPF_Observability snapshot dataset
SET NOCOUNT ON;

SELECT SYSUTCDATETIME() AS captured_at,
    @@SERVERNAME AS server_name,
    SERVERPROPERTY('Edition') AS edition,
    SERVERPROPERTY('ProductVersion') AS product_version,
    @@VERSION AS version;

SELECT sqlserver_start_time,
    cpu_count,
    scheduler_count,
    physical_memory_kb/1024 AS physical_memory_mb,
    committed_kb/1024 AS committed_memory_mb,
    committed_target_kb/1024 AS committed_target_mb
FROM sys.dm_os_sys_info;

SELECT TOP (30)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
ORDER BY wait_time_ms DESC;

SELECT TOP (30)
    wt.session_id,
    wt.blocking_session_id,
    wt.wait_duration_ms,
    wt.wait_type,
    wt.resource_description,
    er.command,
    DB_NAME(er.database_id) AS database_name
FROM sys.dm_os_waiting_tasks wt
LEFT JOIN sys.dm_exec_requests er
  ON wt.session_id = er.session_id
WHERE wt.blocking_session_id IS NOT NULL
  AND wt.blocking_session_id <> 0
ORDER BY wt.wait_duration_ms DESC;

SELECT TOP (50)
    qs.execution_count,
    qs.total_worker_time/1000.0 AS total_cpu_ms,
    qs.total_elapsed_time/1000.0 AS total_elapsed_ms,
    qs.total_logical_reads,
    qs.total_logical_writes,
    LEFT(st.text, 400) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;

SELECT TOP (30)
    DB_NAME(vfs.database_id) AS db_name,
    mf.type_desc,
    mf.physical_name,
    vfs.num_of_reads,
    vfs.num_of_writes,
    vfs.io_stall_read_ms,
    vfs.io_stall_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
  ON vfs.database_id = mf.database_id
 AND vfs.file_id = mf.file_id
ORDER BY (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;

-- MySQL CPF_Observability snapshot dataset
SET SESSION group_concat_max_len = 102400;

SELECT NOW() AS captured_at,
             @@hostname AS host,
             @@version AS version,
             @@version_comment AS flavor,
             @@read_only AS read_only;

SHOW GLOBAL STATUS WHERE Variable_name IN (
    'Uptime','Threads_running','Threads_connected','Max_used_connections',
    'Queries','Slow_queries','Com_select','Com_insert','Com_update','Com_delete',
    'Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads',
    'Innodb_row_lock_current_waits','Innodb_row_lock_waits','Innodb_row_lock_time',
    'Innodb_deadlocks','Innodb_log_waits',
    'Created_tmp_disk_tables','Created_tmp_tables',
    'Select_full_join','Select_scan'
);

SELECT EVENT_NAME, COUNT_STAR AS wait_count,
             ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_wait_s,
             ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0 AND EVENT_NAME NOT LIKE '%idle%'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

SELECT LEFT(DIGEST_TEXT, 300) AS sql_text,
             SCHEMA_NAME AS db,
             COUNT_STAR AS exec_count,
             ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s,
             ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms,
             SUM_ROWS_EXAMINED AS rows_examined,
             SUM_NO_INDEX_USED AS no_index_used,
             SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 50;

SELECT OBJECT_SCHEMA AS db, OBJECT_NAME AS table_name,
             COUNT_READ, COUNT_WRITE,
             ROUND(SUM_TIMER_READ/1000000000000,3) AS total_read_s,
             ROUND(SUM_TIMER_WRITE/1000000000000,3) AS total_write_s
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA NOT IN ('performance_schema','information_schema','sys','mysql')
    AND (COUNT_READ + COUNT_WRITE) > 0
ORDER BY (SUM_TIMER_READ + SUM_TIMER_WRITE) DESC
LIMIT 30;

SELECT r.trx_id AS waiting_trx_id,
             b.trx_id AS blocking_trx_id,
             TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds,
             LEFT(r.trx_query, 300) AS waiting_query,
             LEFT(b.trx_query, 300) AS blocking_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;

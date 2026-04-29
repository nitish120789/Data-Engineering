#!/usr/bin/env bash
set -euo pipefail

ENGINE="${1:-}"
ENGINE_ROOT="${2:-}"

if [[ -z "${ENGINE}" || -z "${ENGINE_ROOT}" ]]; then
  echo "Usage: run_oneoff_engine.sh <engine> <engine_root>"
  exit 1
fi

CONFIG_FILE="${ENGINE_ROOT}/config/default.env"
SNAPSHOT_SQL="${ENGINE_ROOT}/snapshots/snapshot_queries.sql"
REPORT_SQL="${ENGINE_ROOT}/reports/report_queries.sql"
REPORT_BUILDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/report_builder_stub.py"

TS=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "${ENGINE_ROOT}/data/snapshots" "${ENGINE_ROOT}/data/reports" "${ENGINE_ROOT}/logs"
LOG_FILE="${ENGINE_ROOT}/logs/cpf.log"
SNAPSHOT_OUT="${ENGINE_ROOT}/data/snapshots/snapshot_${TS}.txt"
REPORT_TXT="${ENGINE_ROOT}/data/reports/report_${TS}.txt"
REPORT_HTML="${ENGINE_ROOT}/data/reports/report_${TS}.html"

load_config() {
  local line
  [[ -f "${CONFIG_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#$'\xEF\xBB\xBF'}"
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" != *=* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key#${key%%[![:space:]]*}}"
    key="${key%${key##*[![:space:]]}}"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"

    case "${key}" in
      SNAPSHOT_INTERVAL_MINUTES|RETENTION_DAYS|RUN_MODE|OUTPUT_ROOT|REPORT_WINDOW_MINUTES|DB_HOST|DB_PORT|DB_USER|DB_PASSWORD|DB_NAME|DB_SSL_MODE|MYSQL_LOGIN_PATH|PGHOST|PGPORT|PGUSER|PGDATABASE|PGPASSWORD|SQLSERVER_HOST|SQLSERVER_PORT|SQLSERVER_USER|SQLSERVER_PASSWORD|SQLSERVER_DATABASE|SQLSERVER_TRUST_CERT|ORACLE_CONNECT_STRING|ORACLE_USER|ORACLE_PASSWORD|ORACLE_HOST|ORACLE_PORT|ORACLE_SERVICE|REDIS_HOST|REDIS_PORT|REDIS_PASSWORD|MONGODB_URI|CLICKHOUSE_HOST|CLICKHOUSE_PORT|CLICKHOUSE_USER|CLICKHOUSE_PASSWORD|CLICKHOUSE_DATABASE|CASSANDRA_HOST|CASSANDRA_PORT|CASSANDRA_USER|CASSANDRA_PASSWORD|CASSANDRA_KEYSPACE|COSMOS_SUBSCRIPTION|COSMOS_RESOURCE_GROUP|COSMOS_ACCOUNT)
        export "${key}=${value}"
        ;;
    esac
  done < "${CONFIG_FILE}"
}

append_header() {
  {
    echo "CPF Observability AWR-Style Detailed Performance Report"
    echo "Engine: ${ENGINE}"
    echo "Generated (UTC): ${TS}"
    echo "Host context: ${TARGET_DESC:-unknown}"
    echo
    echo "Sections marked unavailable indicate missing permissions, engine feature flags, or version differences."
  } > "${REPORT_TXT}"
}

append_section() {
  local title="$1"
  shift
  {
    echo
    echo "## ${title}"
    echo
  } >> "${REPORT_TXT}"

  if "$@" >> "${REPORT_TXT}" 2>>"${LOG_FILE}"; then
    echo >> "${REPORT_TXT}"
  else
    {
      echo "Section unavailable on this server/version or insufficient privileges."
      echo
    } >> "${REPORT_TXT}"
  fi
}

run_mysql_sql() {
  local sql="$1"
  "${MYSQL_CMD[@]}" --table -e "${sql}"
}

collect_mysql_family() {
  MYSQL_LOGIN_PATH="${MYSQL_LOGIN_PATH:-}"
  DB_HOST="${DB_HOST:-${MYSQL_HOST:-127.0.0.1}}"
  DB_PORT="${DB_PORT:-${MYSQL_PORT:-3306}}"
  DB_USER="${DB_USER:-${MYSQL_USER:-root}}"
  DB_NAME="${DB_NAME:-${MYSQL_DATABASE:-performance_schema}}"
  DB_PASSWORD="${DB_PASSWORD:-${MYSQL_PASSWORD:-}}"

  MYSQL_CMD=(mysql --connect-timeout=5)
  if [[ -n "${MYSQL_LOGIN_PATH}" ]]; then
    MYSQL_CMD+=(--login-path="${MYSQL_LOGIN_PATH}")
    TARGET_DESC="login-path=${MYSQL_LOGIN_PATH}"
  else
    MYSQL_CMD+=(--host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --database="${DB_NAME}")
    TARGET_DESC="${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  fi

  if [[ -n "${DB_PASSWORD}" ]]; then
    export MYSQL_PWD="${DB_PASSWORD}"
  fi

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  if [[ -f "${SNAPSHOT_SQL}" ]]; then
    "${MYSQL_CMD[@]}" < "${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}" 2>>"${LOG_FILE}" || true
  fi

  append_header
  append_section "Instance Identity and Version" run_mysql_sql "SELECT NOW() AS collected_at_utc, @@hostname AS hostname, @@port AS port, @@version AS version, @@version_comment AS flavor, @@read_only AS read_only"
  append_section "Uptime and Connection Pressure" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_running','Threads_connected','Max_used_connections','Connections','Aborted_connects','Connection_errors_max_connections')"
  append_section "Workload Volume and Throughput Counters" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Questions','Com_select','Com_insert','Com_update','Com_delete','Com_commit','Com_rollback')"
  append_section "Temporary Objects and Sort Pressure" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Created_tmp_tables','Created_tmp_disk_tables','Created_tmp_files','Sort_rows','Sort_merge_passes','Sort_scan','Sort_range')"
  append_section "InnoDB Buffer and IO Signals" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads','Innodb_buffer_pool_pages_total','Innodb_buffer_pool_pages_free','Innodb_data_reads','Innodb_data_writes','Innodb_log_waits','Innodb_os_log_written')"
  append_section "Lock Wait and Deadlock Counters" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_row_lock_current_waits','Innodb_row_lock_waits','Innodb_row_lock_time','Innodb_deadlocks')"
  append_section "Current Long-Running Sessions" run_mysql_sql "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 240) AS SQL_TEXT FROM information_schema.processlist WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 25"
  append_section "Active Lock Wait Chains" run_mysql_sql "SELECT r.trx_id AS waiting_trx_id, b.trx_id AS blocking_trx_id, TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds, LEFT(r.trx_query, 200) AS waiting_query, LEFT(b.trx_query, 200) AS blocking_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id ORDER BY waiting_seconds DESC LIMIT 20"
  append_section "Top SQL by Total Time" run_mysql_sql "SELECT DIGEST, LEFT(DIGEST_TEXT, 160) AS sql_text, COUNT_STAR AS exec_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, SUM_ROWS_EXAMINED AS rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 20"
  append_section "Top SQL by Errors and Rows Examined" run_mysql_sql "SELECT DIGEST, LEFT(DIGEST_TEXT, 160) AS sql_text, COUNT_STAR AS exec_count, SUM_ERRORS AS total_errors, SUM_WARNINGS AS total_warnings, SUM_ROWS_EXAMINED AS rows_examined FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_ERRORS DESC, SUM_ROWS_EXAMINED DESC LIMIT 20"
  append_section "Replication Summary (MySQL 8+)" run_mysql_sql "SHOW REPLICA STATUS"
  append_section "Replication Summary (MySQL 5.7 Legacy)" run_mysql_sql "SHOW SLAVE STATUS"
  append_section "InnoDB Engine Status" run_mysql_sql "SHOW ENGINE INNODB STATUS"
}

run_psql_sql() {
  local sql="$1"
  "${PSQL_CMD[@]}" -c "${sql}"
}

collect_postgresql_family() {
  DB_HOST="${DB_HOST:-${PGHOST:-127.0.0.1}}"
  DB_PORT="${DB_PORT:-${PGPORT:-5432}}"
  DB_USER="${DB_USER:-${PGUSER:-postgres}}"
  DB_NAME="${DB_NAME:-${PGDATABASE:-postgres}}"
  DB_PASSWORD="${DB_PASSWORD:-${PGPASSWORD:-}}"

  export PGHOST="${DB_HOST}" PGPORT="${DB_PORT}" PGUSER="${DB_USER}" PGDATABASE="${DB_NAME}"
  if [[ -n "${DB_PASSWORD}" ]]; then
    export PGPASSWORD="${DB_PASSWORD}"
  fi

  PSQL_CMD=(psql -X --pset pager=off)
  TARGET_DESC="${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  if [[ -f "${SNAPSHOT_SQL}" ]]; then
    "${PSQL_CMD[@]}" -f "${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}" 2>>"${LOG_FILE}" || true
  fi

  append_header
  append_section "Instance Identity and Version" run_psql_sql "SELECT now() AS collected_at_utc, inet_server_addr() AS server_ip, inet_server_port() AS server_port, version();"
  append_section "Uptime and Connection Pressure" run_psql_sql "SELECT now() - pg_postmaster_start_time() AS uptime, (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_connections, (SELECT count(*) FROM pg_stat_activity) AS current_connections, (SELECT count(*) FROM pg_stat_activity WHERE state='active') AS active_connections;"
  append_section "Database Throughput and Tuple Activity" run_psql_sql "SELECT datname, xact_commit, xact_rollback, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted FROM pg_stat_database ORDER BY xact_commit + xact_rollback DESC LIMIT 20;"
  append_section "Temp Files and Blocks" run_psql_sql "SELECT datname, temp_files, temp_bytes, blk_read_time, blk_write_time FROM pg_stat_database ORDER BY temp_bytes DESC LIMIT 20;"
  append_section "Cache Hit Ratios" run_psql_sql "SELECT datname, ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct FROM pg_stat_database ORDER BY cache_hit_pct ASC NULLS LAST;"
  append_section "Long-Running Active Queries" run_psql_sql "SELECT pid, usename, datname, state, wait_event_type, wait_event, now() - query_start AS duration, left(query, 240) AS query FROM pg_stat_activity WHERE state <> 'idle' ORDER BY duration DESC LIMIT 25;"
  append_section "Blocking Chains" run_psql_sql "SELECT blocked.pid AS blocked_pid, blocker.pid AS blocker_pid, blocked.usename AS blocked_user, blocker.usename AS blocker_user, now() - blocked.query_start AS blocked_for, left(blocked.query, 160) AS blocked_query, left(blocker.query, 160) AS blocker_query FROM pg_stat_activity blocked JOIN pg_stat_activity blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) ORDER BY blocked_for DESC LIMIT 20;"
  append_section "Top SQL by Total Time" run_psql_sql "SELECT queryid, calls, ROUND(total_exec_time::numeric,2) AS total_ms, ROUND(mean_exec_time::numeric,2) AS mean_ms, rows, left(query, 180) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;"
  append_section "Top SQL by Shared Block Reads" run_psql_sql "SELECT queryid, calls, shared_blks_read, shared_blks_hit, temp_blks_read, temp_blks_written, left(query, 180) AS query FROM pg_stat_statements ORDER BY shared_blks_read DESC LIMIT 20;"
  append_section "WAL and Checkpoint Pressure" run_psql_sql "SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, checkpoint_sync_time, buffers_checkpoint, buffers_backend, maxwritten_clean FROM pg_stat_bgwriter;"
  append_section "Replication Lag" run_psql_sql "SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
}

run_sqlserver_sql() {
  local sql="$1"
  "${SQLCMD_CMD[@]}" -Q "${sql}"
}

collect_sqlserver_family() {
  DB_HOST="${DB_HOST:-${SQLSERVER_HOST:-127.0.0.1}}"
  DB_PORT="${DB_PORT:-${SQLSERVER_PORT:-1433}}"
  DB_USER="${DB_USER:-${SQLSERVER_USER:-sa}}"
  DB_NAME="${DB_NAME:-${SQLSERVER_DATABASE:-master}}"
  DB_PASSWORD="${DB_PASSWORD:-${SQLSERVER_PASSWORD:-}}"
  SQLSERVER_TRUST_CERT="${SQLSERVER_TRUST_CERT:-true}"

  SQLCMD_CMD=(sqlcmd -S "${DB_HOST},${DB_PORT}" -d "${DB_NAME}" -W -w 220)
  if [[ -n "${DB_USER}" && -n "${DB_PASSWORD}" ]]; then
    SQLCMD_CMD+=( -U "${DB_USER}" -P "${DB_PASSWORD}" )
  else
    SQLCMD_CMD+=( -E )
  fi
  if [[ "${SQLSERVER_TRUST_CERT}" == "true" ]]; then
    SQLCMD_CMD+=( -C )
  fi

  TARGET_DESC="${DB_HOST}:${DB_PORT}/${DB_NAME}"
  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  if [[ -f "${SNAPSHOT_SQL}" ]]; then
    "${SQLCMD_CMD[@]}" -i "${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}" 2>>"${LOG_FILE}" || true
  fi

  append_header
  append_section "Instance Identity and Version" run_sqlserver_sql "SELECT GETUTCDATE() AS collected_at_utc, @@SERVERNAME AS server_name, @@VERSION AS version;"
  append_section "Uptime, Build, and Server Configuration" run_sqlserver_sql "SELECT sqlserver_start_time, cpu_count, scheduler_count, hyperthread_ratio, physical_memory_kb/1024 AS physical_memory_mb, committed_kb/1024 AS committed_memory_mb, committed_target_kb/1024 AS committed_target_mb FROM sys.dm_os_sys_info; SELECT name, value_in_use FROM sys.configurations WHERE name IN ('max degree of parallelism','cost threshold for parallelism','max server memory (MB)','min server memory (MB)','optimize for ad hoc workloads','backup compression default','query wait (s)','remote admin connections') ORDER BY name;"
  append_section "Database Inventory and Recovery Posture" run_sqlserver_sql "SELECT d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level, d.log_reuse_wait_desc, d.page_verify_option_desc, d.delayed_durability_desc, d.is_auto_create_stats_on, d.is_auto_update_stats_on, d.snapshot_isolation_state_desc, d.is_read_committed_snapshot_on FROM sys.databases d ORDER BY d.name;"
  append_section "Connection Pressure and Session Mix" run_sqlserver_sql "SELECT COUNT(*) AS current_sessions, SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END) AS user_sessions, SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS running_sessions, SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS sleeping_sessions, SUM(CASE WHEN open_transaction_count > 0 THEN 1 ELSE 0 END) AS sessions_with_open_txn FROM sys.dm_exec_sessions; SELECT TOP 20 login_name, host_name, program_name, COUNT(*) AS session_count FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY login_name, host_name, program_name ORDER BY session_count DESC;"
  append_section "Workload Throughput Counters" run_sqlserver_sql "SELECT object_name, counter_name, instance_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('Batch Requests/sec','SQL Compilations/sec','SQL Re-Compilations/sec','User Connections','Processes blocked','Page life expectancy','Memory Grants Pending','Memory Grants Outstanding','Lazy writes/sec','Checkpoint pages/sec','Forwarded Records/sec','Full Scans/sec','Page reads/sec','Page writes/sec') ORDER BY counter_name, instance_name;"
  append_section "Scheduler and CPU Pressure" run_sqlserver_sql "SELECT scheduler_id, cpu_id, status, is_online, current_tasks_count, runnable_tasks_count, current_workers_count, active_workers_count, load_factor, work_queue_count FROM sys.dm_os_schedulers WHERE scheduler_id < 255 ORDER BY runnable_tasks_count DESC, current_tasks_count DESC;"
  append_section "Memory Grants and Buffer Health" run_sqlserver_sql "SELECT TOP 20 request_time, grant_time, requested_memory_kb, granted_memory_kb, ideal_memory_kb, required_memory_kb, wait_time_ms, queue_id, dop, timeout_sec, resource_semaphore_id FROM sys.dm_exec_query_memory_grants ORDER BY requested_memory_kb DESC; SELECT counter_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('Page life expectancy','Buffer cache hit ratio','Target Server Memory (KB)','Total Server Memory (KB)','Free list stalls/sec');"
  append_section "Waits by Category" run_sqlserver_sql "WITH waits AS ( SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms, CASE WHEN wait_type LIKE 'LCK[_]%' THEN 'Lock' WHEN wait_type LIKE 'PAGEIOLATCH[_]%' OR wait_type LIKE 'IO[_]%' OR wait_type IN ('WRITELOG','LOGBUFFER') THEN 'IO/Log' WHEN wait_type LIKE 'CX%' OR wait_type LIKE 'CXSYNC[_]%' THEN 'Parallelism' WHEN wait_type LIKE 'RESOURCE[_]SEMAPHORE%' OR wait_type LIKE 'MEMORY[_]%' THEN 'Memory' WHEN wait_type LIKE 'SOS[_]SCHEDULER[_]YIELD' OR wait_type LIKE 'THREADPOOL' THEN 'CPU/Scheduler' WHEN wait_type LIKE 'HADR[_]%' THEN 'HADR' WHEN wait_type LIKE 'PAGELATCH[_]%' THEN 'Latch' ELSE 'Other' END AS wait_category FROM sys.dm_os_wait_stats WHERE wait_type NOT IN ('CLR_AUTO_EVENT','CLR_MANUAL_EVENT','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_SEMAPHORE','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','ONDEMAND_TASK_QUEUE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','BROKER_EVENTHANDLER','TRACEWRITE','SOS_WORK_DISPATCHER','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','SP_SERVER_DIAGNOSTICS_SLEEP') ) SELECT TOP 20 wait_category, wait_type, waiting_tasks_count, CAST(wait_time_ms/1000.0 AS DECIMAL(18,2)) AS wait_s, CAST(signal_wait_time_ms/1000.0 AS DECIMAL(18,2)) AS signal_wait_s FROM waits ORDER BY wait_time_ms DESC;"
  append_section "Current Waiting Tasks and Wait Chains" run_sqlserver_sql "SELECT TOP 30 wt.session_id, wt.exec_context_id, wt.wait_duration_ms, wt.wait_type, wt.blocking_session_id, wt.resource_description, er.status, er.command, DB_NAME(er.database_id) AS database_name, LEFT(txt.text, 320) AS sql_text FROM sys.dm_os_waiting_tasks wt LEFT JOIN sys.dm_exec_requests er ON wt.session_id = er.session_id OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) txt ORDER BY wt.wait_duration_ms DESC;"
  append_section "Active Requests (ASH Analogue)" run_sqlserver_sql "SELECT TOP 40 r.session_id, s.login_name, s.host_name, s.program_name, DB_NAME(r.database_id) AS database_name, r.status, r.command, r.cpu_time, r.total_elapsed_time, r.reads, r.writes, r.logical_reads, r.wait_type, r.wait_time, r.blocking_session_id, r.granted_query_memory, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt WHERE s.is_user_process = 1 ORDER BY r.total_elapsed_time DESC, r.cpu_time DESC;"
  append_section "Long-Running Sessions and Open Transactions" run_sqlserver_sql "SELECT TOP 25 s.session_id, s.login_name, s.host_name, s.program_name, s.status, s.open_transaction_count, DATEDIFF(SECOND, s.last_request_start_time, GETDATE()) AS seconds_since_request_start, DATEDIFF(SECOND, s.last_request_end_time, GETDATE()) AS seconds_since_request_end, c.client_net_address, c.net_transport, c.encrypt_option, LEFT(txt.text, 320) AS last_sql_text FROM sys.dm_exec_sessions s LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) txt WHERE s.is_user_process = 1 ORDER BY s.open_transaction_count DESC, seconds_since_request_start DESC;"
  append_section "Blocking Sessions and Head Blockers" run_sqlserver_sql "WITH waiting AS ( SELECT r.session_id, r.blocking_session_id, r.wait_type, r.wait_time, r.cpu_time, r.logical_reads, DB_NAME(r.database_id) AS database_name, LEFT(t.text, 320) AS sql_text FROM sys.dm_exec_requests r OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE r.blocking_session_id <> 0 ) SELECT TOP 30 waiting.*, s.login_name, s.host_name, s.program_name FROM waiting LEFT JOIN sys.dm_exec_sessions s ON waiting.session_id = s.session_id ORDER BY wait_time DESC;"
  append_section "TempDB Usage and Version Store" run_sqlserver_sql "SELECT SUM(user_object_reserved_page_count) * 8 AS user_object_kb, SUM(internal_object_reserved_page_count) * 8 AS internal_object_kb, SUM(version_store_reserved_page_count) * 8 AS version_store_kb, SUM(unallocated_extent_page_count) * 8 AS unallocated_kb FROM tempdb.sys.dm_db_file_space_usage; SELECT TOP 20 session_id, user_objects_alloc_page_count * 8 AS user_alloc_kb, internal_objects_alloc_page_count * 8 AS internal_alloc_kb FROM sys.dm_db_session_space_usage ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC;"
  append_section "Transaction Log and Recovery Health" run_sqlserver_sql "SELECT database_id, DB_NAME(database_id) AS database_name, total_log_size_mb, active_log_size_mb, log_truncation_holdup_reason FROM sys.dm_db_log_stats(NULL) ORDER BY active_log_size_mb DESC;"
  append_section "Database IO Stall by File" run_sqlserver_sql "SELECT DB_NAME(vfs.database_id) AS db_name, mf.type_desc, mf.file_id, mf.name AS logical_name, mf.physical_name, vfs.num_of_reads, vfs.num_of_writes, vfs.io_stall_read_ms, vfs.io_stall_write_ms, CASE WHEN vfs.num_of_reads = 0 THEN NULL ELSE CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(18,2)) END AS avg_read_stall_ms, CASE WHEN vfs.num_of_writes = 0 THEN NULL ELSE CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(18,2)) END AS avg_write_stall_ms, vfs.size_on_disk_bytes / 1048576 AS size_on_disk_mb FROM sys.dm_io_virtual_file_stats(NULL,NULL) vfs JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id ORDER BY (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;"
  append_section "Top CPU Statements" run_sqlserver_sql "SELECT TOP 25 qs.execution_count, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_worker_time / NULLIF(qs.execution_count,0) / 1000.0 AS DECIMAL(18,2)) AS avg_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, qs.total_logical_reads, qs.total_logical_writes, qs.max_worker_time/1000.0 AS max_cpu_ms, DB_NAME(COALESCE(txt.dbid, qp.dbid)) AS database_name, LEFT(txt.text, 400) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt OUTER APPLY sys.dm_exec_text_query_plan(qs.plan_handle, qs.statement_start_offset, qs.statement_end_offset) qp ORDER BY qs.total_worker_time DESC;"
  append_section "Top Duration Statements" run_sqlserver_sql "SELECT TOP 25 qs.execution_count, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, CAST(qs.total_elapsed_time / NULLIF(qs.execution_count,0) / 1000.0 AS DECIMAL(18,2)) AS avg_elapsed_ms, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, qs.total_logical_reads, qs.total_logical_writes, qs.max_elapsed_time/1000.0 AS max_elapsed_ms, LEFT(txt.text, 400) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_elapsed_time DESC;"
  append_section "Top Read and Write Statements" run_sqlserver_sql "SELECT TOP 20 'reads' AS metric, qs.execution_count, qs.total_logical_reads AS metric_value, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_logical_reads DESC; SELECT TOP 20 'writes' AS metric, qs.execution_count, qs.total_logical_writes AS metric_value, CAST(qs.total_worker_time/1000.0 AS DECIMAL(18,2)) AS total_cpu_ms, CAST(qs.total_elapsed_time/1000.0 AS DECIMAL(18,2)) AS total_elapsed_ms, LEFT(txt.text, 320) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt ORDER BY qs.total_logical_writes DESC;"
  append_section "Plan Cache Efficiency and Recompiles" run_sqlserver_sql "SELECT objtype, cacheobjtype, COUNT(*) AS plans, SUM(size_in_bytes)/1048576.0 AS size_mb, SUM(usecounts) AS total_usecounts FROM sys.dm_exec_cached_plans GROUP BY objtype, cacheobjtype ORDER BY size_mb DESC; SELECT counter_name, cntr_value FROM sys.dm_os_performance_counters WHERE counter_name IN ('SQL Compilations/sec','SQL Re-Compilations/sec','Cache Hit Ratio','Cache Pages');"
  append_section "Missing Index Candidates" run_sqlserver_sql "SELECT TOP 25 DB_NAME(mid.database_id) AS database_name, OBJECT_NAME(mid.object_id, mid.database_id) AS table_name, migs.user_seeks, migs.user_scans, CAST(migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) AS improvement_measure, mid.equality_columns, mid.inequality_columns, mid.included_columns FROM sys.dm_db_missing_index_group_stats migs JOIN sys.dm_db_missing_index_groups mig ON migs.group_handle = mig.index_group_handle JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle ORDER BY improvement_measure DESC;"
  append_section "Query Store Regressions and Runtime Outliers" run_sqlserver_sql "SELECT actual_state_desc, desired_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb, interval_length_minutes FROM sys.database_query_store_options; SELECT TOP 25 qsq.query_id, qsp.plan_id, rs.count_executions, CAST(rs.avg_duration/1000.0 AS DECIMAL(18,2)) AS avg_duration_ms, CAST(rs.max_duration/1000.0 AS DECIMAL(18,2)) AS max_duration_ms, CAST(rs.avg_cpu_time/1000.0 AS DECIMAL(18,2)) AS avg_cpu_ms, CAST(rs.avg_logical_io_reads AS DECIMAL(18,2)) AS avg_logical_reads, LEFT(qt.query_sql_text, 320) AS sql_text FROM sys.query_store_runtime_stats rs JOIN sys.query_store_plan qsp ON rs.plan_id = qsp.plan_id JOIN sys.query_store_query qsq ON qsp.query_id = qsq.query_id JOIN sys.query_store_query_text qt ON qsq.query_text_id = qt.query_text_id ORDER BY rs.avg_duration DESC;"
  append_section "Deadlock Signals from System Health" run_sqlserver_sql "SELECT TOP 10 xed.event_data.value('(event/@timestamp)[1]', 'datetime2') AS event_time_utc, xed.event_data.value('(event/data/value/deadlock/process-list/process/@spid)[1]', 'int') AS victim_spid, xed.event_data.value('count((event/data/value/deadlock/process-list/process))', 'int') AS process_count, xed.event_data.value('count((event/data/value/deadlock/resource-list/*))', 'int') AS resource_count FROM ( SELECT CAST(event_data AS XML) AS event_data FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) WHERE object_name = 'xml_deadlock_report' ) xed ORDER BY event_time_utc DESC;"
  append_section "AlwaysOn Replica Health" run_sqlserver_sql "SELECT ag.name AS ag_name, ar.replica_server_name, ars.role_desc, ars.connected_state_desc, ars.operational_state_desc, ars.synchronization_health_desc, ar.availability_mode_desc, ar.failover_mode_desc FROM sys.dm_hadr_availability_replica_states ars JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id JOIN sys.availability_groups ag ON ar.group_id = ag.group_id; SELECT DB_NAME(drs.database_id) AS database_name, drs.is_local, drs.synchronization_state_desc, drs.synchronization_health_desc, drs.log_send_queue_size, drs.redo_queue_size, drs.redo_rate, drs.log_send_rate FROM sys.dm_hadr_database_replica_states drs ORDER BY drs.log_send_queue_size DESC, drs.redo_queue_size DESC;"
}

oracle_sql_block() {
  local sql="$1"
  sqlplus -s "${ORACLE_CONN}" <<EOF
SET LINESIZE 220
SET PAGESIZE 500
SET TRIMSPOOL ON
SET FEEDBACK ON
${sql}
EXIT
EOF
}

collect_oracle() {
  DB_HOST="${DB_HOST:-${ORACLE_HOST:-127.0.0.1}}"
  DB_PORT="${DB_PORT:-${ORACLE_PORT:-1521}}"
  DB_NAME="${DB_NAME:-${ORACLE_SERVICE:-ORCLPDB1}}"
  DB_USER="${DB_USER:-${ORACLE_USER:-system}}"
  DB_PASSWORD="${DB_PASSWORD:-${ORACLE_PASSWORD:-}}"
  ORACLE_CONNECT_STRING="${ORACLE_CONNECT_STRING:-}"

  if [[ -n "${ORACLE_CONNECT_STRING}" ]]; then
    ORACLE_CONN="${ORACLE_CONNECT_STRING}"
    TARGET_DESC="${ORACLE_CONNECT_STRING}"
  else
    ORACLE_CONN="${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_NAME}"
    TARGET_DESC="${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  fi

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  if [[ -f "${SNAPSHOT_SQL}" ]]; then
    sqlplus -s "${ORACLE_CONN}" @"${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}" 2>>"${LOG_FILE}" || true
  fi

  append_header
  append_section "Instance Identity and Version" oracle_sql_block "SELECT SYSTIMESTAMP AT TIME ZONE 'UTC' AS collected_at_utc FROM dual; SELECT host_name, instance_name, version, status FROM v\$instance;"
  append_section "Database Throughput" oracle_sql_block "SELECT name, value FROM v\$sysstat WHERE name IN ('user commits','user rollbacks','execute count','parse count (total)','logons current','opened cursors current');"
  append_section "Top Wait Events" oracle_sql_block "SELECT event, total_waits, time_waited FROM v\$system_event WHERE wait_class <> 'Idle' ORDER BY time_waited DESC FETCH FIRST 25 ROWS ONLY;"
  append_section "Top SQL by Elapsed Time" oracle_sql_block "SELECT * FROM (SELECT sql_id, elapsed_time/1000000 AS elapsed_s, cpu_time/1000000 AS cpu_s, executions, buffer_gets, disk_reads FROM v\$sqlstats ORDER BY elapsed_time DESC) WHERE ROWNUM <= 20;"
  append_section "Top SQL by Buffer Gets" oracle_sql_block "SELECT * FROM (SELECT sql_id, buffer_gets, disk_reads, executions, elapsed_time/1000000 AS elapsed_s FROM v\$sqlstats ORDER BY buffer_gets DESC) WHERE ROWNUM <= 20;"
  append_section "Session and Blocking Overview" oracle_sql_block "SELECT sid, serial#, username, status, event, blocking_session, seconds_in_wait FROM v\$session WHERE type='USER' ORDER BY seconds_in_wait DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Tablespace Utilization" oracle_sql_block "SELECT tablespace_name, ROUND(used_percent,2) AS used_percent FROM dba_tablespace_usage_metrics ORDER BY used_percent DESC;"
  append_section "Redo and Archive Pressure" oracle_sql_block "SELECT name, value FROM v\$sysstat WHERE name IN ('redo size','redo writes','redo blocks written');"
}

collect_redis() {
  REDIS_HOST="${REDIS_HOST:-${DB_HOST:-127.0.0.1}}"
  REDIS_PORT="${REDIS_PORT:-${DB_PORT:-6379}}"
  REDIS_PASSWORD="${REDIS_PASSWORD:-${DB_PASSWORD:-}}"

  REDIS_CMD=(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}")
  if [[ -n "${REDIS_PASSWORD}" ]]; then
    REDIS_CMD+=( -a "${REDIS_PASSWORD}" )
  fi
  TARGET_DESC="${REDIS_HOST}:${REDIS_PORT}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  append_header
  append_section "Server and Memory Overview" "${REDIS_CMD[@]}" INFO SERVER
  append_section "Memory Metrics" "${REDIS_CMD[@]}" INFO MEMORY
  append_section "Command Stats" "${REDIS_CMD[@]}" INFO COMMANDSTATS
  append_section "Clients and Connection Pressure" "${REDIS_CMD[@]}" INFO CLIENTS
  append_section "Persistence and RDB/AOF" "${REDIS_CMD[@]}" INFO PERSISTENCE
  append_section "Replication" "${REDIS_CMD[@]}" INFO REPLICATION
  append_section "Slowlog (Top Entries)" "${REDIS_CMD[@]}" SLOWLOG GET 50
  append_section "Latency Doctor" "${REDIS_CMD[@]}" LATENCY DOCTOR
}

collect_mongodb() {
  MONGODB_URI="${MONGODB_URI:-mongodb://127.0.0.1:27017/admin}"
  TARGET_DESC="${MONGODB_URI}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  mongo_eval() {
    mongosh "${MONGODB_URI}" --quiet --eval "$1"
  }

  append_header
  append_section "Server Build and Uptime" mongo_eval "db.serverBuildInfo(); db.serverStatus().uptime;"
  append_section "Connection and Network Pressure" mongo_eval "var s=db.serverStatus(); printjson({connections:s.connections, network:s.network, opcounters:s.opcounters});"
  append_section "Global Locks and WiredTiger Cache" mongo_eval "var s=db.serverStatus(); printjson({globalLock:s.globalLock, wiredTiger:s.wiredTiger ? s.wiredTiger.cache : 'wiredTiger unavailable'});"
  append_section "Top Databases by Size" mongo_eval "db.adminCommand({listDatabases:1, nameOnly:false});"
  append_section "Current Operations (Top 50)" mongo_eval "db.currentOp({active:true,secs_running:{$gte:1}});"
  append_section "Replication Status" mongo_eval "rs.status();"
}

collect_clickhouse() {
  CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-${DB_HOST:-127.0.0.1}}"
  CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-${DB_PORT:-9000}}"
  CLICKHOUSE_USER="${CLICKHOUSE_USER:-${DB_USER:-default}}"
  CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-${DB_PASSWORD:-}}"
  CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-${DB_NAME:-default}}"

  CH_CMD=(clickhouse-client --host "${CLICKHOUSE_HOST}" --port "${CLICKHOUSE_PORT}" --user "${CLICKHOUSE_USER}" --database "${CLICKHOUSE_DATABASE}")
  if [[ -n "${CLICKHOUSE_PASSWORD}" ]]; then
    CH_CMD+=( --password "${CLICKHOUSE_PASSWORD}" )
  fi
  TARGET_DESC="${CLICKHOUSE_USER}@${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/${CLICKHOUSE_DATABASE}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  ch_sql() {
    "${CH_CMD[@]}" --query "$1"
  }

  append_header
  append_section "Instance Identity and Version" ch_sql "SELECT now() AS collected_at_utc, version() AS version, hostName() AS host"
  append_section "CPU and Memory Metrics" ch_sql "SELECT metric, value FROM system.metrics WHERE metric IN ('Query','MemoryTracking','BackgroundPoolTask','Merge') ORDER BY metric"
  append_section "Asynchronous Metrics" ch_sql "SELECT metric, value FROM system.asynchronous_metrics ORDER BY metric LIMIT 120"
  append_section "Top Active Queries" ch_sql "SELECT elapsed, read_rows, read_bytes, memory_usage, query FROM system.processes ORDER BY elapsed DESC LIMIT 25"
  append_section "Top Query Log by Read Bytes" ch_sql "SELECT event_time, query_duration_ms, read_rows, read_bytes, result_rows, result_bytes, query FROM system.query_log WHERE type = 'QueryFinish' ORDER BY read_bytes DESC LIMIT 20"
  append_section "Merges and Mutations" ch_sql "SELECT database, table, elapsed, progress, num_parts, source_part_names FROM system.merges ORDER BY elapsed DESC LIMIT 20"
  append_section "Replicas Status" ch_sql "SELECT database, table, is_leader, is_readonly, queue_size, inserts_in_queue, merges_in_queue, log_max_index - log_pointer AS replication_lag FROM system.replicas ORDER BY replication_lag DESC LIMIT 20"
}

collect_cassandra() {
  CASSANDRA_HOST="${CASSANDRA_HOST:-${DB_HOST:-127.0.0.1}}"
  CASSANDRA_PORT="${CASSANDRA_PORT:-${DB_PORT:-9042}}"
  CASSANDRA_USER="${CASSANDRA_USER:-${DB_USER:-}}"
  CASSANDRA_PASSWORD="${CASSANDRA_PASSWORD:-${DB_PASSWORD:-}}"
  CASSANDRA_KEYSPACE="${CASSANDRA_KEYSPACE:-${DB_NAME:-system}}"
  TARGET_DESC="${CASSANDRA_HOST}:${CASSANDRA_PORT}/${CASSANDRA_KEYSPACE}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  CQLSH_CMD=(cqlsh "${CASSANDRA_HOST}" "${CASSANDRA_PORT}")
  if [[ -n "${CASSANDRA_USER}" && -n "${CASSANDRA_PASSWORD}" ]]; then
    CQLSH_CMD+=( -u "${CASSANDRA_USER}" -p "${CASSANDRA_PASSWORD}" )
  fi

  cql_sql() {
    echo "$1" | "${CQLSH_CMD[@]}"
  }

  append_header
  append_section "Cluster Status" nodetool status
  append_section "Node Info" nodetool info
  append_section "Compaction Stats" nodetool compactionstats
  append_section "Table Stats" nodetool tablestats
  append_section "Thread Pool Stats" nodetool tpstats
  append_section "Proxy Histograms" nodetool proxyhistograms
  append_section "Read/Write Latency by Keyspace" cql_sql "SELECT keyspace_name, table_name, bloom_filter_false_positives, live_disk_space_used, read_latency, write_latency FROM system_schema.tables;"
}

collect_cosmosdb() {
  COSMOS_SUBSCRIPTION="${COSMOS_SUBSCRIPTION:-}"
  COSMOS_RESOURCE_GROUP="${COSMOS_RESOURCE_GROUP:-}"
  COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-}"
  TARGET_DESC="subscription=${COSMOS_SUBSCRIPTION};rg=${COSMOS_RESOURCE_GROUP};account=${COSMOS_ACCOUNT}"

  echo "Running one-off snapshot at ${TS}" | tee -a "${LOG_FILE}"
  echo "Target: ${TARGET_DESC}" | tee -a "${LOG_FILE}"

  az_metrics() {
    local metric="$1"
    az monitor metrics list --resource "/subscriptions/${COSMOS_SUBSCRIPTION}/resourceGroups/${COSMOS_RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_ACCOUNT}" --metric "${metric}" --interval PT5M --aggregation Average Maximum Total --output table
  }

  append_header
  append_section "Cosmos Account Details" az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${COSMOS_RESOURCE_GROUP}" --subscription "${COSMOS_SUBSCRIPTION}" --output table
  append_section "Total Request Units" az_metrics TotalRequestUnits
  append_section "Normalized RU Consumption" az_metrics NormalizedRUConsumption
  append_section "Data Usage" az_metrics DataUsage
  append_section "Index Usage" az_metrics IndexUsage
  append_section "Server Side Latency" az_metrics ServerSideLatency
  append_section "Availability" az_metrics Availability
}

render_html() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "${REPORT_BUILDER}" --engine "${ENGINE}" --input "${REPORT_TXT}" --output "${REPORT_HTML}"
  elif command -v python >/dev/null 2>&1; then
    python "${REPORT_BUILDER}" --engine "${ENGINE}" --input "${REPORT_TXT}" --output "${REPORT_HTML}"
  else
    {
      echo "<!doctype html><html><head><meta charset=\"utf-8\"><title>${ENGINE} report</title></head><body><pre>"
      sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "${REPORT_TXT}"
      echo "</pre></body></html>"
    } > "${REPORT_HTML}"
  fi
}

load_config

case "${ENGINE}" in
  mysql|aurora_mysql|aws_rds)
    collect_mysql_family
    ;;
  postgresql|aurora_postgresql)
    collect_postgresql_family
    ;;
  sqlserver|azure_sql_db)
    collect_sqlserver_family
    ;;
  oracle)
    collect_oracle
    ;;
  redis)
    collect_redis
    ;;
  mongodb)
    collect_mongodb
    ;;
  clickhouse)
    collect_clickhouse
    ;;
  cassandra)
    collect_cassandra
    ;;
  cosmosdb)
    collect_cosmosdb
    ;;
  *)
    echo "Unsupported engine: ${ENGINE}" | tee -a "${LOG_FILE}"
    exit 1
    ;;
esac

if [[ -f "${REPORT_SQL}" ]]; then
  {
    echo
    echo "## Engine Report SQL Output"
    echo
    cat "${REPORT_SQL}"
  } >> "${SNAPSHOT_OUT}"
fi

render_html

echo "Snapshot written: ${SNAPSHOT_OUT}" | tee -a "${LOG_FILE}"
echo "Detailed TXT report: ${REPORT_TXT}" | tee -a "${LOG_FILE}"
echo "Detailed HTML report: ${REPORT_HTML}" | tee -a "${LOG_FILE}"

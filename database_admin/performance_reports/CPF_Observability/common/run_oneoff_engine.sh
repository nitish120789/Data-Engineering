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
  append_section "Instance Identity and Version" run_mysql_sql "SELECT NOW() AS collected_at_utc, @@hostname AS hostname, @@port AS port, @@version AS version, @@version_comment AS flavor, @@read_only AS read_only, @@global.gtid_mode AS gtid_mode"
  append_section "Server Configuration Key Variables" run_mysql_sql "SHOW GLOBAL VARIABLES WHERE Variable_name IN ('max_connections','max_allowed_packet','innodb_buffer_pool_size','innodb_buffer_pool_instances','innodb_log_file_size','innodb_log_buffer_size','innodb_flush_method','innodb_flush_log_at_trx_commit','sync_binlog','binlog_format','slow_query_log','long_query_time','table_open_cache','thread_cache_size','wait_timeout','interactive_timeout','transaction_isolation','innodb_io_capacity','innodb_io_capacity_max','innodb_read_io_threads','innodb_write_io_threads','innodb_autoinc_lock_mode')"
  append_section "Database Inventory and Size" run_mysql_sql "SELECT table_schema AS db_name, COUNT(*) AS table_count, ROUND(SUM(data_length)/1024/1024,2) AS data_mb, ROUND(SUM(index_length)/1024/1024,2) AS index_mb, ROUND(SUM(data_length+index_length)/1024/1024,2) AS total_mb, ROUND(SUM(data_free)/1024/1024,2) AS free_mb FROM information_schema.tables WHERE table_schema NOT IN ('performance_schema','information_schema','sys','mysql') GROUP BY table_schema ORDER BY total_mb DESC"
  append_section "Connection Pressure and Session Mix" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_running','Threads_connected','Threads_cached','Max_used_connections','Connections','Aborted_connects','Aborted_clients','Connection_errors_max_connections'); SELECT USER, HOST, DB, COMMAND, COUNT(*) AS cnt FROM information_schema.processlist GROUP BY USER, HOST, DB, COMMAND ORDER BY cnt DESC LIMIT 20"
  append_section "Workload Throughput Counters" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Questions','Com_select','Com_insert','Com_update','Com_delete','Com_replace','Com_commit','Com_rollback','Com_begin','Slow_queries','Handler_read_key','Handler_read_next','Handler_read_rnd','Handler_read_rnd_next','Select_full_join','Select_scan','Select_range')"
  append_section "Temporary Objects and Sort Pressure" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Created_tmp_tables','Created_tmp_disk_tables','Created_tmp_files','Sort_rows','Sort_merge_passes','Sort_scan','Sort_range')"
  append_section "InnoDB Buffer Pool Health" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads','Innodb_buffer_pool_pages_total','Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_dirty','Innodb_buffer_pool_wait_free','Innodb_buffer_pool_write_requests','Innodb_buffer_pool_pages_flushed'); SELECT ROUND(100*(1 - SUM(IF(VARIABLE_NAME='Innodb_buffer_pool_reads',VARIABLE_VALUE,0)) / NULLIF(SUM(IF(VARIABLE_NAME='Innodb_buffer_pool_read_requests',VARIABLE_VALUE,0)),0)),4) AS buffer_pool_hit_pct FROM performance_schema.global_status WHERE VARIABLE_NAME IN ('Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests')"
  append_section "InnoDB IO and Log Pressure" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_data_reads','Innodb_data_writes','Innodb_data_fsyncs','Innodb_data_pending_reads','Innodb_data_pending_writes','Innodb_log_waits','Innodb_log_writes','Innodb_log_write_requests','Innodb_os_log_written','Innodb_os_log_fsyncs','Innodb_pages_read','Innodb_pages_written','Innodb_pages_created','Innodb_rows_read','Innodb_rows_inserted','Innodb_rows_updated','Innodb_rows_deleted')"
  append_section "Statement Wait Events" run_mysql_sql "SELECT EVENT_NAME, COUNT_STAR AS wait_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_wait_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_wait_ms, ROUND(MAX_TIMER_WAIT/1000000000,3) AS max_wait_ms FROM performance_schema.events_waits_summary_global_by_event_name WHERE COUNT_STAR > 0 AND EVENT_NAME NOT LIKE '%idle%' ORDER BY SUM_TIMER_WAIT DESC LIMIT 30"
  append_section "Lock Wait and Deadlock Counters" run_mysql_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_row_lock_current_waits','Innodb_row_lock_waits','Innodb_row_lock_time','Innodb_row_lock_time_avg','Innodb_row_lock_time_max','Innodb_deadlocks','Table_locks_waited','Table_locks_immediate')"
  append_section "Active Sessions (ASH Analogue)" run_mysql_sql "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 320) AS SQL_TEXT FROM information_schema.processlist WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 30"
  append_section "Active Lock Wait Chains" run_mysql_sql "SELECT r.trx_id AS waiting_trx_id, b.trx_id AS blocking_trx_id, r.trx_mysql_thread_id AS waiting_thread, b.trx_mysql_thread_id AS blocking_thread, TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds, LEFT(r.trx_query, 240) AS waiting_query, LEFT(b.trx_query, 240) AS blocking_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id ORDER BY waiting_seconds DESC LIMIT 20"
  append_section "Long-Running Transactions" run_mysql_sql "SELECT trx_id, trx_mysql_thread_id AS thread_id, trx_state, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_seconds, trx_rows_locked, trx_rows_modified, LEFT(trx_query, 240) AS sql_text, trx_operation_state, trx_tables_in_use, trx_tables_locked FROM information_schema.innodb_trx ORDER BY trx_started ASC LIMIT 20"
  append_section "Top SQL by Total Time" run_mysql_sql "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, ROUND(MAX_TIMER_WAIT/1000000000,3) AS max_ms, SUM_ROWS_EXAMINED AS rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 25"
  append_section "Top SQL by Execution Count" run_mysql_sql "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, SUM_ROWS_EXAMINED AS total_rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY COUNT_STAR DESC LIMIT 25"
  append_section "Top SQL by Rows Examined" run_mysql_sql "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_ROWS_EXAMINED AS total_rows_examined, ROUND(SUM_ROWS_EXAMINED/NULLIF(COUNT_STAR,0),0) AS avg_rows_examined, SUM_NO_INDEX_USED AS no_index_used, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_ROWS_EXAMINED DESC LIMIT 25"
  append_section "Top SQL by Temp Disk Tables" run_mysql_sql "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables, SUM_CREATED_TMP_TABLES AS tmp_tables, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, SUM_SORT_MERGE_PASSES AS sort_merge_passes FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_CREATED_TMP_DISK_TABLES DESC LIMIT 20"
  append_section "Top SQL by Errors and Warnings" run_mysql_sql "SELECT LEFT(DIGEST_TEXT, 240) AS sql_text, SCHEMA_NAME AS db, COUNT_STAR AS exec_count, SUM_ERRORS AS total_errors, SUM_WARNINGS AS total_warnings, SUM_ROWS_EXAMINED AS rows_examined FROM performance_schema.events_statements_summary_by_digest WHERE SUM_ERRORS > 0 OR SUM_WARNINGS > 0 ORDER BY SUM_ERRORS DESC, SUM_WARNINGS DESC LIMIT 20"
  append_section "Table IO Latency" run_mysql_sql "SELECT OBJECT_SCHEMA AS db, OBJECT_NAME AS table_name, COUNT_READ, COUNT_WRITE, COUNT_FETCH, COUNT_INSERT, COUNT_UPDATE, COUNT_DELETE, ROUND(SUM_TIMER_READ/1000000000000,3) AS total_read_s, ROUND(SUM_TIMER_WRITE/1000000000000,3) AS total_write_s FROM performance_schema.table_io_waits_summary_by_table WHERE OBJECT_SCHEMA NOT IN ('performance_schema','information_schema','sys','mysql') AND (COUNT_READ + COUNT_WRITE) > 0 ORDER BY (SUM_TIMER_READ + SUM_TIMER_WRITE) DESC LIMIT 30"
  append_section "User and Host Activity Summary" run_mysql_sql "SELECT USER, HOST, DB, SUM(CASE WHEN COMMAND='Query' THEN 1 ELSE 0 END) AS active_queries, SUM(CASE WHEN COMMAND='Sleep' THEN 1 ELSE 0 END) AS idle_sessions, COUNT(*) AS total_sessions, MAX(TIME) AS max_query_time_s FROM information_schema.processlist GROUP BY USER, HOST, DB ORDER BY total_sessions DESC, active_queries DESC LIMIT 20"
  append_section "Schema Size and Top Tables" run_mysql_sql "SELECT table_schema AS db, table_name, engine, table_rows, ROUND(data_length/1024/1024,2) AS data_mb, ROUND(index_length/1024/1024,2) AS index_mb, ROUND((data_length+index_length)/1024/1024,2) AS total_mb, ROUND(data_free/1024/1024,2) AS free_mb FROM information_schema.tables WHERE table_schema NOT IN ('performance_schema','information_schema','sys','mysql') ORDER BY (data_length+index_length) DESC LIMIT 30"
  append_section "Binary Log and GTID Status" run_mysql_sql "SHOW MASTER STATUS; SHOW BINARY LOGS"
  append_section "Replication Status (MySQL 8+)" run_mysql_sql "SHOW REPLICA STATUS"
  append_section "Replication Status (MySQL 5.7 Legacy)" run_mysql_sql "SHOW SLAVE STATUS"
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
  append_section "Server Configuration Key Parameters" run_psql_sql "SELECT name, setting, unit, context, source FROM pg_settings WHERE name IN ('max_connections','shared_buffers','effective_cache_size','work_mem','maintenance_work_mem','wal_level','max_wal_size','checkpoint_timeout','checkpoint_completion_target','random_page_cost','effective_io_concurrency','autovacuum','autovacuum_max_workers','autovacuum_naptime','track_io_timing') ORDER BY name;"
  append_section "Database Inventory and Size" run_psql_sql "SELECT d.datname, pg_catalog.pg_get_userbyid(d.datdba) AS owner, d.datistemplate, d.datallowconn, pg_size_pretty(pg_database_size(d.datname)) AS db_size, s.numbackends FROM pg_database d LEFT JOIN pg_stat_database s ON d.datname = s.datname ORDER BY pg_database_size(d.datname) DESC;"
  append_section "Connection Pressure and Session Mix" run_psql_sql "SELECT now() - pg_postmaster_start_time() AS uptime, (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_connections, (SELECT count(*) FROM pg_stat_activity) AS current_connections, (SELECT count(*) FROM pg_stat_activity WHERE state='active') AS active_connections; SELECT usename, application_name, client_addr, state, COUNT(*) AS sessions FROM pg_stat_activity GROUP BY usename, application_name, client_addr, state ORDER BY sessions DESC LIMIT 30;"
  append_section "Workload Throughput and Transaction Counters" run_psql_sql "SELECT datname, xact_commit, xact_rollback, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, blks_read, blks_hit, temp_files, temp_bytes, deadlocks FROM pg_stat_database ORDER BY xact_commit + xact_rollback DESC LIMIT 30;"
  append_section "Temporary Objects and Sort Pressure" run_psql_sql "SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes, blk_read_time, blk_write_time FROM pg_stat_database ORDER BY temp_bytes DESC LIMIT 20;"
  append_section "Buffer Cache and IO Hit Ratios" run_psql_sql "SELECT datname, ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct, blks_read, blks_hit FROM pg_stat_database ORDER BY cache_hit_pct ASC NULLS LAST;"
  append_section "WAL and Checkpoint Pressure" run_psql_sql "SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, checkpoint_sync_time, buffers_checkpoint, buffers_clean, maxwritten_clean, buffers_backend, buffers_backend_fsync, buffers_alloc FROM pg_stat_bgwriter; SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full, stats_reset FROM pg_stat_wal;"
  append_section "Wait Event Profile" run_psql_sql "SELECT wait_event_type, wait_event, COUNT(*) AS session_count FROM pg_stat_activity WHERE wait_event_type IS NOT NULL GROUP BY wait_event_type, wait_event ORDER BY session_count DESC, wait_event_type LIMIT 30;"
  append_section "Active Sessions (ASH Analogue)" run_psql_sql "SELECT pid, usename, datname, application_name, client_addr, backend_type, state, wait_event_type, wait_event, now() - query_start AS duration, LEFT(query, 320) AS query FROM pg_stat_activity WHERE state <> 'idle' ORDER BY duration DESC LIMIT 40;"
  append_section "Blocking Chains" run_psql_sql "SELECT blocked.pid AS blocked_pid, blocker.pid AS blocker_pid, blocked.usename AS blocked_user, blocker.usename AS blocker_user, blocked.wait_event_type AS blocked_wait_type, blocked.wait_event AS blocked_wait_event, now() - blocked.query_start AS blocked_for, LEFT(blocked.query, 220) AS blocked_query, LEFT(blocker.query, 220) AS blocker_query FROM pg_stat_activity blocked JOIN pg_stat_activity blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) ORDER BY blocked_for DESC LIMIT 30;"
  append_section "Long-Running Transactions" run_psql_sql "SELECT pid, usename, datname, state, now() - xact_start AS xact_age, now() - query_start AS query_age, wait_event_type, wait_event, LEFT(query, 320) AS query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY xact_start ASC LIMIT 30;"
  append_section "Top SQL by Total Time" run_psql_sql "SELECT queryid, calls, ROUND(total_exec_time::numeric,2) AS total_ms, ROUND(mean_exec_time::numeric,2) AS mean_ms, ROUND(max_exec_time::numeric,2) AS max_ms, rows, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 25;"
  append_section "Top SQL by Execution Count" run_psql_sql "SELECT queryid, calls, ROUND(mean_exec_time::numeric,2) AS mean_ms, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY calls DESC LIMIT 25;"
  append_section "Top SQL by Shared Block Reads" run_psql_sql "SELECT queryid, calls, shared_blks_read, shared_blks_hit, temp_blks_read, temp_blks_written, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY shared_blks_read DESC LIMIT 25;"
  append_section "Top SQL by Temp Blocks" run_psql_sql "SELECT queryid, calls, temp_blks_read, temp_blks_written, ROUND(total_exec_time::numeric,2) AS total_ms, LEFT(query, 240) AS query FROM pg_stat_statements ORDER BY (temp_blks_read + temp_blks_written) DESC LIMIT 20;"
  append_section "Table IO and Heap/Index Access" run_psql_sql "SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch, n_tup_ins, n_tup_upd, n_tup_del, n_dead_tup, vacuum_count, autovacuum_count FROM pg_stat_user_tables ORDER BY (seq_tup_read + idx_tup_fetch) DESC LIMIT 30;"
  append_section "Index Usage and Bloat Indicators" run_psql_sql "SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size FROM pg_stat_user_indexes ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC LIMIT 30;"
  append_section "Vacuum and Analyze Health" run_psql_sql "SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze, vacuum_count, autovacuum_count, analyze_count, autoanalyze_count FROM pg_stat_user_tables ORDER BY n_dead_tup DESC NULLS LAST LIMIT 30; SELECT pid, datname, relid::regclass AS relation, phase, heap_blks_total, heap_blks_scanned, heap_blks_vacuumed, index_vacuum_count, max_dead_tuples, num_dead_tuples FROM pg_stat_progress_vacuum;"
  append_section "Lock Inventory and Contention" run_psql_sql "SELECT locktype, mode, granted, COUNT(*) AS lock_count FROM pg_locks GROUP BY locktype, mode, granted ORDER BY lock_count DESC;"
  append_section "Replication and Slot Health" run_psql_sql "SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication; SELECT slot_name, slot_type, active, restart_lsn, wal_status, safe_wal_size FROM pg_replication_slots;"
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
  append_section "Instance Identity and Version" oracle_sql_block "SELECT SYSTIMESTAMP AT TIME ZONE 'UTC' AS collected_at_utc FROM dual; SELECT host_name, instance_name, version, startup_time, status, parallel FROM v\$instance; SELECT name, db_unique_name, open_mode, log_mode, force_logging, platform_name, cdb FROM v\$database;"
  append_section "Initialization Parameters (Key)" oracle_sql_block "SELECT name, value, isdefault, issys_modifiable FROM v\$parameter WHERE name IN ('processes','sessions','open_cursors','cursor_sharing','optimizer_mode','db_cache_size','shared_pool_size','pga_aggregate_target','pga_aggregate_limit','sga_target','sga_max_size','filesystemio_options','db_writer_processes','log_buffer','undo_retention') ORDER BY name;"
  append_section "Database Inventory and Size" oracle_sql_block "SELECT owner, segment_type, ROUND(SUM(bytes)/1024/1024,2) AS size_mb FROM dba_segments GROUP BY owner, segment_type ORDER BY size_mb DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Connection Pressure and Session Mix" oracle_sql_block "SELECT resource_name, current_utilization, max_utilization, limit_value FROM v\$resource_limit WHERE resource_name IN ('processes','sessions','transactions'); SELECT NVL(username,'[BACKGROUND]') AS username, status, type, COUNT(*) AS sessions FROM v\$session GROUP BY NVL(username,'[BACKGROUND]'), status, type ORDER BY sessions DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Workload Throughput Counters" oracle_sql_block "SELECT name, value FROM v\$sysstat WHERE name IN ('user commits','user rollbacks','execute count','parse count (total)','parse count (hard)','opened cursors current','logons cumulative','redo size','redo writes','db block changes','physical reads','physical writes','session logical reads') ORDER BY name;"
  append_section "Memory (SGA/PGA) Health" oracle_sql_block "SELECT name, ROUND(value/1024/1024,2) AS value_mb FROM v\$sga; SELECT component, current_size/1024/1024 AS current_mb, min_size/1024/1024 AS min_mb, max_size/1024/1024 AS max_mb FROM v\$sga_dynamic_components ORDER BY current_size DESC; SELECT name, value FROM v\$pgastat WHERE name IN ('aggregate PGA target parameter','aggregate PGA auto target','global memory bound','total PGA allocated','total PGA inuse','over allocation count');"
  append_section "Wait Events (Top)" oracle_sql_block "SELECT event, wait_class, total_waits, time_waited, average_wait FROM v\$system_event WHERE wait_class <> 'Idle' ORDER BY time_waited DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Wait Class Profile" oracle_sql_block "SELECT wait_class, total_waits, time_waited FROM v\$system_wait_class WHERE wait_class <> 'Idle' ORDER BY time_waited DESC;"
  append_section "Active Sessions (ASH Analogue)" oracle_sql_block "SELECT sid, serial#, username, status, state, event, wait_class, blocking_session, seconds_in_wait, sql_id, module, machine FROM v\$session WHERE type='USER' AND status='ACTIVE' ORDER BY seconds_in_wait DESC FETCH FIRST 40 ROWS ONLY;"
  append_section "Blocking Chains and Locks" oracle_sql_block "SELECT s.sid, s.serial#, s.username, s.status, s.event, s.blocking_session, s.seconds_in_wait, s.sql_id FROM v\$session s WHERE s.blocking_session IS NOT NULL OR s.sid IN (SELECT l1.sid FROM v\$lock l1 JOIN v\$lock l2 ON l1.id1=l2.id1 AND l1.id2=l2.id2 WHERE l1.block = 1 AND l2.request > 0) ORDER BY s.seconds_in_wait DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Long Operations" oracle_sql_block "SELECT sid, serial#, opname, target_desc, sofar, totalwork, units, elapsed_seconds, time_remaining FROM v\$session_longops WHERE totalwork > 0 AND sofar < totalwork ORDER BY elapsed_seconds DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Top SQL by Elapsed Time" oracle_sql_block "SELECT * FROM (SELECT sql_id, plan_hash_value, elapsed_time/1000000 AS elapsed_s, cpu_time/1000000 AS cpu_s, executions, rows_processed, buffer_gets, disk_reads, parse_calls FROM v\$sqlstats ORDER BY elapsed_time DESC) WHERE ROWNUM <= 25;"
  append_section "Top SQL by CPU Time" oracle_sql_block "SELECT * FROM (SELECT sql_id, plan_hash_value, cpu_time/1000000 AS cpu_s, elapsed_time/1000000 AS elapsed_s, executions, buffer_gets, disk_reads, rows_processed FROM v\$sqlstats ORDER BY cpu_time DESC) WHERE ROWNUM <= 25;"
  append_section "Top SQL by Buffer Gets" oracle_sql_block "SELECT * FROM (SELECT sql_id, buffer_gets, disk_reads, executions, elapsed_time/1000000 AS elapsed_s, cpu_time/1000000 AS cpu_s FROM v\$sqlstats ORDER BY buffer_gets DESC) WHERE ROWNUM <= 25;"
  append_section "Top SQL by Disk Reads" oracle_sql_block "SELECT * FROM (SELECT sql_id, disk_reads, buffer_gets, executions, elapsed_time/1000000 AS elapsed_s FROM v\$sqlstats ORDER BY disk_reads DESC) WHERE ROWNUM <= 25;"
  append_section "Cursor and Parse Pressure" oracle_sql_block "SELECT name, value FROM v\$sysstat WHERE name IN ('parse count (total)','parse count (hard)','session cursor cache hits','opened cursors cumulative','opened cursors current') ORDER BY name;"
  append_section "Redo and Archive Pressure" oracle_sql_block "SELECT name, value FROM v\$sysstat WHERE name IN ('redo size','redo writes','redo blocks written','redo write time','redo wastage') ORDER BY name; SELECT thread#, COUNT(*) AS switches, MIN(first_time) AS first_switch, MAX(first_time) AS last_switch FROM v\$log_history GROUP BY thread# ORDER BY thread#;"
  append_section "Undo and Transaction Health" oracle_sql_block "SELECT begin_time, end_time, tuned_undoretention, ssolderrcnt, nospaceerrcnt, unxpstealcnt, expblkreucnt FROM v\$undostat ORDER BY begin_time DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Datafile IO Latency" oracle_sql_block "SELECT df.file_id, df.file_name, fs.phyrds, fs.phywrts, fs.readtim, fs.writetim, CASE WHEN fs.phyrds = 0 THEN NULL ELSE ROUND(fs.readtim/fs.phyrds,3) END AS avg_read_ms, CASE WHEN fs.phywrts = 0 THEN NULL ELSE ROUND(fs.writetim/fs.phywrts,3) END AS avg_write_ms FROM v\$filestat fs JOIN dba_data_files df ON fs.file# = df.file_id ORDER BY (NVL(fs.readtim,0)+NVL(fs.writetim,0)) DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Tablespace Utilization" oracle_sql_block "SELECT tablespace_name, used_space*8/1024 AS used_mb, tablespace_size*8/1024 AS total_mb, ROUND(used_percent,2) AS used_percent FROM dba_tablespace_usage_metrics ORDER BY used_percent DESC;"
  append_section "Top Segments by Size" oracle_sql_block "SELECT owner, segment_name, segment_type, tablespace_name, ROUND(bytes/1024/1024,2) AS size_mb FROM dba_segments ORDER BY bytes DESC FETCH FIRST 30 ROWS ONLY;"
  append_section "Invalid Objects and Object Churn" oracle_sql_block "SELECT owner, object_type, status, COUNT(*) AS object_count FROM dba_objects GROUP BY owner, object_type, status ORDER BY object_count DESC FETCH FIRST 40 ROWS ONLY;"
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

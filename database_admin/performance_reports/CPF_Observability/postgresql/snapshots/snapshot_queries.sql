-- PostgreSQL CPF_Observability snapshot dataset
SELECT now() AS captured_at,
       inet_server_addr() AS server_ip,
       inet_server_port() AS server_port,
       version() AS version;

SELECT datname, numbackends, xact_commit, xact_rollback,
       blks_hit, blks_read, temp_files, temp_bytes, deadlocks
FROM pg_stat_database
ORDER BY xact_commit + xact_rollback DESC;

SELECT wait_event_type, wait_event, COUNT(*) AS session_count
FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL
GROUP BY wait_event_type, wait_event
ORDER BY session_count DESC
LIMIT 30;

SELECT pid, usename, datname, state, wait_event_type, wait_event,
       now() - query_start AS query_age, LEFT(query, 300) AS query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start
LIMIT 50;

SELECT queryid, calls,
       ROUND(total_exec_time::numeric, 2) AS total_exec_ms,
       ROUND(mean_exec_time::numeric, 2) AS mean_exec_ms,
       shared_blks_read, shared_blks_hit,
       temp_blks_read, temp_blks_written,
       LEFT(query, 300) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 50;

SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       blocked.usename AS blocked_user,
       blocker.usename AS blocker_user,
       now() - blocked.query_start AS blocked_for,
       LEFT(blocked.query, 220) AS blocked_query,
       LEFT(blocker.query, 220) AS blocker_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
ORDER BY blocked_for DESC;

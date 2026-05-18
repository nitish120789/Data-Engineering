-- Transaction Lock Detection and Timeout Guard
-- Prevents long-running AI-generated queries from causing global locks

SET NOCOUNT ON;

PRINT '=== Transaction Lock and Timeout Analysis ===';
PRINT '';

-- Blocking Chain Detection
PRINT '[BLOCKING] Current Blocking Chains';
PRINT '';

WITH blocking_chain AS (
    SELECT
        er.session_id,
        er.blocking_session_id,
        er.command,
        es.login_name,
        es.host_name,
        er.start_time,
        DATEDIFF(SECOND, er.start_time, GETUTCDATE()) AS wait_seconds,
        SUBSTRING(st.text, (er.statement_start_offset / 2) + 1,
            CASE WHEN er.statement_end_offset = -1 THEN LEN(st.text)
            ELSE (er.statement_end_offset - er.statement_start_offset) / 2 END) AS query_text,
        er.wait_duration_ms,
        er.wait_type
    FROM sys.dm_exec_requests er
    JOIN sys.dm_exec_sessions es ON es.session_id = er.session_id
    CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) st
    WHERE er.session_id > 50
)
SELECT
    session_id,
    blocking_session_id,
    command,
    login_name,
    wait_seconds,
    wait_duration_ms,
    wait_type,
    SUBSTRING(query_text, 1, 100) AS query_preview
FROM blocking_chain
WHERE blocking_session_id > 0 OR wait_seconds > 5
ORDER BY session_id;

PRINT '';

-- Long-Running Transactions
PRINT '[ALERT] Long-Running Transactions (>60 seconds)';
PRINT '';

SELECT
    er.session_id,
    es.login_name,
    es.host_name,
    er.command,
    DATEDIFF(SECOND, er.start_time, GETUTCDATE()) AS running_seconds,
    er.wait_type,
    er.wait_duration_ms,
    SUBSTRING(st.text, (er.statement_start_offset / 2) + 1,
        CASE WHEN er.statement_end_offset = -1 THEN LEN(st.text)
        ELSE (er.statement_end_offset - er.statement_start_offset) / 2 END) AS query_text,
    CASE
        WHEN DATEDIFF(SECOND, er.start_time, GETUTCDATE()) > 300 THEN 'KILL_RECOMMENDED'
        WHEN DATEDIFF(SECOND, er.start_time, GETUTCDATE()) > 120 THEN 'MONITOR_CLOSELY'
        ELSE 'ACCEPTABLE'
    END AS action
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es ON es.session_id = er.session_id
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) st
WHERE er.session_id > 50
  AND DATEDIFF(SECOND, er.start_time, GETUTCDATE()) > 60
ORDER BY running_seconds DESC;

PRINT '';

-- Open Transactions
PRINT '[ALERT] Open Transactions';
PRINT '';

SELECT
    st.session_id,
    es.login_name,
    es.program_name,
    st.transaction_begin_time,
    DATEDIFF(SECOND, st.transaction_begin_time, GETUTCDATE()) AS open_seconds,
    st.transaction_state,
    CASE
        WHEN DATEDIFF(SECOND, st.transaction_begin_time, GETUTCDATE()) > 300 THEN 'CRITICAL'
        WHEN DATEDIFF(SECOND, st.transaction_begin_time, GETUTCDATE()) > 120 THEN 'WARNING'
        ELSE 'NORMAL'
    END AS severity
FROM sys.dm_tran_session_transactions st
JOIN sys.dm_exec_sessions es ON es.session_id = st.session_id
WHERE st.session_id > 50
ORDER BY open_seconds DESC;

PRINT '';

-- Lock Distribution
PRINT '[MONITORING] Lock Distribution by Resource';
PRINT '';

SELECT TOP 20
    tl.resource_type,
    CASE WHEN tl.resource_type = 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id)
         WHEN tl.resource_type = 'PAGE' THEN 'Page Lock on DB'
         ELSE 'Other'
    END AS resource_name,
    tl.request_mode,
    COUNT(*) AS lock_count,
    COUNT(DISTINCT tl.request_session_id) AS session_count
FROM sys.dm_tran_locks tl
WHERE database_id = DB_ID()
GROUP BY tl.resource_type, tl.resource_associated_entity_id, tl.request_mode
ORDER BY lock_count DESC;

PRINT '';

-- Deadlock Summary (if available)
PRINT '[HISTORY] Recent Deadlock Events';
PRINT '';

IF OBJECT_ID('tempdb..deadlock_events', 'U') IS NOT NULL
BEGIN
    SELECT TOP 20
        deadlock_time,
        process_id,
        victim_spid,
        blocked_spid,
        query_text
    FROM tempdb..deadlock_events
    ORDER BY deadlock_time DESC;
END
ELSE
BEGIN
    PRINT 'Enable Extended Events or trace to capture deadlock details.';
    PRINT 'Query: xp_readerrorlog for deadlock information.';
END;

PRINT '';

PRINT '=== Lock Analysis Complete ===';
PRINT '';
PRINT 'Recommended Actions:';
PRINT '  1. Investigate blocking chains (blocker -> waiter relationships)';
PRINT '  2. Kill long-running queries if >5 minutes without progress';
PRINT '  3. Review query plans for table scans causing exclusive locks';
PRINT '  4. Implement query timeout policy in application connection strings';
PRINT '  5. Set statement timeout: SET LOCK_TIMEOUT 30000 (milliseconds)';

# Lock Contention, Deadlock Triage, and Resolution Runbook

## Summary

- Purpose: diagnose and resolve blocking sessions, deadlocks, and lock contention without requiring database restart
- Scope: production OLTP workloads (Tier-0, Tier-1)
- Owner: DBA on-call / DBRE
- Escalation: incident commander if unresolved after 10 minutes of intervention

## Impact and Reliability Context

- Lock contention manifests as latency increase, timeouts, and connection pool exhaustion
- Deadlocks cause application-level retries and can cascade if client-side retry logic is aggressive
- Blocking sessions reduce throughput and are often a symptom of query inefficiency or lock escalation
- Reliability goal: reduce lock-related incident mean-time-to-resolution (MTTR) to < 10 minutes

## Preconditions and Risk Gates

- Ensure access to system-level queries (e.g., database admin role)
- Do not terminate sessions without incident commander awareness
- Always capture query text and session context before termination
- Have rollback plan if corrective action causes further degradation

## Preparation

1. Record UTC incident start time
2. Identify affected application/workload (from error logs or application team)
3. Prepare monitoring dashboard: session activity, wait events, locks
4. Brief incident commander and application owner

## Procedure

### Phase 1: Rapid Assessment (2-5 minutes)

Goal: determine whether issue is blocking, deadlock, or lock escalation.

#### Step 1: Confirm the Problem

**PostgreSQL**:

```sql
-- Are there sessions in 'idle in transaction' state (common blocker)?
SELECT pid, usename, state, query_start, now() - query_start AS idle_duration, query
FROM pg_stat_activity
WHERE state LIKE 'idle%'
ORDER BY query_start;

-- Active blocking relationships
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query,
       blocked_activity.application_name,
       blocked_locks.mode AS lock_mode
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.pid <> blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

**SQL Server**:

```sql
-- Find blocked sessions
SELECT r.blocking_session_id, r.session_id, r.command, r.status, r.wait_time_ms,
       SUBSTRING(st.text, (r.statement_start_offset / 2) + 1, 
       ((CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(st.text)
             ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.blocking_session_id <> 0;

-- Check for deadlock graph in error log
SELECT * FROM sys.dm_tran_database_transactions
WHERE database_id = DB_ID();
```

**MySQL**:

```sql
-- Active lock waits
SELECT * FROM information_schema.innodb_lock_waits;

-- Sessions and locks
SELECT * FROM information_schema.innodb_trx;

-- More detail on waiting transactions
SELECT r.trx_id, r.trx_state, r.trx_started, r.trx_query
FROM information_schema.innodb_trx r
JOIN information_schema.innodb_lock_waits w ON r.trx_id = w.requesting_trx_id;
```

**Oracle**:

```sql
-- Blocked sessions
SELECT b.sid AS blocked_sid, b.username,
       bl.sid AS blocker_sid, bl.username,
       b.seconds_in_wait,
       b.sql_id, bl.sql_id
FROM v$session b
JOIN v$session bl ON b.blocking_session = bl.sid
WHERE b.blocking_session IS NOT NULL;

-- Lock details
SELECT * FROM v$lock
WHERE type NOT IN ('MR', 'RT'); -- Filter out background locks
```

#### Step 2: Count Impact Scope

How many sessions are blocked?

```sql
-- PostgreSQL
SELECT COUNT(*) AS blocked_session_count
FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL
  AND query NOT LIKE 'autovacuum%';
```

Decision point:
- **1-2 blocked sessions**: likely data lock; investigate query and blocker
- **10+ blocked sessions**: connection pool exhaustion likely; consider kill-blocker-and-retry strategy
- **Deadlock visible in logs**: proceed to Phase 2 (deadlock section)

### Phase 2: Deep Diagnosis (5-10 minutes)

#### Blocker Analysis

Extract the blocking query:

**PostgreSQL**:

```sql
-- Get full query text of blocker
SELECT pid, query, state, now() - query_start AS duration
FROM pg_stat_activity
WHERE pid = <blocker_pid>;

-- Get lock mode (ExclusiveLock vs ShareLock etc)
SELECT locktype, relation::regclass, mode, granted
FROM pg_locks
WHERE pid = <blocker_pid>;
```

**SQL Server**:

```sql
-- Get the SQL being held
SELECT * FROM sys.dm_exec_requests
WHERE session_id = <blocker_session_id>;
```

#### Root Cause Determination

Ask: **Why is the blocker session holding this lock?**

Common patterns:

1. **Long-running transaction** (idle in transaction):
   - App opened transaction and didn't commit/rollback
   - Cause: exception handler didn't close transaction
   - Resolution: kill session and ask app team to fix code

2. **Slow query with lock escalation**:
   - Query accessing many rows, lock manager escalated to table lock
   - Cause: inefficient query plan or excessive row count
   - Resolution: optimize query (add index) or rewrite

3. **Explicit lock hold** (application or batch job):
   - App intentionally locked table (e.g., `SELECT ... FOR UPDATE NOWAIT`)
   - Cause: long-running batch updating denormalized cache
   - Resolution: kill if non-critical; coordinate with app team

4. **DDL operation**:
   - Schema change holding access exclusive lock
   - Cause: ALTER TABLE or CREATE INDEX without CONCURRENTLY
   - Resolution: wait for DDL to complete or cancel if error occurred

#### Decision Point: Continue or Kill?

| Blocker Type | Continue Duration | Decision |
|---|---|---|
| Long-running transaction (idle) | Any | Kill session (app tier bug) |
| Slow query | < 2 min | Wait; get app to retry |
| Slow query | > 2 min | Kill if not critical; else optimize |
| DDL | < 5 min | Wait |
| DDL | > 5 min | Evaluate CANCEL; risk of incomplete cleanup |

### Phase 3: Intervention (2-5 minutes)

#### Option A: Wait and Monitor

If blocker appears to be making progress:

1. Monitor blocking chain depth minute-over-minute
2. Set alert: if blocked session count exceeds 20 after 2 minutes, escalate to kill
3. Communicate ETA to incident commander

#### Option B: Terminate Blocker Session

**PostgreSQL**:

```sql
-- Graceful termination (client will see connection closed)
SELECT pg_terminate_backend(<blocker_pid>);

-- If terminate fails, use pg_cancel_backend first
SELECT pg_cancel_backend(<blocker_pid>);

-- Verify termination
SELECT count(*) FROM pg_stat_activity WHERE pid = <blocker_pid>;
```

**SQL Server**:

```sql
-- Terminate with rollback (immediate)
KILL <session_id>;

-- Verify termination
SELECT count(*) FROM sys.dm_exec_sessions WHERE session_id = <session_id>;
```

**MySQL**:

```sql
-- Terminate connection (implicit rollback)
KILL <connection_id>;

-- Or via a query (if connected to same instance)
KILL QUERY <connection_id>;
```

**Oracle**:

```sql
-- Terminate session
ALTER SYSTEM KILL SESSION '<sid>,<serial>' IMMEDIATE;

-- Or via ORADEBUG (requires additional setup)
```

#### Option C: Resolve Deadlock (if applicable)

Deadlock detection varies by engine:

**PostgreSQL** (automatic detection + automatic victim rollback):

```sql
-- Deadlock is automatically detected; one transaction rolled back
-- Check recent logs:
SELECT message FROM pg_log WHERE message LIKE '%deadlock%' ORDER BY logged DESC LIMIT 10;

-- Application must retry the rolled-back transaction
```

**SQL Server** (automatic detection + victim chosen by database):

```sql
-- Deadlock graph is written to error log
-- Check error log for deadlock graph and identify victims
EXEC sp_readerrorlog;

-- Application must retry

-- Or capture deadlocks in trace/Extended Events
CREATE EVENT SESSION deadlock_monitoring ON SERVER
  ADD EVENT sqlserver.xml_deadlock_report
  ADD TARGET event_file(FILENAME='/var/opt/mssql/deadlock.xel')
WITH (STARTUP_STATE=ON);
```

**MySQL** (automatic detection + victim rolled back):

```sql
-- Deadlock is automatic
-- Check InnoDB status for deadlock info
SHOW ENGINE INNODB STATUS\G

-- Application must retry; configure exponential backoff
```

**Oracle** (ORA-04020 error; app must handle retry):

```sql
-- No automatic victim selection; app must handle exception
-- In app code:
BEGIN
  -- attempt transaction
EXCEPTION
  WHEN deadlock_detected THEN
    -- exponential backoff + retry
END;
/
```

### Phase 4: Verification (2-3 minutes)

1. [ ] Blocked session count dropped to zero
2. [ ] Application error rate returned to baseline
3. [ ] Latency p95/p99 returning to SLO band
4. [ ] No new blocking chains forming

```sql
-- Verify clean state (PostgreSQL)
SELECT COUNT(*) AS remaining_blocked
FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL;
```

## Rollback / Escalation

- If terminating session caused cascading issues: escalate to Sev-1 incident response
- If deadlock recurs within 5 minutes: escalate to Sev-1 incident response (likely systematic issue)

## Communication

- **Every 2 minutes during active blocking**: status update to incident bridge ("X blocked sessions, root cause Y, action Z in progress")
- **After resolution**: brief summary email (root cause, action taken, lessons learned link)

## Evidence and Audit Trail

Collect:

1. Session query text of blocker (before and after termination)
2. Lock mode and resource being contended
3. Error log entries (deadlock graph if applicable)
4. Timestamp of resolution
5. Count of affected transactions/connections

## Troubleshooting Deep Dive

### Lock Escalation (SQL Server specific)

SQL Server automatically escalates row-level locks to page or table locks if threshold exceeded.

Diagnosis:

```sql
-- Check lock escalation setting
SELECT * FROM sys.tables WHERE name = 'table_name';
-- Look for lock_escalation column

-- If escalating too aggressively:
ALTER TABLE table_name SET (LOCK_ESCALATION = DISABLE);
```

### Gap Locks and Phantom Reads (MySQL/PostgreSQL)

Some workloads (e.g., range scans with FOR UPDATE) can cause gap locks, preventing inserts in range.

Diagnosis:

```sql
-- PostgreSQL: check lock mode
SELECT * FROM pg_locks WHERE mode LIKE '%Lock%';

-- MySQL: check lock type
SELECT * FROM information_schema.innodb_lock_waits;
```

Resolution: align transaction isolation level with workload requirements.

### Lock Timeout vs Deadlock

- **Lock timeout**: session waiting for lock for longer than timeout threshold (application-tunable)
- **Deadlock**: circular wait dependency between two or more sessions (automatic victim rollback)

Whichever occurs first ends the blocked session.

## Automation Opportunities

- Auto-capture blocker query and notification to incident commander
- Auto-escalation: if blocked_session_count > 20 for > 2 minutes, recommend session termination
- Periodic health check: "idle in transaction" sessions lasting > 5 minutes (potential bug indicator)
- Pattern detection: if same query causes deadlocks repeatedly, flag for query optimization

## Lessons Learned

After each lock-related incident:

1. Was this a known workload pattern or a novel issue?
2. Could query optimization prevent recurrence?
3. Should connection pool settings be adjusted?
4. Does application error handling need improvement (retry logic)?

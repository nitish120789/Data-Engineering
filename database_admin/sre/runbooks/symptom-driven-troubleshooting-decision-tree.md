# Symptom-Driven Troubleshooting Decision Tree

This guide helps diagnostic triage: you observe a symptom, follow the decision tree, and land on the appropriate detailed runbook or diagnostic procedure.

## Overview

```
Symptom → Primary Diagnosis Branch → Root Cause Investigation → Targeted Runbook
```

Diagram description: User observes a symptom, follows branching questions to narrow to a primary diagnosis, then performs root cause investigation before executing targeted resolution runbook.

## Quick Reference by Symptom

| Symptom | Primary Branch | Likely Causes | Runbook |
|---|---|---|---|
| Slow queries (p95 > SLO) | Performance | Missing index, plan regression, statistics stale, lock contention | incident_response.md → Phase 3 (Root Cause) |
| Application timeouts | Availability | Connection exhaustion, lock blocking, CPU saturation | incident_response.md → Phase 2 (Stabilization) |
| Spiky latency (then normal) | Performance | Cache miss, hot spot data access, I/O burst | query analysis + Performance Guide |
| Connection pool errors | Availability | Connection limit exceeded, idle timeout, network partition | Incident Response Phase 2 |
| High CPU, no obvious query | Performance | Autovacuum/maintenance, index maintenance, inefficient plan | Performance Troubleshooting Guide |
| Replication lag growing | Availability | Replica query load, network bottleneck, IO saturation | HA/DR Runbook |
| Lock timeouts (app errors) | Concurrency | Blocking session, deadlock, row lock escalation | lock-deadlock-triage.md |
| Backup failed / missing | Reliability | Storage issue, permission, network path, retention expired | Backup/Restore Drill Runbook |
| Query suddenly 10x slower | Performance | Plan regression, statistics stale, blocking, resource contention | Quick Diagnostics (below) |

## Decision Tree by Primary Symptom

### Branch A: Slow Queries or High Latency

**Symptom**: p95/p99 latency increased OR specific queries report >1s execution time

**Step 1: Is latency uniform or spiky?**

- **Uniform** (consistently slow): → A1 (Regression)
- **Spiky** (normal then slow then normal): → A2 (Resource Contention)

#### A1: Query Regression (Uniform Slowness)

Queries that were fast are now slow; not environmental issue.

**Root cause investigation**:

```sql
-- Did execution plan change?
-- PostgreSQL
EXPLAIN ANALYZE SELECT ...;
-- Compare to EXPLAIN ANALYZE from last week (check git history if query stored)
-- Look for Seq Scan instead of Index Scan, or worse selectivity

-- SQL Server
SET STATISTICS IO ON;
SELECT ...;
SET STATISTICS IO OFF;
-- Check logical reads; compare to baseline

-- Did statistics become stale?
-- PostgreSQL
SELECT schemaname, tablename, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY last_analyze;

-- SQL Server
DBCC SHOW_STATISTICS (table_name, index_name);

-- Was an index recently dropped?
-- Check deployment history / git log for DDL changes
```

**Decision**: 

- If plan changed for worse: re-analyze statistics or add index → update_stats_or_add_index_and_replan
- If index missing: follow index-lifecycle-management.md
- If neither: continue to A2 (contention)

#### A2: Spiky Latency (Resource Contention)

Latency spikes then returns to normal; likely resource exhaustion.

```sql
-- Correlate latency spike with CPU spike?
-- Check monitoring dashboard: did CPU/IOPS spike align with latency?

-- PostgreSQL: check autovacuum during spike
SELECT schemaname, relname, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY last_autovacuum DESC
LIMIT 10;

-- Was a large query running (cache miss)?
SELECT pid, query, now() - query_start AS duration, state
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;

-- Are there lock waits?
SELECT COUNT(*) blocked FROM pg_stat_activity WHERE wait_event_type IS NOT NULL;
```

**Decision**:

- If CPU spike: → Performance troubleshooting (autovacuum, index maintenance)
- If IOPS spike: → I/O bottleneck investigation
- If lock waits detected: → lock-deadlock-triage.md

**Runbook**: incident_response.md (Phase 2: Stabilization, Phase 3: Root Cause)

### Branch B: Connection Errors or Timeouts

**Symptom**: "Connection refused", "Too many connections", "Connection timeout"

**Step 1: Can you connect to database at all?**

- **Cannot connect**: network or database process down
- **Can connect but pool exhausted**: connection leak or load spike

#### B1: Database Process Down or Unreachable

```bash
# Can you ping the database host?
ping database.example.com

# Can you telnet/nc to the port?
nc -zv database.example.com 5432  # PostgreSQL

# Can you connect with admin tools?
psql -U postgres -h database.example.com -d postgres -c "SELECT 1;"

# Check database logs
tail -f /var/log/postgresql/postgresql.log
# Or SQL Server
Get-WinEvent -LogName "Application" | Select-Object -First 50
```

**Decision**:

- If network unreachable: escalate to infrastructure/network team
- If database process down: check if crash; restart if safe; investigate crash logs
- If process up but rejecting connections: → Incident Response (Phase 2)

#### B2: Connection Pool Exhaustion (Database reachable but no connections available)

```sql
-- Check current connections vs max
-- PostgreSQL
SELECT count(*) current_connections, 
       (SELECT setting FROM pg_settings WHERE name='max_connections')::int AS max_connections
FROM pg_stat_activity;

-- SQL Server
SELECT COUNT(*) current_connections FROM sys.dm_exec_sessions;
SELECT @@MAX_CONNECTIONS;

-- MySQL
SHOW PROCESSLIST;
SHOW VARIABLES LIKE 'max_connections';

-- Who holds the connections?
-- PostgreSQL: long-running idle sessions?
SELECT pid, usename, state, now() - query_start AS idle_duration, query
FROM pg_stat_activity
WHERE state = 'idle'
ORDER BY query_start;
```

**Decision**:

- If many idle connections: app not closing connections (bug) → app team
- If pool limit is LOW: increase max_connections if platform allows → change_management.md
- If connections legitimately maxed by queries: → Performance troubleshooting

**Runbook**: incident_response.md (Phase 2: apply connection throttling)

### Branch C: Lock or Blocking Issues

**Symptom**: "Lock timeout", app errors mentioning deadlock, queries "hang", p50 latency normal but p95/p99 very high

**Step 1: Is this blocking (one session waiting for another) or deadlock (circular wait)?**

```sql
-- PostgreSQL: check for deadlocks in logs
SELECT * FROM pg_log WHERE message LIKE '%deadlock%' ORDER BY logged DESC LIMIT 1;

-- SQL Server: check system health session
SELECT * FROM sys.dm_os_ring_buffers 
WHERE ring_buffer_type = 'RING_BUFFER_EXCEPTION'
ORDER BY timestamp DESC;

-- MySQL: deadlock info
SHOW ENGINE INNODB STATUS;
```

**Decision**:

- If deadlock in logs: → lock-deadlock-triage.md (Phase 4: Deadlock section)
- If blocking visible: → lock-deadlock-triage.md (Phase 2-3: Blocker Analysis + Intervention)

**Runbook**: lock-deadlock-triage-and-resolution.md

### Branch D: High CPU But No Obvious Query

**Symptom**: CPU 80%+, but top 10 queries don't explain it

**Root cause investigation**:

```sql
-- Is autovacuum/maintenance running?
-- PostgreSQL
SELECT pid, query, state, now() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE 'autovacuum%' OR query LIKE 'analyze%';

-- SQL Server
SELECT * FROM sys.dm_exec_requests WHERE command LIKE '%CHECKPOINT%' OR command LIKE '%SHRINK%';

-- Is index maintenance/rebuild running?
-- SQL Server
SELECT * FROM sys.dm_exec_requests WHERE command LIKE '%INDEX%';

-- Are there waiting tasks (CPU spin)?
-- SQL Server
SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE runnable_tasks_count > 0;
```

**Decision**:

- If autovacuum: wait for completion; consider tuning autovacuum parameters
- If index rebuild: wait or cancel if safe
- If neither: investigate background processes (backups, replication, monitoring agents)

**Runbook**: Performance Troubleshooting Guide (see database_admin/performance/)

### Branch E: Replication Lag Growing

**Symptom**: replication_lag_seconds increasing over time; replica not catching up

**Step 1: Is it a network issue or replica-side issue?**

```sql
-- PostgreSQL: check replica LSN
-- On primary:
SELECT pg_current_wal_lsn();

-- On replica:
SELECT pg_last_xlog_receive_location(), pg_last_xlog_replay_location();

-- SQL Server: check LSN
-- On primary:
SELECT name, synchronization_state FROM sys.dm_hadr_database_replica_states;

-- Is replica applying logs?
-- PostgreSQL: check replay progress
SELECT now() - pg_last_xact_replay_timestamp() AS replay_delay;

-- SQL Server: check redo queue
SELECT redo_queue_size FROM sys.dm_hadr_database_replica_states;
```

**Decision**:

- If replica replay lag growing: replica CPU/IO saturated → throttle replica query load
- If network latency: increase network bandwidth or move replica closer
- If primary write volume spike: scale primary or defer writes

**Runbook**: HA/DR runbooks; consider failover if lag exceeds policy

### Branch F: Backup Failures or Missing

**Symptom**: "Backup failed", no backup in 24 hours, backup size significantly smaller than normal

**Step 1: Is it a file system issue or backup process issue?**

```bash
# Check backup directory exists and is writable
ls -lah /backup/

# Is disk space available?
df -h /backup/

# Do backup files exist and are recent?
ls -lh /backup/*.bak /backup/*.backup* 2>/dev/null | head -5

# Check backup process logs
tail -50 /var/log/backup_script.log
# Or Windows:
Get-EventLog -LogName Application -Source "Backup" | Select-Object -First 10
```

**Decision**:

- If disk full: expand storage or delete old backups → capacity planning
- If permission denied: fix directory permissions
- If backup process error: check logs; retry or escalate

**Runbook**: backup-verification-and-restore-drill.md (Phase 1)

### Branch G: Application Getting Wrong Data / Consistency Issue

**Symptom**: user reports data missing/corrupted; row counts don't match; constraint violations

**Step 1: Is this on primary or replica? Is replication in sync?**

```sql
-- Check replication status
-- PostgreSQL
SELECT application_name, state, sync_state FROM pg_stat_replication;

-- SQL Server
SELECT replica_server_name, synchronization_state FROM sys.dm_hadr_database_replica_states;

-- Is the data actually missing or is it a query filter issue?
-- PostgreSQL: count all rows (no filter)
SELECT COUNT(*) FROM table_name;

-- Compare to application's filtered view
SELECT COUNT(*) FROM table_name WHERE filter_column = 'value';
```

**Decision**:

- If replication out of sync: resync replica or failover to replica
- If data missing from both primary and replica: corruption or accidental delete → escalate to SRE (Sev-1)
- If missing only on replica: wait for replication to catch up

**Runbook**: Disaster Recovery (Phase 1: Scope and Prioritize)

## Quick Diagnostic Queries

### PostgreSQL - Health Check (2 minutes)

```sql
-- Active sessions and waits
SELECT pid, usename, state, wait_event_type, wait_event, query_start, now() - query_start AS duration
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start
LIMIT 20;

-- Cache hit ratio (should be >99%)
SELECT 
  sum(blks_read) AS total_reads,
  sum(blks_hit) AS total_hits,
  round(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) AS cache_hit_ratio
FROM pg_statio_user_tables;

-- Replication status
SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag
FROM pg_stat_replication;
```

### SQL Server - Health Check (2 minutes)

```sql
-- Active requests
SELECT session_id, command, status, wait_type, wait_time_ms, 
  SUBSTRING(st.text, (r.statement_start_offset / 2) + 1, 50) AS query_snippet
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE session_id > 50
ORDER BY wait_time_ms DESC;

-- CPU and memory pressure
SELECT *, 100.0 - available_physical_memory_percent AS memory_used_pct
FROM sys.dm_os_sys_memory;

-- Replication status (if AG)
SELECT replica_server_name, synchronization_state, last_received_lsn, last_hardened_lsn
FROM sys.dm_hadr_database_replica_states;
```

### MySQL - Health Check (2 minutes)

```sql
-- Process list
SHOW PROCESSLIST;

-- InnoDB status
SHOW ENGINE INNODB STATUS\G

-- Replica status
SHOW SLAVE STATUS\G

-- Active locks
SELECT * FROM performance_schema.data_locks;
```

## When to Escalate

If after 10 minutes of diagnosis you haven't found root cause:

1. **Sev-1 escalation**: → incident commander + senior DBA
2. **Provide evidence collected**:
   - Queries run
   - Output from diagnostic commands
   - Timeline of when issue started
   - Any recent changes/deployments
3. **Join war room**: real-time pair troubleshooting with domain experts

## Troubleshooting Log Template

For each incident, record:

| Item | Value |
|---|---|
| **Symptom observed** | (e.g., "Slow queries") |
| **Impact** | (e.g., "P95 latency > SLO") |
| **Time detected** | (UTC) |
| **Diagnosis branch used** | (e.g., "A1: Query Regression") |
| **Root cause found** | (e.g., "Missing index") |
| **Time to diagnosis** | (minutes) |
| **Runbook executed** | (file name) |
| **Time to resolution** | (minutes) |
| **Escalation needed?** | Yes/No |

# Lock Contention Troubleshooting

**This is a reference stub. For complete lock diagnosis and resolution procedures, see**:

[Lock/Deadlock Triage & Resolution Runbook](../sre/runbooks/lock-deadlock-triage-and-resolution.md)

That runbook includes:

- Rapid assessment queries (PostgreSQL, SQL Server, MySQL, Oracle)
- Blocker analysis and root cause determination
- Session termination safety procedures
- Deadlock detection and handling by engine
- Post-incident automation opportunities

## Quick Reference: PostgreSQL Blocking Check

```sql
-- Find blocking relationships
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
WHERE NOT blocked_locks.granted
LIMIT 10;
```

See full runbook for engine-specific variants and escalation procedures.

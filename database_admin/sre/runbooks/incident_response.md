# Incident Response Runbook (PostgreSQL)

## Triage
- Check cluster health, replication lag, connection saturation
- Identify top queries via pg_stat_statements

## Immediate Actions
- Throttle or terminate offending queries
- Enable statement_timeout if required

## Deep Dive
- Analyze locks, deadlocks, IO wait, buffer cache
- Review recent schema/index changes

## Recovery
- Failover if needed
- Restore from backup if corruption detected

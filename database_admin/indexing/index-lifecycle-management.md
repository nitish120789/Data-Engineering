# Index Lifecycle Management Guide

## Overview

Indexes are double-edged tools: they dramatically speed up reads but slow down writes and consume storage. This guide provides a structured approach to index creation, monitoring, maintenance, and retirement.

## Index Lifecycle Stages

```
Proposal → Validation → Creation → Ongoing Monitoring → Obsolescence Detection → Removal
```

Diagram description: Index lifecycle flows from initial proposal through validation, creation, continuous monitoring, detection of obsolescence, and eventual removal.

## Stage 1: Index Proposal and Validation

### When to Propose an Index

An index is a good candidate if:

1. **High-read query affected by full table scan**:
   - Query runs frequently (>100x per day)
   - Query is slow (>100ms) due to scan
   - Query is on a table with >1M rows
   - Index would filter to <5% of rows

2. **Join predicate inefficiency**:
   - Join on unindexed column
   - Join affects Tier-0/Tier-1 critical path

3. **Sorting bottleneck**:
   - ORDER BY on unindexed column with large result set
   - External sort spilling to disk

### Before Proposing: Cost-Benefit Analysis

Create a brief analysis:

| Factor | Benefit | Cost |
|---|---|---|
| Read improvement | Estimated speedup (e.g., 5s → 100ms) | - |
| Write penalty | - | 1-5% additional write latency per indexed column |
| Storage cost | - | 5-15% additional table storage |
| Maintenance | Automatic (vacuum/reorg) | Included in nightly maintenance window |
| Uniqueness | Can enforce uniqueness if partial index | N/A |

Example analysis:

> Index on `user_events.user_id` where scan takes 8 seconds on 500M row table.
> Expected benefit: 8s → 50ms for user profile load (critical path).
> Cost: 50ms additional per INSERT on user_events table (0.05% write penalty).
> Storage: +10GB (acceptable; table is 100GB).
> ROI: High; reduce profile load SLO by 95%; insert cost negligible on 50k/sec insert rate.
> **Decision: Create**

### Test Before Production

Lab testing (staging environment matching production topology):

```sql
-- PostgreSQL: create index and measure impact
EXPLAIN ANALYZE SELECT * FROM user_events WHERE user_id = 123 AND created_at > now() - interval '7 days';
-- Before index: Seq Scan: 2000ms
-- After index: Index Scan: 50ms

-- Capture baseline throughput and write latency
-- Run 60-second insert load test before and after index creation
-- Expected write latency increase: <5%
```

### Approval Gate

Tier-1/Tier-2 indexes require:

- [ ] Cost-benefit analysis attached to change ticket
- [ ] Test results showing read improvement
- [ ] Test results confirming write penalty < policy threshold (default 5%)
- [ ] DBRE approval
- [ ] Service owner sign-off

## Stage 2: Index Creation

### Timing and Approach

**Tier-1 Tables (>100M rows, high write rate)**:

Use non-blocking (concurrent) creation during business hours:

- PostgreSQL: `CREATE INDEX CONCURRENTLY`
- SQL Server: `CREATE INDEX ... WITH (ONLINE = ON)`
- MySQL: Percona Toolkit `pt-online-schema-change` or native online DDL (8.0+)
- Oracle: online index creation (default)

**Tier-2 Tables (10M-100M rows)**:

Can create during low-traffic window:

- PostgreSQL: `CREATE INDEX` during maintenance window (holds brief lock only for small tables)
- SQL Server: can use online mode; brief lock acceptable
- MySQL: native online DDL or toolkit

**Tier-3 Tables (<10M rows)**:

Blocking create acceptable; do in scheduled window:

```sql
-- PostgreSQL
CREATE INDEX idx_table_column ON table(column);

-- SQL Server
CREATE INDEX idx_table_column ON table(column);

-- MySQL
CREATE INDEX idx_table_column ON table(column);
```

### Creation Commands by Engine

**PostgreSQL** (concurrent for Tier-1):

```sql
-- Non-blocking index creation (holds AccessExclusiveLock briefly, then shared lock)
CREATE INDEX CONCURRENTLY idx_events_user_id ON events(user_id);

-- Monitor progress in parallel terminal
SELECT schemaname, tablename, indexname, phase, blocks_total, blocks_done,
       ROUND(100.0 * blocks_done / NULLIF(blocks_total, 0), 1) AS pct_complete
FROM pg_stat_progress_create_index;
```

**SQL Server** (online mode preferred for Tier-1):

```sql
-- Online index creation (minimizes lock window)
CREATE INDEX idx_events_user_id ON events(user_id)
WITH (ONLINE = ON, FILLFACTOR = 90);

-- Monitor progress
SELECT name, type_desc, create_date FROM sys.indexes WHERE name = 'idx_events_user_id';
```

**MySQL** (native online DDL for 8.0+):

```sql
-- Online DDL (ALGORITHM=INPLACE for non-blocking)
ALTER TABLE events ADD INDEX idx_events_user_id (user_id), ALGORITHM=INPLACE, LOCK=NONE;

-- Or Percona Toolkit for older versions or complex scenarios
pt-online-schema-change --alter "ADD INDEX idx_events_user_id (user_id)" \
  D=database,t=events \
  --execute
```

**Oracle** (default is online; can be made parallel):

```sql
-- Online index creation (default; can parallelize)
CREATE INDEX idx_events_user_id ON events(user_id)
  PARALLEL (DEGREE 4);

-- Monitor progress
SELECT * FROM v$session_longops WHERE opname LIKE '%Index%';
```

### Post-Creation Validation

1. [ ] Index exists and is visible in system catalog
2. [ ] Index is being used (not dead code)
3. [ ] Write latency penalty acceptable
4. [ ] Replication lag within policy

```sql
-- PostgreSQL: verify index is used
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE indexname = 'idx_events_user_id';

-- SQL Server
SELECT name, type_desc, user_seeks, user_scans, user_lookups
FROM sys.indexes i
JOIN sys.dm_db_index_usage_stats s ON i.index_id = s.index_id
WHERE i.name = 'idx_events_user_id';

-- MySQL
SELECT OBJECT_SCHEMA, OBJECT_NAME, COUNT_STAR, COUNT_READ, COUNT_WRITE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_NAME = 'idx_events_user_id';
```

## Stage 3: Ongoing Monitoring

### Monthly Index Health Review

Every month, run this assessment per critical table:

```sql
-- PostgreSQL: index usage and bloat
SELECT schemaname, tablename, indexname,
       idx_scan AS scans,
       idx_tup_read AS tuples_read,
       idx_tup_fetch AS tuples_fetched,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
       ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 1) AS cache_hit_pct
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- SQL Server
SELECT i.name, i.type_desc, s.user_seeks, s.user_scans, s.user_lookups, s.user_updates,
       ROUND(s.user_seeks / NULLIF(s.user_seeks + s.user_scans + s.user_lookups + s.user_updates, 0) * 100, 1) AS seek_pct
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE database_id = DB_ID()
ORDER BY s.user_seeks DESC;

-- MySQL
SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME,
       COUNT_STAR, COUNT_READ, COUNT_WRITE,
       ROUND(100.0 * COUNT_READ / NULLIF(COUNT_STAR, 0), 1) AS read_pct
FROM performance_schema.table_io_waits_summary_by_index_usage
ORDER BY COUNT_STAR DESC;
```

### Metrics to Track

| Metric | Healthy Range | Action if Outside |
|---|---|---|
| Scan frequency | >100/month for Tier-1 | Consider removing if <50/month |
| Write penalty | <5% per indexed column | Consider partial index or different design |
| Cache hit ratio | >95% | Index may be too large; review selectivity |
| Bloat (dead tuples) | <10% | Schedule REINDEX or maintenance |

## Stage 4: Obsolescence Detection

Indexes become candidates for removal when:

### 1. Unused Index (No Scans in 90 days)

```sql
-- PostgreSQL: find unused indexes (no scans in 90 days)
SELECT schemaname, tablename, indexname, idx_scan, 
       ROUND(pg_relation_size(indexrelid) / 1024 / 1024, 2) AS size_mb,
       idx_blks_read, idx_blks_hit
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  OR idx_scan < 10 -- very low usage
ORDER BY pg_relation_size(indexrelid) DESC;

-- SQL Server
SELECT i.name, s.user_seeks, s.user_scans, s.user_lookups,
       DATEDIFF(DAY, s.last_user_seek, GETDATE()) AS days_since_last_seek,
       ps.reserved_page_count * 8 / 1024 AS size_mb
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id
LEFT JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE database_id = DB_ID()
  AND i.type_desc = 'NONCLUSTERED'
  AND (s.user_seeks + s.user_scans + s.user_lookups) = 0
ORDER BY ps.reserved_page_count DESC;
```

### 2. Redundant Index

Two or more indexes with identical/overlapping leading columns:

```sql
-- PostgreSQL: find redundant indexes
SELECT indname, indkey, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename = 'table_name'
ORDER BY pg_relation_size(indexrelid) DESC;

-- If multiple indexes have same leading column, keep most selective one
```

### 3. Poor Selectivity Index

Index not filtering significantly (>50% of table still scanned):

```sql
-- PostgreSQL: analyze index selectivity
ANALYZE table_name;

-- Run query and check EXPLAIN plan
EXPLAIN SELECT * FROM table_name WHERE indexed_column = 'value';
-- If still sees >50% of table, index selectivity is poor

-- Candidate for removal or redesign
```

### 4. Index on Low-Cardinality Column

Indexing a column with very few unique values (e.g., status with 3 values) provides little benefit:

```sql
-- PostgreSQL: check distinct values
SELECT COUNT(DISTINCT indexed_column) AS unique_count,
       COUNT(*) AS total_rows,
       ROUND(100.0 * COUNT(DISTINCT indexed_column) / COUNT(*), 2) AS cardinality_pct
FROM table_name;

-- If cardinality < 5%, likely not useful (except for partial indexes)
```

### Approval Gate for Removal

- [ ] No usage in past 90 days (or extremely low)
- [ ] No dependent objects (views, applications)
- [ ] Test: run workload 24 hours without index to confirm no performance regression
- [ ] DBRE approval

## Stage 5: Index Removal

### Safe Removal Procedure

**For Tier-1/Critical Tables:**

1. Disable index first (if engine supports); run for 1-7 days; confirm no errors
2. If safe, drop index during maintenance window
3. Have rollback script ready: capture index definition before drop

**Commands by Engine**:

```sql
-- PostgreSQL
DROP INDEX IF EXISTS idx_name;

-- SQL Server (disable first, optional)
DISABLE INDEX idx_name ON table_name;
-- ... monitor for 24-48 hours ...
DROP INDEX idx_name ON table_name;

-- MySQL
DROP INDEX idx_name ON table_name;

-- Oracle
DROP INDEX idx_name;
```

### Capture Index Definition Before Removal

```sql
-- PostgreSQL
SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_name';

-- SQL Server
SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('idx_name');

-- MySQL
SHOW CREATE TABLE table_name\G

-- Oracle
SELECT dbms_metadata.get_ddl('INDEX', 'IDX_NAME') FROM dual;
```

## Best Practices

### Index Design Principles

1. **Narrow indexes preferred**: include only columns necessary for query
2. **Composite indexes**: order columns by selectivity (most selective first, except for range predicates)
3. **Partial indexes**: filter to frequently-accessed subset to reduce size

```sql
-- PostgreSQL: partial index (low cardinality improvement)
CREATE INDEX idx_orders_active_user ON orders(user_id) 
WHERE status = 'active';

-- PostgreSQL: covering index (includes columns for index-only scans)
CREATE INDEX idx_events_user_created ON events(user_id, created_at) 
INCLUDE (event_type);
```

4. **Avoid indexing joins on foreign keys if referential integrity enforced by engine** (can still help if frequent joins)

### Common Pitfalls

- **Duplicate indexes**: multiple indexes with same leading column
- **Over-indexing**: more than 3-4 indexes per Tier-1 table rarely beneficial
- **Indexes on low-cardinality columns**: status, flag fields (unless very large table)
- **Ignoring write penalty**: index speeds up one query but slows inserts/updates across the board

## Automation Opportunities

- **Monthly index health report**: automated scan for unused indexes, bloat, redundancy
- **Dead index alerts**: if index unused for 60 days, create ticket for review
- **Index recommendation**: query rewrite suggestions when full table scans detected on large tables
- **Index bloat monitoring**: schedule REINDEX automatically when bloat exceeds threshold

## Index Review Checklist (Quarterly)

1. [ ] Identify indexes with zero usage in past quarter
2. [ ] Identify redundant indexes (same leading column)
3. [ ] Assess index bloat; schedule maintenance if >15%
4. [ ] Review indexes on low-cardinality columns
5. [ ] Evaluate partial/covering indexes for Tier-1 workloads
6. [ ] Update cost-benefit analysis for top 5 slowest queries
7. [ ] Document new index proposals and test results

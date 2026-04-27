# Change Management and Release Runbook

## Summary

- Purpose: systematically implement schema, configuration, code, or infrastructure changes to production databases while maintaining SLO compliance
- Scope: Tier-1, Tier-2, and Tier-3 production environments
- Owner: DBRE/DBA + application owner + platform engineer
- Policy enforcement: mandatory for all Tier-1 changes; waivable for low-risk Tier-3 ops with documented risk acceptance

## Impact and Reliability Context

- Database changes are the leading cause of unplanned outages in most estates
- High-risk changes (DDL on large tables, index creation, parameter tuning) require pre-change analysis and post-change validation
- Change windows and maintenance schedules protect SLO compliance and reduce blast radius

## Change Classification and Risk Assessment

### Tier-1 High-Risk Changes

Examples: schema modifications on active tables, security policy enforcement, capacity/resource changes

- Blast radius: production impact likely
- Rollback complexity: high
- Testing requirement: mandatory
- Window requirement: scheduled maintenance window
- Approval: DBRE + Service owner + Platform lead

### Tier-2 Medium-Risk Changes

Examples: index additions, non-blocking DDL, configuration tuning, non-critical security updates

- Blast radius: limited scope
- Rollback complexity: medium
- Testing requirement: pre-validation required; progressive rollout acceptable
- Window requirement: scheduled or flexible with monitoring
- Approval: DBRE + Service owner

### Tier-3 Low-Risk Changes

Examples: monitoring policy updates, metadata changes, non-operational parameter tuning

- Blast radius: isolated
- Rollback complexity: low
- Testing requirement: documented but may be laboratory-only
- Window requirement: flexible
- Approval: DBRE alone (with ticket trail)

## Preconditions and Risk Gates

- [ ] Change ticket created with business justification
- [ ] Risk classification assigned (Tier 1/2/3)
- [ ] Required stakeholders identified and notified
- [ ] Change window scheduled (for high-risk changes)
- [ ] Backup verified and restore tested within last 7 days
- [ ] Monitoring and alerting confirmed ready
- [ ] Rollback procedure documented and tested
- [ ] Application owner aware of expected impact window
- [ ] Break-glass access validated if required

## Preparation Checklist

### Pre-Change (1-5 days before)

1. [ ] Schedule change window and send calendar invites
2. [ ] Create detailed change plan using template: [database_admin/templates/change_plan_template.md](../templates/change_plan_template.md)
3. [ ] Perform testing in staging environment matching production topology
4. [ ] Document all test results and any required adjustments
5. [ ] Identify and pre-stage rollback scripts
6. [ ] Notify application teams of planned window and expected behavior
7. [ ] Review recent changes and incidents in same area to identify interaction risks
8. [ ] If Tier-1, conduct change review meeting with all required approvers

### Day-Of (1 hour before window)

1. [ ] Establish incident bridge and assign communication lead
2. [ ] Verify database replication lag is minimal
3. [ ] Confirm all required personnel are available
4. [ ] Take baseline snapshots: query latency, throughput, CPU, IOPS
5. [ ] Verify connectivity and permissions to target systems
6. [ ] Announce change start to stakeholders
7. [ ] Enable enhanced monitoring and alerting

## Procedure

### Phase 1: Pre-Change Validation (5-15 minutes)

Goal: Confirm system state is suitable for change execution.

Steps:

1. Verify replication lag (if applicable) is within policy and stable.
2. Check active session count and connection utilization.
3. Run health check query specific to change type (see engine-specific sections below).
4. Compare baseline metrics snapshot to current state.
5. Decision point: if anomalies detected, discuss with incident commander whether to proceed or defer.

### Phase 2: Change Implementation (variable duration)

Goal: Execute the change with minimal service impact.

Approach depends on change type:

#### DDL on Tier-1 Tables (Large/Heavily Accessed)

Use online/non-blocking approach where available:

- PostgreSQL: Use `CONCURRENTLY` for index creation; use `pg_repack` or `pg_stat_monitor` for blocking DDL on huge tables
- SQL Server: Use online index operations; use staging tables for large transformations
- MySQL: Use Percona Toolkit (`pt-online-schema-change`) or native online DDL
- Oracle: Use online redefinition via `DBMS_REDEFINITION` or Transportable Tablespaces for large objects

Example PostgreSQL concurrent index creation:

```sql
-- Tier-1 table (concurrent mode preferred to avoid blocking)
CREATE INDEX CONCURRENTLY idx_new_large_table ON large_table (column_name);

-- Monitor progress (can be run in parallel terminal)
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE indexname = 'idx_new_large_table';
```

#### Schema Changes with Potential Downtime

For changes that cannot be made non-blocking:

1. Execute during scheduled window
2. Minimize blocking time: pre-allocate resources, warm caches where possible
3. Monitor connection drains and query completion during execution
4. If blocking exceeds policy threshold (e.g., > 30 seconds), escalate to rollback decision

#### Parameter and Configuration Changes

1. Apply to non-primary replicas first if applicable
2. Validate behavior on replica for 5-10 minutes
3. Apply to primary
4. Monitor application response time and error rate for drift

### Phase 3: Post-Change Validation (10-30 minutes)

Goal: Confirm change has the intended effect and no unintended consequences.

Validation checklist (adapt per change type):

1. [ ] Verify schema/config change applied correctly:

```sql
-- PostgreSQL schema verification
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE indexname = 'idx_new_column';

-- SQL Server index verification
SELECT name, type_desc, create_date
FROM sys.indexes
WHERE name = 'idx_new_column';
```

2. [ ] Check query plan for affected workloads:

```sql
-- PostgreSQL: verify plan uses new index
EXPLAIN ANALYZE SELECT ... FROM table WHERE column_name = 'value';

-- SQL Server
SET STATISTICS IO ON;
SELECT ... FROM table WHERE column_name = 'value';
SET STATISTICS IO OFF;
```

3. [ ] Verify latency metrics:
   - p95 and p99 latency should remain within SLO band or improve
   - If degradation observed, investigate immediately
4. [ ] Monitor error rates for spike (connection timeouts, query failures)
5. [ ] Verify replication is catching up (lag < threshold)
6. [ ] Run application smoke tests against modified schema/config

### Phase 4: Stabilization and Post-Change Actions (30 minutes - 2 hours)

1. Monitor for 30-60 minutes to catch delayed or cascade issues
2. Collect final metrics snapshot for comparison against baseline
3. Document actual impact and timing vs. planned estimates
4. If all metrics nominal, release communication to stakeholders
5. Update change ticket with:
   - Completion time and actual window vs. planned
   - Any issues encountered and resolution
   - Verification results
   - Rollback not needed (or note if executed)

## Verification

### Technical Success Criteria

- [ ] Intended schema/config change is reflected in system
- [ ] Application transactions process without new errors
- [ ] Latency metrics within SLO band
- [ ] Replication lag recovering toward baseline
- [ ] No blocking chains or deadlock spikes introduced
- [ ] Query plans for affected queries still efficient (or improved)

### Data Integrity Spot-Checks

If change involves data transformation or constraint addition:

```sql
-- PostgreSQL example: verify constraint
SELECT constraint_name, constraint_type, table_name
FROM information_schema.table_constraints
WHERE constraint_name = 'new_constraint';

-- Count violations (should be zero if change included validation)
SELECT COUNT(*) AS violations
FROM table_name
WHERE NOT (new_column_constraint_expression);
```

### SLO Attestation

- Query latency p95/p99: ✓ Within band
- Error rate: ✓ No new error types observed
- Availability: ✓ No unplanned downtime

## Rollback

### Trigger Conditions for Rollback

- Latency degradation exceeds 50% above baseline
- Error rate spikes to > 0.1% of traffic
- Application reports functional failures (e.g., queries failing, constraints rejecting valid data)
- Query plans regress materially for critical paths
- Replication backlog exceeds recovery SLA

### Rollback Procedure

1. **Assess urgency**: if Sev-1 impact, escalate to incident commander immediately
2. **Prepare rollback**:
   - Confirm rollback steps are in change plan
   - Pre-stage undo scripts
3. **Execute rollback**:
   - Run undo script
   - Verify rollback completed successfully
4. **Validate recovery**:
   - Metrics return to baseline within 5-10 minutes
   - Queries execute without new errors
   - Replication converges
5. **Communicate**: inform stakeholders of rollback and root cause findings

### Post-Rollback Analysis

- Why did the change cause the issue?
- What additional testing would have caught it?
- Schedule follow-up change with additional validation

## Communication

### Pre-Window Notification (1-3 days before)

- Recipient: application teams, service owners, support, on-call
- Message: change summary, estimated window, expected behavior (brief pauses, possible timeout increase)

### During-Window Updates (every 15-30 minutes if Tier-1)

- Recipient: incident bridge participants
- Message: phase (pre-validation, implementation, post-validation), current status, any issues

### Post-Change Summary (within 24 hours)

- Change completed successfully vs. rolled back
- Actual duration vs. planned
- Any anomalies observed and resolution
- Ticket link for full details

## Evidence and Audit Trail

Collect and store:

1. **Pre-change baseline**:
   - Query latency histogram (p50/p95/p99)
   - Throughput (TPS/QPS)
   - CPU, IOPS, storage utilization
   - Replication lag (if HA)
2. **During-change logs**:
   - DDL or configuration change command with timestamp
   - Error messages or warnings (if any)
   - Connection/session counts during execution
3. **Post-change baseline**:
   - Same metrics as pre-change
   - Query plan comparison for affected queries
4. **Verification outputs**:
   - Schema/config verification query results
   - Smoke test results
5. **Communication record**:
   - Email threads
   - Incident bridge transcript
6. **Change ticket**: final status, approval record, lessons learned link

## Automation Opportunities

- **Pre-change health checks**: automated query to run 10 minutes before window start; report anomalies to on-call
- **Post-change metric diff**: automated comparison of latency/error rate baseline vs. post-change; auto-rollback if threshold exceeded
- **Change approval workflow**: GitOps-style change validation in CI (syntax check, compatibility check vs. schema version)
- **Staged rollout automation**: progressive deployment of configuration changes across replica → primary

## Engine-Specific Guidance

### PostgreSQL

**High-Risk DDL (e.g., ADD COLUMN on large table)**

Use `CONCURRENTLY` where possible or leverage newer PostgreSQL versions with optimized ALTER TABLE:

```sql
-- PostgreSQL 11+: fast ADD COLUMN with constant default
ALTER TABLE large_table ADD COLUMN new_col INT DEFAULT 0;

-- Pre-check for blocking activity
SELECT pid, query, query_start, wait_event_type
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;
```

**Pre-change health check**:

```sql
-- Check for long-running transactions that could block DDL
SELECT pid, usename, xact_start, now() - xact_start AS duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY duration DESC;
```

### SQL Server

**High-Risk DDL (e.g., ADD COLUMN on indexed table)**

Use online index operations where available:

```sql
-- Enable online index operation (SQL Server 2014+)
ALTER TABLE large_table
ADD new_column INT DEFAULT 0
WITH (ONLINE = ON);

-- Pre-check for blocking
SELECT r.session_id, r.command, r.status, CAST(r.start_time AS VARCHAR(30)) AS start_time, r.est_completion_time
FROM sys.dm_exec_requests r
WHERE r.session_id > 50;
```

### MySQL

**High-Risk DDL (large table schema changes)**

Use Percona Toolkit or native online DDL:

```bash
# Using pt-online-schema-change (non-blocking)
pt-online-schema-change --alter "ADD COLUMN new_col INT DEFAULT 0" \
  D=database,t=large_table \
  --execute
```

### Oracle

**High-Risk DDL (table redefinition)**

Use online redefinition:

```sql
BEGIN
  DBMS_REDEFINITION.start_redef_table(
    uname => 'SCHEMA_OWNER',
    orig_table => 'LARGE_TABLE',
    int_table => 'LARGE_TABLE_INT'
  );
  
  -- DDL changes to intermediate table here
  
  DBMS_REDEFINITION.finish_redef_table(
    uname => 'SCHEMA_OWNER',
    orig_table => 'LARGE_TABLE',
    int_table => 'LARGE_TABLE_INT'
  );
END;
/
```

## Lessons Learned

After each Tier-1 change:

1. [ ] What went well?
2. [ ] What could be improved (testing, validation, communication)?
3. [ ] Were there any unexpected interactions or timing issues?
4. [ ] Should this procedure be updated?

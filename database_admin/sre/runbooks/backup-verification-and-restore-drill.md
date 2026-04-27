# Backup Verification and Restore Drill Runbook

## Summary

- Purpose: verify backup infrastructure is functional and validate actual recovery time/data loss
- Scope: Tier-1, Tier-2 production database services
- Owner: DBRE / DBA + storage/infrastructure team
- Frequency: monthly restore drill for Tier-1; quarterly for Tier-2
- SLO context: RTO and RPO policy is validated only through successful drills

## Impact and Reliability Context

- Backups exist but may be corrupted or incomplete (undetected for weeks)
- Recovery procedures may be broken or require undocumented manual steps
- Only through actual drill can you be confident in RTO/RPO claims
- Restore drill is the highest-value DBRE activity for reliability

## Types of Drills

### 1. Full Restore Drill (Most Valuable)

- Restore entire database to alternate infrastructure
- Validate all data present and consistent
- Measure actual RTO and RPO
- Frequency: quarterly for Tier-1
- Effort: 2-4 hours

### 2. Rapid Restore to Point-in-Time (High Value)

- Restore to specific timestamp and validate row counts of critical tables
- Validate log/archive completeness
- Measure RTO for point-in-time recovery
- Frequency: monthly for Tier-1
- Effort: 1-2 hours

### 3. Backup Integrity Check (Baseline)

- Verify backup file integrity (checksums)
- Verify backup metadata (header, timestamps)
- Verify archive log completeness (no gaps)
- Frequency: weekly for Tier-1
- Effort: 30 minutes

## Preparation Checklist

### Pre-Drill (1 week before)

1. [ ] Schedule drill window; book infrastructure
2. [ ] Identify target restore environment (must be separate from production)
3. [ ] Obtain latest backup set and archive logs
4. [ ] Document baseline: production row counts, critical table max ID, etc.
5. [ ] Notify stakeholders: this is a planned drill; expect resource usage spike
6. [ ] Create restore checklist for team (see Procedure section)
7. [ ] Verify rollback plan (restore target cleanup)

### Day-Of (1 hour before drill)

1. [ ] Confirm restore infrastructure is available and networked
2. [ ] Verify backup files and archive logs accessible
3. [ ] Ensure team members available and on communication bridge
4. [ ] Start timer; record start time (UTC)

## Procedure

### Phase 1: Pre-Restore Validation (15-30 minutes)

Goal: confirm backup integrity before attempting restore.

#### Step 1: Backup File Integrity Check

**PostgreSQL**:

```bash
# Verify physical backup (pg_basebackup format)
pg_verifybackup -p /backup/latest_backup

# Or for logical backup (pg_dump format)
pg_dump -f /tmp/verify_dump.sql --schema-only database_name
# Should not error

# Check backup timestamps
ls -lah /backup/latest_backup/
# Verify recent (within backup window)
```

**SQL Server**:

```sql
-- Verify backup integrity
RESTORE VERIFYONLY FROM DISK = '/backup/full_backup.bak';

-- Check backup headers
RESTORE HEADERONLY FROM DISK = '/backup/full_backup.bak';
-- Verify BackupFinishDate is recent and ExpirationDate is in future
```

**MySQL**:

```bash
# Verify backup file integrity (Percona XtraBackup)
xtrabackup --prepare --target-dir=/backup/latest_backup

# Or for logical backup (mysqldump format)
mysql < /backup/mysqldump.sql --skip-column-statistics 2>&1 | head -20
# Should parse without syntax errors
```

**Oracle**:

```sql
-- Verify backup set
RMAN> VALIDATE BACKUPSET 1;
-- Should show "validate is complete"

-- List backup sets
RMAN> LIST BACKUP SUMMARY;
```

#### Step 2: Archive Log Completeness Check

Verify no gaps in redo logs/WAL between backup and point-in-time target.

**PostgreSQL**:

```bash
# Check WAL archive completeness
ls -1 /backup/archive_logs/ | sort
# Verify no gaps in sequence (000000010000000000000001, 000000010000000000000002, ...)
# If gaps, restore cannot go past the gap

# Or query:
SELECT * FROM pg_walfile_name_offset(pg_backup_info)
```

**SQL Server**:

```sql
-- Verify transaction log backup chain
RESTORE FILELISTONLY FROM DISK = '/backup/latest_log.trn';
-- All logs should have sequential sequence numbers
```

**MySQL**:

```bash
# Verify binary log completeness
ls -1 /backup/archive_logs/ | sort
# Verify sequence: mysql-bin.000001, mysql-bin.000002, ...
# If gaps, point-in-time restore limited
```

#### Step 3: Point-in-Time Target Definition

**Policy**: restore to what point? (latest available or specific time?)

- **Option A**: restore to latest available (highest RPO; proves backup chain complete)
- **Option B**: restore to 1 hour ago (typical production scenario; tests point-in-time capability)

Record target time: **UTC YYYY-MM-DD HH:MM:SS**

### Phase 2: Restore Execution (30-120 minutes, engine-dependent)

Goal: restore database to target environment.

#### PostgreSQL Restore

```bash
# Full restore from base backup + WAL replay
initdb -D /restore_target

# Restore base backup
pg_basebackup -h backup_server -D /restore_target -X fetch -P

# Or restore from pg_dump
psql -U postgres -d postgres -f /backup/mysqldump.sql

# If point-in-time, configure recovery target:
# In recovery.conf:
recovery_target_timeline = 'latest'
recovery_target_time = '2026-04-26 14:30:00 UTC'
# Start PostgreSQL; it will replay WAL to target time

# Verify restore completeness
SELECT COUNT(*) FROM critical_table;
# Should match production baseline
```

#### SQL Server Restore

```sql
-- Restore full database backup
RESTORE DATABASE database_name 
  FROM DISK = '/backup/full_backup.bak'
  WITH NORECOVERY;

-- Restore transaction logs sequentially (in order)
RESTORE LOG database_name 
  FROM DISK = '/backup/log_1.trn'
  WITH NORECOVERY;

RESTORE LOG database_name 
  FROM DISK = '/backup/log_2.trn'
  WITH RECOVERY;
  -- Last log must have WITH RECOVERY to bring DB online

-- Verify
SELECT COUNT(*) FROM critical_table;
```

#### MySQL Restore

```bash
# Restore from full backup
mysql < /backup/mysqldump.sql

# Or from Percona backup
xtrabackup --prepare --target-dir=/backup/latest_backup
# (copy files to MySQL data directory)
systemctl restart mysql

# Verify
mysql -e "SELECT COUNT(*) FROM database.critical_table;"
```

#### Oracle Restore

```sql
-- Restore from backup
RMAN> SET DBID nnnn;  -- if required
RMAN> RESTORE DATABASE;
RMAN> RECOVER DATABASE;

-- Or point-in-time
RMAN> SET UNTIL TIME 'APR 26 2026 14:30:00';
RMAN> RESTORE DATABASE;
RMAN> RECOVER DATABASE;

-- Verify
SELECT COUNT(*) FROM critical_table;
```

### Phase 3: Post-Restore Validation (30-60 minutes)

Goal: confirm restored data is complete and consistent.

#### Verification Checklist

1. [ ] Database comes online without errors
2. [ ] All critical tables accessible
3. [ ] Row count matches production baseline (within tolerance)

```sql
-- PostgreSQL/MySQL/Oracle
SELECT table_name, COUNT(*) FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'mysql', 'sys')
GROUP BY table_name
ORDER BY table_name;

-- Compare to production baseline
-- Accept <1% variance for point-in-time restores
```

4. [ ] No data corruption (referential integrity check)

```sql
-- Check foreign keys
SELECT COUNT(*) AS orphaned_records
FROM child_table c
WHERE NOT EXISTS (
  SELECT 1 FROM parent_table p WHERE p.id = c.parent_id
);
-- Should be zero

-- Check checksums on high-value tables
SELECT table_name, MD5(GROUP_CONCAT(column_list ORDER BY column_list))
FROM critical_table
GROUP BY table_name;
-- Compare to production checksum baseline
```

5. [ ] Replication (if HA) initializes successfully

```sql
-- PostgreSQL (if streaming replication)
SELECT application_name, client_addr, state, sync_state, sync_priority
FROM pg_stat_replication;
-- Replica should show "streaming" state

-- MySQL (if multi-source replication)
SHOW SLAVE STATUS\G
-- Verify Slave_IO_Running and Slave_SQL_Running are both Yes
```

6. [ ] Performance baseline acceptable

```sql
-- Run sample query and verify latency
SELECT COUNT(*) FROM large_table WHERE indexed_column = 'value';
-- Should complete in <1 second (relative to table size)
```

#### Data Consistency Deep Dive

If Tier-1 workload, add additional validation:

```sql
-- Row count by date range (check data completeness)
SELECT DATE(created_at) AS date, COUNT(*) AS row_count
FROM transactions
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Verify max ID progression (no gaps in sequence)
SELECT MAX(id) FROM transactions;
-- Compare to production max ID

-- For financial systems: verify sum balances
SELECT account_id, SUM(amount) AS total_balance
FROM transactions
GROUP BY account_id
HAVING total_balance != 0;
-- Balance transactions should sum to zero
```

### Phase 4: Measurement and Documentation (10 minutes)

1. Record actual RTO:
   - Start time: (UTC from Phase 1)
   - End time (fully restored + validated): (UTC)
   - Actual RTO: ___ minutes
   - Planned RTO target: ___ minutes
   - Status: ✓ Met / ✗ Exceeded

2. Record actual RPO:
   - Restore target time: (UTC)
   - Latest data available in backup: (UTC)
   - Data loss window: ___ minutes
   - Planned RPO target: ___ minutes
   - Status: ✓ Met / ✗ Exceeded

3. Document any issues encountered:

   - Issue: ___
   - Resolution: ___
   - Root cause: ___
   - Preventive action: ___

### Phase 5: Cleanup

1. Stop restored database instance
2. Deallocate compute/storage resources
3. Clean up restore working directories

## Verification

### Technical Success Criteria

- [ ] Backup integrity check passed (no corruption)
- [ ] Archive log chain complete (no gaps)
- [ ] Restore completed without errors
- [ ] All critical tables present and accessible
- [ ] Row counts within 1% of production
- [ ] Referential integrity validation passed
- [ ] Replication initialized (if applicable)
- [ ] Sample query latency acceptable

### SLO Attestation

- Actual RTO ≤ Planned RTO target (or acceptable variance documented)
- Actual RPO ≤ Planned RPO target (or acceptable variance documented)
- No data loss scenarios identified during restore

## Rollback / Escalation

- If restore fails: escalate to infrastructure team; document failure mode
- If data corruption detected: escalate to SRE incident commander; treat as Sev-1

## Communication

- Pre-drill: notify stakeholders 1 week and 24 hours before
- During drill: brief status updates to bridge (start, checkpoint 50%, completion)
- Post-drill: email summary (RTO/RPO achieved, pass/fail, action items)

## Evidence and Audit Trail

Document:

1. Backup set used (file names, timestamps)
2. Archive logs applied (start → end)
3. Point-in-time target (if applicable)
4. Restore start and end time (UTC)
5. Validation results (row counts, integrity checks)
6. Performance baselines (query latency)
7. Any issues and resolutions
8. Sign-off (DBRE, infrastructure lead)

Example drill report:

> **Backup Restore Drill Report**
> Date: 2026-04-26
> Database: production_db (PostgreSQL 14)
> Restore target time: 2026-04-26 10:00:00 UTC (1 hour before current time)
> 
> **Results**:
> - Backup integrity: ✓ Valid
> - Archive logs: ✓ Complete (gap free)
> - Restore duration: 45 minutes (target: 60 min) ✓
> - RTO achieved: 45 min (target: 60 min) ✓
> - RPO achieved: 1 hour (target: 24 hours) ✓
> - Row count validation: ✓ 0.3% variance (acceptable)
> - Referential integrity: ✓ No orphaned records
> - Replication sync: ✓ Replica caught up in 5 minutes
> 
> **Issues**: None
> **Approval**: Signed by DBRE
> **Next Drill**: 2026-05-26

## Automation Opportunities

- **Weekly integrity check**: automated backup header validation; alert if corrupted
- **Monthly drill**: automated restore to temp environment; validate row counts; auto-cleanup
- **Metrics tracking**: graph RTO/RPO trends; alert if degrading
- **Backup diff**: automated comparison of restore data to production; alert on size/count anomalies

## Lessons Learned Template

After each drill:

1. What went well?
2. What failed or was unexpected?
3. Is restore procedure documented accurately?
4. Should team training be updated?
5. Any infrastructure or backup process changes needed?
6. Schedule action items for next quarter

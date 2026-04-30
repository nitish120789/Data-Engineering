# Migration Runbook: Oracle to PostgreSQL (120+ TB)

## Pre-Migration Checklist

### 1. Week 1: Planning & Preparation
- [ ] Audit Oracle schema (tables, indexes, sequences, procedures)
- [ ] Estimate data volume per table
- [ ] Identify Oracle-specific features (partitioning, LOBs, custom types)
- [ ] Create PostgreSQL target environment (sizing, network testing)
- [ ] Provision Azure resources (Data Box, ADLS, ADF, PostgreSQL)
- [ ] Train migration team (roles, responsibilities, escalation)
- [ ] Set up monitoring (CloudWatch, Azure Monitor, pgAdmin)
- [ ] Schedule change advisory board (CAB) approval

**Exit Criteria**: Migration plan approved, resources provisioned, team trained

---

## Phase 1: Initial Bulk Load (Weeks 1-4)

### 1.1 Schema Extraction & Conversion

**Day 1-2: Extract Oracle DDL**
```bash
# On Oracle extraction host
sqlplus / as sysdba @scripts/phase1_schema_extraction.sql
# Output: oracle_schema_ddl.sql
```

**Day 2-3: Convert to PostgreSQL**
```bash
# Convert DDL
python scripts/phase1_schema_conversion.py \
  --input oracle_schema_ddl.sql \
  --output postgresql_schema_ddl.sql \
  --target-version 15

# Review and test conversion
psql -U postgres -d postgres -f postgresql_schema_ddl.sql -e
```

**Exit Criteria**: PostgreSQL schema created, schema object count verified

### 1.2 Prepare Data Export

**Day 3-5: Export Oracle to CSV**
```bash
# Stage parallel exports (8 parallel workers)
# Use expdp or custom UNLOAD scripts
# Generate CSV files: ~150 MB each

# Verify exports
ls -lh /data/oracle_exports/csv/
wc -l /data/oracle_exports/csv/*.csv

# Calculate checksums
md5sum /data/oracle_exports/csv/*.csv > csv_checksums.txt
```

**Exit Criteria**: All CSV files staged, checksums validated

### 1.3 Stage to Azure Data Box

**Day 5-7: Prepare Data Box**
1. Receive Data Box device
2. Configure network access (NFS)
3. Mount on extraction host
4. Copy CSV files to Data Box

```bash
# Mount Data Box
mkdir -p /mnt/databox
mount -t nfs -o vers=4.1,rsize=65536,wsize=65536 \
  192.168.1.100:/csv /mnt/databox/csv

# Copy CSV files
rsync -av --progress /data/oracle_exports/csv/ /mnt/databox/csv/

# Verify transfer
ls -lh /mnt/databox/csv/ | tail -20
du -sh /mnt/databox/csv/
```

**Exit Criteria**: All CSVs on Data Box, checksums verified

### 1.4 Ship & Ingest to Azure

**Day 7-14: Shipment & Azure Ingestion**
1. Seal Data Box and initiate shipment (Azure Portal)
2. Monitor shipment tracking
3. Upon delivery, Azure automatically uploads to ADLS
4. Verify ingestion in ADLS

```bash
# Check ADLS ingestion progress (Azure Portal)
az storage fs file list \
  --account-name migrationadls01 \
  --file-system-name oracle-migration \
  --path raw/csv

# Calculate ingestion time and rate
# Expected: 800 GB in ~24-48 hours
```

**Exit Criteria**: All CSVs in ADLS, checksums match

### 1.5 CSV to Parquet Conversion

**Day 14-16: Bulk Convert to Parquet**
```bash
# Run converter
python scripts/csv_to_parquet_converter.py \
  --input-dir /mnt/adls/csv_exports \
  --output-dir /mnt/adls/parquet_staging \
  --compression snappy \
  --parallel 8

# Monitor progress
tail -f csv_to_parquet_conversion.log

# Verify output
az storage fs file list \
  --account-name migrationadls01 \
  --file-system-name oracle-migration \
  --path processed/parquet
```

**Exit Criteria**: All Parquet files in ADLS, row counts match CSV row counts

### 1.6 PostgreSQL Initial Load (ADF)

**Day 16-20: Run ADF Pipeline**
1. Create ADF pipeline (Copy activity from Parquet → PostgreSQL)
2. Configure parallel execution (50 concurrent writers per table)
3. Set checkpoint per table (resume on failure)
4. Monitor pipeline execution

```bash
# Trigger ADF pipeline run
az datafactory pipeline create-run \
  --factory-name mig-adf-01 \
  --name oracle_parquet_to_postgres \
  --resource-group rg-migration-prod

# Monitor progress
az datafactory pipeline-run query-by-factory \
  --factory-name mig-adf-01 \
  --resource-group rg-migration-prod

# Expected: 120 TB in ~4 days
```

**Exit Criteria**: All 1200 tables loaded, row counts match, no failed tables

### 1.7 Post-Load Validation

**Day 20-21: Row Count & Sample Checks**
```bash
# Row count reconciliation
psql -U postgres -d oracle_migration -f scripts/reconciliation_checks.sql > row_count_report.txt

# Compare with Oracle row counts
diff <(oracle_counts.sql) <(psql -c "SELECT table_name, COUNT(*) FROM ...") 

# Checksum validation (sample 10% of rows per table)
psql -U postgres -d oracle_migration -c "
  SELECT table_name, 
         COUNT(*) as checked,
         SUM(CASE WHEN checksum_match THEN 1 ELSE 0 END) as matched
  FROM checksum_validation
  GROUP BY table_name
  ORDER BY table_name;
"

# Business query spot checks
psql -U postgres -d oracle_migration -f scripts/business_validation.sql > business_report.txt
```

**Exit Criteria**: ≥99.9% row match, no checksum failures, business queries pass

### 1.8 Build Indexes & Constraints

**Day 21-22: Index & FK Creation**
```sql
-- PostgreSQL: Create indexes (deferred from initial load)
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
-- ... (all remaining indexes)

-- Enable foreign keys
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer_id
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
-- ... (all remaining FKs)
```

**Exit Criteria**: All indexes created, all FKs enabled, no constraint violations

---

## Phase 2: CDC & Delta Sync (Weeks 2-11, overlapping)

### 2.1 LogMiner Setup (Start Week 2, Day 1)

**Day 1: Record Snapshot SCN**
```sql
-- On Oracle, BEFORE initial load (or at start of Phase 1)
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER FROM DUAL;
-- Output: 123456789 (example SCN)
-- This is your ORACLE_START_SCN for CDC config
```

**Day 2-3: Enable Supplemental Logging**
```sql
-- On Oracle
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER TABLE customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- ... (all tables)

-- Verify
SELECT name FROM v$archived_log WHERE supplemental_log_dbid = 0;
```

**Day 3: Run LogMiner Setup Script**
```bash
sqlplus / as sysdba @scripts/phase2_logminer_setup.sql SNAPSHOT_SCN=123456789
```

**Exit Criteria**: Supplemental logging enabled, LogMiner ready

### 2.2 Start CDC Extractor (Week 2, Day 4)

**Day 4: Launch CDC Extractor**
```bash
# Start extractor (runs continuously)
python scripts/oracle_logminer_cdc.py \
  --oracle-dsn "oracle://cdc_user:pwd@10.0.0.50:1521/ORCL" \
  --start-scn 123456789 \
  --output-queue /var/lib/cdc/changes.jsonl \
  --batch-size 10000 \
  --interval 5 &

# Monitor progress
tail -f oracle_logminer_cdc.log

# Check queue growth
du -sh /var/lib/cdc/changes.jsonl
```

**Exit Criteria**: CDC extractor running, queue populating with changes

### 2.3 Start CDC Replay (Week 2, Day 5)

**Day 5: Launch CDC Replay**
```bash
# Start replay (continuous consumer)
python scripts/cdc_replay_postgresql.py \
  --pg-dsn "postgresql://postgres:pwd@pg-target.postgres.database.azure.com:5432/oracle_migration" \
  --input-queue /var/lib/cdc/changes.jsonl \
  --batch-size 1000 \
  --checkpoint-table public.cdc_checkpoint &

# Monitor replay progress
tail -f cdc_replay_postgresql.log

# Check CDC lag
psql -c "
  SELECT 
    MAX(last_scn) as current_scn,
    NOW() - MAX(last_timestamp) as lag
  FROM public.cdc_checkpoint;
"
```

**Exit Criteria**: CDC replay running, lag < 5 minutes

### 2.4 Monitor CDC Lag (Weeks 2-11)

**Weekly: CDC Health Check**
```bash
# Check CDC lag
psql -U postgres -d oracle_migration -c "
  SELECT 
    table_name, 
    last_scn, 
    last_timestamp,
    rows_applied,
    EXTRACT(EPOCH FROM (NOW() - last_timestamp)) / 60 as lag_minutes
  FROM public.cdc_checkpoint
  ORDER BY lag_minutes DESC;
"

# Alert if lag > 15 minutes
if [ $LAG_MINUTES -gt 15 ]; then
  echo "CDC LAG ALERT: $LAG_MINUTES minutes" | mail -s "CDC Lag Alert" dba-team@company.com
fi

# Check extractor & replay process health
ps aux | grep oracle_logminer_cdc
ps aux | grep cdc_replay_postgresql
```

**Troubleshooting Guide**:
- High lag: Increase CDC_PARALLEL_STREAMS, check network, PostgreSQL IOPS
- Extractor crash: Review logs, restart with --resume (resumes from last SCN)
- Replay lag: Check PostgreSQL CPU/disk, increase CDC_REPLAY_BATCH_SIZE

---

## Phase 3: Validation & Cutoff (Week 12)

### 3.1 Pre-Cutoff Reconciliation (Day 1-2)

**Day 1: Final Row Count Validation**
```bash
psql -U postgres -d oracle_migration -f scripts/reconciliation_checks.sql > final_reconciliation.txt

# Key checks:
# - All tables present: 100% match
# - All rows present: 100% match
# - All PKs unique
# - All FKs valid
# - CDC checkpoint current (< 5 min lag)
```

**Day 1-2: Business Logic Validation**
```bash
psql -U postgres -d oracle_migration -f scripts/business_validation.sql > business_final.txt

# Review results:
# - All sample queries return identical results to Oracle
# - Aggregates match (sums, counts, averages)
# - Joins produce same row counts
```

**Exit Criteria**: All reconciliation checks PASS, business queries match

### 3.2 Performance Validation (Day 2-3)

**Day 2-3: Performance Baseline**
```bash
bash scripts/performance_baseline.sh \
  --oracle-dsn "oracle://user:pwd@10.0.0.1:1521/ORCL" \
  --pg-dsn "postgresql://user:pwd@pg-target:5432/mydb" \
  --query-file config/sample_queries.sql > performance_report.txt

# Review report:
# - Flag queries > 20% slower than Oracle
# - Tune indexes if needed (EXPLAIN ANALYZE)
# - Add missing indexes if beneficial

# Expected result: 90% of queries within ±20% of Oracle
```

**Exit Criteria**: Performance acceptable (< 20% slower), no tuning blockers

### 3.3 Pre-Cutoff Sign-Off (Day 3)

**Checklist**:
```
☐ Row counts 100% match Oracle
☐ PK/FK validation passed (0 orphans)
☐ Checksum validation > 99.9%
☐ Business query results identical
☐ Performance baseline acceptable
☐ CDC queue empty (all changes applied)
☐ CDC lag < 1 minute
☐ Application team smoke test passed
☐ PostgreSQL backup validated
☐ Rollback plan documented & tested
☐ Cutoff window scheduled & approved
☐ Stakeholder sign-off obtained
```

**Approvals**:
- [ ] Database Lead
- [ ] Application Owner
- [ ] Infrastructure Lead
- [ ] Change Advisory Board

**Exit Criteria**: All checkboxes checked, all approvals obtained

### 3.4 Cutoff Window (Day 4)

**Morning - Preparation (T-30 min)**
```bash
# 1. Freeze source Oracle (READ ONLY mode)
sqlplus / as sysdba <<EOF
ALTER DATABASE READ ONLY;
SHUTDOWN;
STARTUP MOUNT;
ALTER DATABASE OPEN READ ONLY;
EOF

# 2. Final CDC sync (wait for lag to close)
sleep 120  # Wait 2 minutes for final changes

# 3. Verify CDC queue empty
du -sh /var/lib/cdc/changes.jsonl
# Expected: < 10 MB (minimal)
```

**Cutoff - Execute (T-00:00)**
```bash
# 1. Stop CDC extractor
killall python -f oracle_logminer_cdc

# 2. Stop CDC replay
killall python -f cdc_replay_postgresql

# 3. Final validation
psql -c "
  SELECT 'FINAL_CHECKPOINT' as check,
         COUNT(*) as tables_synced,
         MAX(last_scn) as final_scn,
         NOW() - MAX(last_timestamp) as final_lag
  FROM public.cdc_checkpoint;
"

# 4. Update application connection string
# Prepare: OLD: oracle://10.0.0.1:1521/ORCL
# NEW: postgresql://pg-target.postgres.database.azure.com:5432/oracle_migration

# 5. Switch DNS (or app config)
# Update: ORACLE_DB_HOST → PG_HOST
# Restart: Application services

# 6. Smoke test (20-30 key application queries)
./scripts/smoke_test.sh

# Expected: All queries return identical results, response time acceptable

# 7. Confirm go-live
echo "GO-LIVE SUCCESSFUL at $(date)" >> /var/log/migration.log
```

**Post-Cutoff (T+1 hour)**
```bash
# 1. Monitor PostgreSQL for issues
# Watch CPU, memory, disk I/O, connections
watch -n 5 'psql -c "SELECT version();"'

# 2. Monitor application logs for errors
tail -f /var/log/application.log | grep ERROR

# 3. Verify all users can connect
psql -U app_user -d oracle_migration -c "SELECT COUNT(*) FROM customers;"

# 4. Archive CDC artifacts
tar czf cdc_artifacts_$(date +%s).tar.gz \
  /var/lib/cdc/ /var/log/cdc_*.log

# 5. Keep Oracle READ ONLY for 72 hours (rollback window)
```

**Exit Criteria**: Application running on PostgreSQL, no errors, all users working

### 3.5 Rollback Procedure (if issues detected)

**If cutoff issues arise within 72 hours**:
```bash
# 1. Alert: Stop application
systemctl stop application

# 2. Restore Oracle to READ/WRITE
sqlplus / as sysdba <<EOF
SHUTDOWN IMMEDIATE;
STARTUP;
ALTER DATABASE READ WRITE;
EOF

# 3. Update application back to Oracle
# Rollback: PG_HOST → ORACLE_DB_HOST
systemctl start application

# 4. Investigate PostgreSQL issue
# Root cause analysis
# Plan re-attempt

# 5. Keep PostgreSQL in sync (CDC continues)
# Re-execute CDC capture/replay after fix

# 6. Retry cutoff once issues resolved
```

---

## Post-Cutoff Monitoring (Days 5-30)

### Daily Checks
```bash
# PostgreSQL health
psql -c "\du"  # List users
psql -c "\l"   # List databases
psql -c "SELECT version();"

# Query performance
SELECT query, calls, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;

# Monitor I/O
iostat -x 5

# Connection count
SELECT datname, usename, COUNT(*) FROM pg_stat_activity GROUP BY datname, usename;
```

### Weekly Tuning
- Add missing indexes (based on query performance)
- Optimize PostgreSQL parameters (shared_buffers, work_mem)
- Analyze query plans (EXPLAIN ANALYZE)

### Month 1 Post-Cutoff
- Decommission Oracle test environment
- Archive migration artifacts
- Conduct post-incident review

---

## Troubleshooting Guide

| Issue | Symptoms | Resolution |
|-------|----------|-----------|
| **CSV Transfer Slow** | ADF pipeline > 6 hours | Check network speed, increase ADF DIUs (Data Integration Units) |
| **Parquet Conversion Errors** | OOM errors, type mismatch | Reduce parallel jobs, check CSV data quality |
| **CDC Lag > 15 min** | Changes not replayed timely | Add CDC parallel streams, check Oracle redo logs, PostgreSQL IOPS |
| **Checksum Mismatch** | < 99.9% rows match | Investigate data type issues, character set encoding |
| **Query Performance Slow** | Queries > 20% slower | Add missing indexes, check statistics (ANALYZE), tune PostgreSQL parameters |
| **Foreign Key Violations** | FK constraint errors | Re-check data quality, verify CASCADE delete settings |
| **Cutoff Delay** | CDC lag won't close | Pause application writes, run CDC catch-up, increase batch size |

---

## Contact & Escalation

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| **Lead DBA** | John Smith | +1-425-555-0123 | john.smith@company.com |
| **App Owner** | Jane Doe | +1-425-555-0456 | jane.doe@company.com |
| **Azure Admin** | Mike Johnson | +1-425-555-0789 | mike.johnson@company.com |
| **On-Call** | PagerDuty | n/a | oncall@company.com |

---

**Migration Owner**: DBRE Team  
**Last Updated**: 2026-04-30  
**Status**: Active - Pre-Implementation

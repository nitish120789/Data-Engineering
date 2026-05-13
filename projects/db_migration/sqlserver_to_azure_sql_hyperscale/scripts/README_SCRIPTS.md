# SQL Server to Azure SQL Hyperscale Migration Scripts

This directory contains production-grade scripts for migrating a SQL Server OLTP database to Azure SQL Database Hyperscale using **CDC (Change Data Capture) + custom Python consumer** model.

---

## Quick Start

**Prerequisites:**
- SQL Server 2016 or later (source database)
- Azure SQL Database Hyperscale (target database)
- Python 3.8+ with pyodbc
- PowerShell 5.0+ (for orchestration scripts)
- sqlcmd command-line tool
- Network connectivity from migration machine to both source and target

**Installation:**
```bash
# Install Python dependencies
pip install pyodbc

# On Windows, install ODBC Driver 17 for SQL Server
# Download from: https://docs.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
```

---

## Script Reference

### 1. `schema_assessment.sql`
**Purpose:** Pre-migration assessment of source database schema and compatibility.

**Run on:** Source SQL Server (master database context)

**Output:** SQL result set showing:
- Database size and compatibility level
- CDC eligibility (missing PKs, CLR assemblies, linked servers)
- Index distribution
- Tables without primary keys (blocking CDC)

**Typical Usage:**
```sql
-- Run directly in SQL Server Management Studio or sqlcmd
sqlcmd -S sql-prod.contoso.com -d OrderDB -i schema_assessment.sql
```

**Expected Findings:**
- Tables without PKs cannot be replicated via CDC (must add PKs or exclude)
- Cross-database references not supported in Azure SQL Hyperscale (must refactor)
- CLR assemblies require rewrite (not supported in Hyperscale)

---

### 2. `bulk_seed_orchestration.ps1`
**Purpose:** Orchestrate backup of source database to Azure Blob Storage for baseline load.

**Run on:** Migration orchestration machine (with sqlcmd and Azure connectivity)

**Dependencies:**
- `sqlcmd` command-line tool
- Azure Storage account with write access
- Source SQL Server connectivity
- 4 hours of uninterrupted execution time for typical large databases

**Typical Usage:**
```powershell
.\bulk_seed_orchestration.ps1 `
    -SourceServer "sql-prod.contoso.com" `
    -SourceDatabase "OrderDB" `
    -StorageAccount "backupstg001" `
    -StorageContainer "sql-backups" `
    -StorageKey "...storage-account-key..." `
    -StripeCount 16

# Output:
# - Backup manifest written to logs/seed_manifest.txt
# - Backup script saved to logs/OrderDB_seed_20260513_143022_backup.sql
# - Backup log at logs/OrderDB_seed_20260513_143022_backup.log
```

**What It Does:**
1. Validates source SQL Server connectivity
2. Generates striped (parallel) backup URLs for Azure Blob
3. Executes BACKUP DATABASE command with compression and checksums
4. Records backup manifest and timing
5. Provides next-step instructions

**Post-Execution Steps:**
1. Verify backup files exist in Azure Storage (expected: 16 files totaling ~1.2x database size)
2. Create restore script with SAS token URLs
3. Execute `RESTORE DATABASE ... FROM URL ...` on target Azure SQL Hyperscale
4. Record restore duration and timing
5. Run `reconciliation_checks.sql` on target after restore completes

---

### 3. `sqlserver_cdc_extractor.py`
**Purpose:** Extract CDC (Change Data Capture) records from source SQL Server in batches.

**Run on:** Any machine with Python 3.8+ and source SQL Server connectivity

**Dependencies:**
- `pyodbc` Python package
- ODBC Driver 17 for SQL Server
- Source SQL Server with CDC enabled on target tables

**Typical Usage:**
```bash
python sqlserver_cdc_extractor.py \
    --source-conn "DRIVER={ODBC Driver 17 for SQL Server};Server=sql-prod;Database=OrderDB;UID=svc_migration;PWD=..." \
    --capture-instance "dbo_orders" \
    --from-lsn "00000029000000be0003" \
    --to-lsn "00000029000000c00001" \
    --out-file "cdc_batch_001.jsonl"

# Output: cdc_batch_001.jsonl containing ~1000-5000 CDC records (JSONL format)
```

**LSN (Log Sequence Number) Coordinates:**
- First run: Obtain from `cdc.fn_cdc_get_net_changes_<capture_instance>` with NULL LSN
- Subsequent runs: Use `last_lsn` from previous batch's checkpoint
- Query to find LSN: `SELECT sys.fn_cdc_map_time_to_lsn('greatest lower bound', GETUTCDATE());`

**Output Format (JSONL):**
```json
{"__$start_lsn":"00000029000000be0004","__$seqval":"00000000000001f4","__$operation":2,"__$update_mask":"0x03","order_id":1001,"customer_id":42,"total_amount":"299.99","order_date":"2026-05-13T10:30:00"}
{"__$start_lsn":"00000029000000be0005","__$seqval":"00000000000001f5","__$operation":4,"__$update_mask":"0x02","order_id":1001,"customer_id":42,"total_amount":"299.99","order_date":"2026-05-13T10:30:00"}
```

**Operation Codes:**
- `1` = DELETE
- `2` = INSERT
- `3` = UPDATE (before image)
- `4` = UPDATE (after image)

---

### 4. `azure_sql_replay_worker.py`
**Purpose:** Apply CDC change batches to Azure SQL Hyperscale target database.

**Run on:** Any machine with Python 3.8+, source SQL Server CDC data, and target Azure SQL connectivity

**Dependencies:**
- `pyodbc` Python package
- ODBC Driver 17 for SQL Server
- JSONL file from `sqlserver_cdc_extractor.py`

**Typical Usage:**
```bash
python azure_sql_replay_worker.py \
    --target-conn "Driver={ODBC Driver 17 for SQL Server};Server=sql-target.database.windows.net;Database=OrderDB;UID=dba;PWD=...;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" \
    --table-name "orders" \
    --pk-col "order_id" \
    --in-file "cdc_batch_001.jsonl" \
    --last-lsn "00000029000000c00001" \
    --batch-size 1000

# Output:
# - Checkpoint table created: dbo.cdc_checkpoint
# - Records applied: ~1000-5000
# - Checkpoint updated with last_lsn and rows_applied
# - Log message: "Applied 1234 records into dbo.orders"
```

**Checkpoint Table (auto-created):**
```sql
CREATE TABLE dbo.cdc_checkpoint (
    table_name NVARCHAR(256) NOT NULL PRIMARY KEY,
    last_lsn VARBINARY(10) NOT NULL,
    last_applied_at DATETIME2 NOT NULL,
    rows_applied BIGINT NOT NULL DEFAULT 0
);
```

**Batching Strategy:**
- Commits every 1000 records (configurable via `--batch-size`)
- Rollback on error (transaction isolation level = READ_COMMITTED)
- Idempotent (can re-run same batch; checkpoint updates atomically)

**Error Handling:**
- Invalid JSON → logged and skipped
- Connection failure → immediate rollback and exit
- Constraint violation → logged and exit (data integrity issue)

---

### 5. `reconciliation_checks.sql`
**Purpose:** Validate data parity between source and target databases.

**Run on:** Target Azure SQL Database (after baseline restore, before CDC sync; and again before cutover)

**Output:** SQL result set showing:
- Object inventory (table count, index count)
- Row count estimates per table
- Primary key constraint status
- Foreign key constraint count
- Identity/IDENTITY_INSERT seed status
- CDC checkpoint lag (if using custom CDC)
- Checklist for operator sign-off

**Typical Usage:**
```sql
-- Run on target Azure SQL Hyperscale
sqlcmd -S sql-target.database.windows.net -d OrderDB -i reconciliation_checks.sql

-- For linked-server cross-database comparison (requires setup):
-- sqlcmd -S sql-target.database.windows.net -d OrderDB -v source_server="LINKEDSERVER_SOURCE" source_db="OrderDB" -i reconciliation_checks.sql
```

**Key Validations:**
1. **Object Inventory:** Counts tables, indexes; compare source vs. target
2. **Row Counts:** Estimates per table (can be off by 10% due to partitioning)
3. **PK Integrity:** Finds duplicate PKs (should be 0)
4. **FK Integrity:** Lists FK constraints; checks orphaned refs if enforced
5. **Identity Drift:** Reports seed values and current identity
6. **CDC Lag:** Shows time since last CDC batch applied
7. **Checklist:** Operator sign-off template

**Interpretation:**
- ✅ All counts match source (100%)
- ⚠️ Row count diff < 1% → acceptable (index fragmentation/statistics lag)
- ❌ Duplicate PKs found → halt cutover, investigate
- ❌ CDC lag > 1 minute → wait for CDC catch-up or investigate lag

---

### 6. `performance_baseline.ps1`
**Purpose:** Compare query performance between source and target databases.

**Run on:** Migration orchestration machine (with sqlcmd connectivity to both databases)

**Dependencies:**
- `sqlcmd` command-line tool
- Query file (SQL batch file with GO-delimited queries)
- Source SQL Server connectivity
- Target Azure SQL Database connectivity

**Typical Usage:**
```powershell
# Create query batch file (e.g., test_queries.sql)
$queries = @"
-- Query 1: Top customers
SELECT TOP 100 customer_id, SUM(total_amount) FROM dbo.orders GROUP BY customer_id ORDER BY 2 DESC;
GO

-- Query 2: Daily sales
SELECT CAST(order_date AS DATE), COUNT(*), SUM(total_amount) FROM dbo.orders GROUP BY CAST(order_date AS DATE);
GO
"@

$queries | Out-File -FilePath test_queries.sql

# Run performance comparison
.\performance_baseline.ps1 `
    -SourceServer "sql-prod.contoso.com" `
    -TargetServer "sql-target.database.windows.net" `
    -Database "OrderDB" `
    -QueryFile "test_queries.sql" `
    -OutputFile "logs/performance_report.csv"

# Output: CSV with columns: query_name, source_ms, target_ms, delta_pct
```

**Output Format (performance_report.csv):**
```csv
query_name,source_ms,target_ms,delta_pct
"Query 1: Top customers",234,198,-15.38
"Query 2: Daily sales",567,512,-9.70
```

**Interpretation:**
- Positive delta_pct → target is slower (Hyperscale gen level may need upgrade)
- Negative delta_pct → target is faster (expected for Hyperscale with right provisioning)
- Delta within ±20% → acceptable (network latency, data distribution differences)
- Delta > +50% → investigate indexes, data types, or Hyperscale SLO

---

### 7. `business_validation.sql`
**Purpose:** Validate business-level parity (KPIs, aggregations, join integrity).

**Run on:** Both source SQL Server and target Azure SQL Database (compare results manually)

**Output:** SQL result set showing:
- Daily sales totals and customer counts
- Top 50 customers by revenue
- Order status distribution
- Order-Customer join integrity (orphan detection)
- Business rule violations (negative amounts, null status, future dates)

**Typical Usage:**
```sql
-- On source database
sqlcmd -S sql-prod.contoso.com -d OrderDB -i business_validation.sql > source_results.txt

-- On target database
sqlcmd -S sql-target.database.windows.net -d OrderDB -i business_validation.sql > target_results.txt

-- Compare
diff source_results.txt target_results.txt
```

**Customization:**
1. Edit queries 1-5 to reference your actual application tables/columns (not placeholder `orders` table)
2. Add domain-specific validation queries (inventory, GL accounts, customer balances)
3. Copy critical queries from your application QA test suite

**Expected Results:**
- All queries return matching result sets on source and target
- No business rule violations (negative amounts, null status, orphaned FKs)
- Operator approval before cutover

---

## End-to-End Migration Workflow

### Phase 1: Pre-Migration Assessment (Day 1)
```bash
# Assess source database schema
sqlcmd -S sql-prod -d OrderDB -i schema_assessment.sql
# Review: CDC eligibility, unsupported patterns, PKs present
# Action: Add PKs to tables without them, refactor cross-database refs
```

### Phase 2: Baseline Load (Days 1-3)
```powershell
# Execute backup and stage to Azure
.\bulk_seed_orchestration.ps1 `
    -SourceServer "sql-prod" `
    -SourceDatabase "OrderDB" `
    -StorageAccount "stg001" `
    -StorageKey "..." `
    -StripeCount 16

# Verify backup in Azure Storage
# Restore to target Hyperscale instance
# This typically takes 4-8 hours for 100+ GB databases
```

### Phase 3: Post-Load Validation (Day 3)
```sql
-- Validate baseline restore
sqlcmd -S sql-target.database.windows.net -d OrderDB -i reconciliation_checks.sql
# Review: Row counts, PK integrity, FK constraints
# Approve baseline before starting CDC
```

### Phase 4: CDC Sync (Days 3-7, parallel with testing)
```bash
# On production:
# 1. Enable CDC on source tables
# 2. Get baseline LSN (record in config)

# Then run extraction/apply loop:
for BATCH in {1..50}; do
    python sqlserver_cdc_extractor.py \
        --source-conn "DRIVER={...};Server=sql-prod;..." \
        --capture-instance "dbo_orders" \
        --from-lsn "<current_lsn>" \
        --to-lsn "<next_lsn>" \
        --out-file "batch_${BATCH}.jsonl"
    
    python azure_sql_replay_worker.py \
        --target-conn "Driver={...};Server=sql-target.database.windows.net;..." \
        --table-name "orders" \
        --pk-col "order_id" \
        --in-file "batch_${BATCH}.jsonl" \
        --last-lsn "<next_lsn>"
    
    # Monitor CDC lag
    sleep 300  # Run every 5 minutes
done
```

### Phase 5: Performance Baseline (Days 4-6)
```powershell
# Validate query performance parity
.\performance_baseline.ps1 `
    -SourceServer "sql-prod" `
    -TargetServer "sql-target.database.windows.net" `
    -Database "OrderDB" `
    -QueryFile "critical_queries.sql" `
    -OutputFile "perf_report.csv"

# Review: Target within ±20% of source
# Approve performance envelope
```

### Phase 6: Business Validation (Days 5-7)
```sql
-- Run business-specific validations
sqlcmd -S sql-prod -d OrderDB -i business_validation.sql > source.txt
sqlcmd -S sql-target.database.windows.net -d OrderDB -i business_validation.sql > target.txt

# Manual review and approval
# Compare: Daily revenue, top customers, order status distribution, etc.
```

### Phase 7: Cutover (Day 8, minimal downtime)
```sql
-- Monitor CDC checkpoint lag
SELECT * FROM dbo.cdc_checkpoint ORDER BY last_applied_at DESC;

-- When lag < 30 seconds:
-- 1. Stop application writes to source
-- 2. Wait for CDC lag to reach 0
-- 3. Drain any pending CDC batches
-- 4. Switch application connection string to target
-- 5. Start smoke tests on target
-- 6. Monitor for 24 hours before declaring cutover complete
```

---

## Operational Runbook

### Monitoring CDC Sync Progress
```sql
-- Check checkpoint status every 5 minutes during sync phase
SELECT 
    table_name, 
    last_applied_at, 
    rows_applied,
    DATEDIFF(SECOND, last_applied_at, SYSUTCDATETIME()) AS lag_seconds
FROM dbo.cdc_checkpoint
ORDER BY last_applied_at DESC;

-- Expected: lag_seconds < 60 (1 minute)
-- If lag > 5 minutes: check network, database lock contention, or resource bottleneck
```

### Troubleshooting Common Issues

**Issue: CDC extractor returns 0 records**
```sql
-- Verify CDC is enabled
SELECT * FROM sys.tables WHERE is_tracked_by_cdc = 1;

-- Verify capture instance
EXEC sys.sp_cdc_help_change_data_capture;

-- Check LSN range validity
SELECT sys.fn_cdc_get_min_lsn('dbo_orders'), sys.fn_cdc_get_max_lsn();
```

**Issue: Replay worker fails with "Primary key constraint violation"**
- Root cause: Duplicate PK in source CDC or pre-existing row in target
- Solution: Investigate data quality, run reconciliation_checks.sql, potentially re-seed

**Issue: Performance is 50% slower on target**
- Root cause: Hyperscale provisioning too low, missing indexes, or data type coercion
- Solution: Review performance_baseline.ps1 results, increase Hyperscale SLO, create missing indexes

---

## Best Practices

1. **Always run schema_assessment.sql first** — identify incompatibilities before starting migration
2. **Use striped backup (StripeCount=16)** — parallelize backup/restore for large databases
3. **Monitor CDC lag during sync** — keep lag < 1 minute; investigate spikes
4. **Run reconciliation_checks.sql multiple times** — after baseline, mid-sync, before cutover
5. **Perform business validation with real queries** — not placeholder queries
6. **Test cutover in non-prod first** — validate all automation on lower environment
7. **Keep audit trail** — save all output files, manifests, and logs for compliance

---

## Support & Documentation

- **Full Architecture:** See [ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- **Migration Runbook:** See [MIGRATION_RUNBOOK.md](../docs/MIGRATION_RUNBOOK.md)
- **CDC Implementation Details:** See [CDC_IMPLEMENTATION.md](../docs/CDC_IMPLEMENTATION.md)

---

**Author:** Nitish Anand Srivastava  
**Last Updated:** May 13, 2026

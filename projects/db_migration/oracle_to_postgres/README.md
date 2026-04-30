# Oracle to PostgreSQL Migration: Enterprise Scale (120+ TB)

## Executive Summary

This project documents a real-world, large-scale migration of a 120+ TB Oracle database to PostgreSQL using a hybrid cloud approach:
- **Initial bulk transfer**: Oracle exports via Azure Data Box → Azure Data Lake Storage → PostgreSQL
- **Schema conversion**: Oracle DDL → PostgreSQL native format
- **Delta sync (CDC)**: Oracle LogMiner captures changes post-snapshot → Python custom CDC → PostgreSQL
- **Validation**: Full reconciliation and pre-cutover validation before go-live

**Timeline**: Typical 8-12 week engagement (depends on complexity, data quality, network bandwidth)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│ Phase 1: Initial Bulk Load (Weeks 1-4)                             │
│                                                                     │
│  Oracle DB ──> Extract CSV ──> Azure Data Box ──> Azure Data Lake │
│                                                          │           │
│                                                    Convert to       │
│                                                    Parquet          │
│                                                          │           │
│                                            Azure Data Factory      │
│                                                  (ADF)              │
│                                                          │           │
│                                                          ▼           │
│                                              PostgreSQL (initial)  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Phase 2: CDC & Delta Sync (Weeks 2-11, overlapping)               │
│                                                                     │
│  Oracle LogMiner ──> Python CDC Script ──> Message Queue/Files    │
│       │                                            │                │
│       └─── Capture changes since SCN snapshot ────┘                │
│                                                   │                 │
│                                          Apply to PostgreSQL       │
│                                          (continuous until cutoff) │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Phase 3: Validation & Cutoff (Week 12)                            │
│                                                                     │
│  Row counts ──> PK/FK validation ──> Checksums ──> Sample queries │
│       │              │                    │              │         │
│       └──────────────┴────────────────────┴──────────────┘         │
│                                                                     │
│                         All green? ──> CUTOFF                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Project Plan

### **Phase 1: Initial Bulk Load (Weeks 1-4)**

#### 1.1 Pre-Migration Assessment
- **Audit Oracle schema** (tables, indexes, constraints, sequences, procedures, functions)
- **Estimate data volume** per table (especially >100 GB tables)
- **Identify Oracle-specific features** (partitioning, compression, LOBs, custom types) requiring conversion
- **Test PostgreSQL target environment** (sizing, network, storage I/O)

#### 1.2 Schema Extraction & Conversion
- Extract Oracle DDL using `dbms_metadata.get_ddl()` or `expdp`
- Convert to PostgreSQL-compatible format (PL/SQL → PL/pgSQL, datatypes, constraints)
- Create staging tables in PostgreSQL matching Oracle structure
- Test foreign key constraints and indexes after initial load (defer until data load complete)

#### 1.3 Bulk Data Export via Azure Data Box
**Why Data Box?**
- Handles large volumes (up to 1 TB per device) with minimal network strain
- Parallel parallel CSV exports from Oracle shards/partitions
- Ship physical device; Azure ingests to Data Lake Storage in parallel

**Steps:**
1. Use Oracle parallel exports (`expdp` or custom SQL `UNLOAD TO` equivalents)
2. Generate CSV files (~100-200 GB per file for manageability)
3. Load onto Azure Data Box device
4. Ship to Azure datacenter; automatic upload to Azure Data Lake Storage (ADLS)
5. Verify checksums post-upload

#### 1.4 CSV → Parquet Conversion
- Use Python script (`scripts/csv_to_parquet_converter.py`)
- Handles schema mapping, type inference, compression
- Stores Parquet files in ADLS for efficient columnar reads by ADF

#### 1.5 PostgreSQL Initial Load via Azure Data Factory
- ADF pipeline reads Parquet files from ADLS
- Stages to PostgreSQL target using bulk insert (`COPY`)
- Parallel streams for large tables (25-50 concurrent writers per table)
- Checkpoint table-by-table; resume on failure without re-processing

#### 1.6 Post-Load Validation (Phase 1)
- Row count reconciliation (Oracle source vs. PostgreSQL target)
- Sample query spot checks (aggregate sums, date ranges)
- Checksum validation (MD5 on row concatenation)

---

### **Phase 2: CDC & Delta Sync (Weeks 2-11, overlapping)**

#### 2.1 Change Data Capture Strategy
**Why Oracle LogMiner + Custom CDC?**
- Captures all DML changes (INSERT, UPDATE, DELETE) since snapshot SCN
- Works with Oracle EE and SE; no Streams/GoldenGate license required
- Custom Python script provides fine-grained control and PostgreSQL compatibility

**Flow:**
```
Oracle DB (LogMiner) → Extract REDO logs → Redo log dictionary
                                    ↓
                        Python CDC Script (redo_extractor.py)
                                    ↓
                    Parse SQL statements from redo
                                    ↓
                    Convert to PostgreSQL INSERTs/UPDATEs/DELETEs
                                    ↓
                    Queue to PostgreSQL (batch or stream)
                                    ↓
                        Apply to target DB
```

#### 2.2 LogMiner Setup
1. Enable supplemental logging on source tables:
   ```sql
   ALTER TABLE <table_name> ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
   ```
2. Archive redo logs (if not already in ARCHIVELOG mode)
3. Record starting SCN at snapshot time (used by CDC extractor)

#### 2.3 Python CDC Extractor
- Script: `scripts/oracle_logminer_cdc.py`
- Queries LogMiner (V$LOGMNR_CONTENTS) for committed DML
- Extracts row-level before/after images
- Converts Oracle types to PostgreSQL equivalents
- Handles sequences, LOBs, special characters
- Outputs to JSON queue or CSV log for replay in PostgreSQL

#### 2.4 Change Replay to PostgreSQL
- Consume from CDC queue
- Apply in original transaction order
- Handle conflicts (e.g., deletes of non-existent rows due to filtering)
- Track applied SCN high-water mark for resume on restart

#### 2.5 Parallel CDC Processing
- Multiple LogMiner instances per schema/table group
- Distribute large tables across parallel CDC extractors
- Merge change streams at PostgreSQL ingest tier

---

### **Phase 3: Data Reconciliation & Validation (Week 12)**

#### 3.1 Pre-Cutoff Reconciliation Checks
**Script: `scripts/reconciliation_checks.sql` (PostgreSQL)**

1. **Row Count Check**
   ```sql
   SELECT table_name, oracle_rows, pg_rows, 
          CASE WHEN oracle_rows = pg_rows THEN 'MATCH' ELSE 'MISMATCH' END
   FROM reconciliation_summary
   ORDER BY oracle_rows DESC;
   ```

2. **Primary Key Coverage**
   - All PKs in Oracle present in PostgreSQL
   - No orphaned rows in PostgreSQL

3. **Foreign Key Integrity**
   - All FKs from PostgreSQL resolve in target tables
   - No dangling references post-migration

4. **Checksum Validation** (sample rows per table)
   ```sql
   SELECT table_name, md5_match_count, total_rows,
          ROUND(100.0 * md5_match_count / total_rows, 2) AS match_pct
   FROM checksum_validation;
   ```

5. **Data Type Completeness**
   - No unexpected NULLs in NOT NULL columns
   - Date/numeric ranges within expected bounds

#### 3.2 Business Logic Validation
**Script: `scripts/business_validation.sql`**
- Sample queries from application: do results match Oracle?
- Aggregate totals by department/region/product line
- Period-over-period comparisons

#### 3.3 Performance Validation
**Script: `scripts/performance_baseline.sh`**
- Run 10-20 representative application queries
- Compare execution time Oracle vs. PostgreSQL
- Flag queries >20% slower (potential index tuning)

#### 3.4 CDC Lag Monitoring
- Confirm all changes since snapshot captured
- Verify no gaps in redo log coverage
- Check CDC extractor health (memory, CPU, network)

#### 3.5 Cutoff Readiness Checklist
```
Pre-Cutoff Sign-Off
====================
☐ Row counts match (all tables)
☐ PK/FK validation passed
☐ Checksum validation > 99.9% match
☐ Sample query results identical
☐ Performance baseline acceptable
☐ CDC queue empty; all changes applied
☐ Application team smoke test passed
☐ Backup verified (PostgreSQL)
☐ Rollback plan documented
☐ Cutoff window scheduled
```

---

## Project Deliverables

### Folder Structure
```
oracle_to_postgres/
├── README.md                          (this file)
├── docs/
│   ├── ARCHITECTURE.md                (detailed architecture)
│   ├── MIGRATION_RUNBOOK.md           (step-by-step execution)
│   ├── TROUBLESHOOTING.md             (common issues & fixes)
│   └── CUTOFF_PROCEDURE.md            (cutover checklist)
├── scripts/
│   ├── phase1_schema_extraction.sql   (Oracle DDL extraction)
│   ├── phase1_schema_conversion.py    (DDL conversion to PostgreSQL)
│   ├── csv_to_parquet_converter.py    (CSV bulk → Parquet)
│   ├── phase2_logminer_setup.sql      (LogMiner configuration)
│   ├── oracle_logminer_cdc.py         (CDC extractor)
│   ├── cdc_replay_postgresql.py       (Apply changes to PG)
│   ├── reconciliation_checks.sql      (Phase 3 validation)
│   ├── business_validation.sql        (Application-level checks)
│   ├── performance_baseline.sh        (Query performance comparison)
│   └── pre_migration_checklist.sql    (Pre-flight validation)
├── config/
│   ├── azure_databox.env              (Data Box config template)
│   ├── adf_pipeline.json              (Azure Data Factory pipeline)
│   ├── cdc_config.yaml                (CDC extractor config)
│   └── reconciliation_config.yaml     (Validation thresholds)
└── logs/
    ├── migration.log                  (execution log)
    └── cdc_progress.log               (CDC watermark tracking)
```

---

## Technology Stack

| Component | Purpose | Tool/Version |
|-----------|---------|--------------|
| Source DB | Oracle 12c/18c/19c/21c | Oracle EE/SE |
| Target DB | PostgreSQL 12+ | PostgreSQL 14/15/16 |
| Bulk Transfer | Data transport | Azure Data Box (1 TB devices) |
| Cloud Storage | Staging (CSV/Parquet) | Azure Data Lake Storage (Gen2) |
| ETL Orchestration | Pipeline automation | Azure Data Factory (ADF) |
| CDC | Change capture | Oracle LogMiner + Custom Python |
| Data Conversion | CSV ↔ Parquet | Python (pandas, pyarrow) |
| SQL Conversion | Oracle → PostgreSQL | ora2pg, sqlparse, custom Python |
| Validation | Data reconciliation | SQL (PostgreSQL), Python (pandas) |

---

## Prerequisites & Assumptions

### Infrastructure
- **Oracle**: 120+ TB, 12c+, ARCHIVELOG mode enabled
- **PostgreSQL**: 14+ with pgcrypto, pg_trgm extensions; sufficient disk for staging
- **Azure**: Data Lake Storage Gen2, Data Factory, Data Box service access
- **Network**: 1+ Gbps bandwidth between Oracle and Data Box staging area

### Access & Privileges
- **Oracle**: DBA role for schema extraction, LogMiner setup
- **PostgreSQL**: Superuser for initial schema creation
- **Azure**: Owner/Contributor role on subscription, Data Box, ADLS, ADF
- **OS**: Admin/sudo access on extraction hosts

### Pre-Work
- Source Oracle database backed up
- Target PostgreSQL test environment validated (sizing, network)
- Azure resources provisioned (ADLS, ADF, Data Box device reserved)
- Migration team trained on tools and rollback procedures

---

## Key Scripts & Their Usage

### Phase 1: Schema & Initial Load

#### `scripts/phase1_schema_extraction.sql` (Oracle)
Extracts all DDL for tables, indexes, sequences, constraints.
```sql
sqlplus / as sysdba @scripts/phase1_schema_extraction.sql
-- Outputs: oracle_schema_ddl.sql (to be converted)
```

#### `scripts/phase1_schema_conversion.py` (Python)
Converts extracted DDL from Oracle to PostgreSQL.
```bash
python scripts/phase1_schema_conversion.py \
  --input oracle_schema_ddl.sql \
  --output postgresql_schema_ddl.sql \
  --target-version 15
```

#### `scripts/csv_to_parquet_converter.py` (Python)
Bulk converts exported CSV files to Parquet for efficient ADF ingestion.
```bash
python scripts/csv_to_parquet_converter.py \
  --input-dir /mnt/databox/csv_exports \
  --output-dir /mnt/adls/parquet_staging \
  --compression snappy \
  --parallel 8
```

### Phase 2: CDC Capture & Replay

#### `scripts/phase2_logminer_setup.sql` (Oracle)
One-time LogMiner configuration and logging start.
```sql
sqlplus / as sysdba @scripts/phase2_logminer_setup.sql SNAPSHOT_SCN=<scn_value>
```

#### `scripts/oracle_logminer_cdc.py` (Python)
Main CDC extractor; runs continuously during cutoff window.
```bash
python scripts/oracle_logminer_cdc.py \
  --oracle-dsn "oracle://user:pwd@10.0.0.1:1521/ORCL" \
  --start-scn <snapshot_scn> \
  --output-queue /var/lib/cdc/changes.jsonl \
  --batch-size 10000 \
  --parallel 4
```

#### `scripts/cdc_replay_postgresql.py` (Python)
Consumes CDC queue and applies changes to PostgreSQL target.
```bash
python scripts/cdc_replay_postgresql.py \
  --pg-dsn "postgresql://user:pwd@pg-target.postgres.database.azure.com:5432/mydb" \
  --input-queue /var/lib/cdc/changes.jsonl \
  --batch-size 1000 \
  --checkpoint-table public.cdc_checkpoint
```

### Phase 3: Validation & Reconciliation

#### `scripts/reconciliation_checks.sql` (PostgreSQL)
Comprehensive row count and data validation.
```bash
psql -U postgres -d mydb -f scripts/reconciliation_checks.sql > reconciliation_report.txt
```

#### `scripts/business_validation.sql` (PostgreSQL)
Application-level spot checks (aggregates, joins, business rules).
```bash
psql -U postgres -d mydb -f scripts/business_validation.sql > business_report.txt
```

#### `scripts/performance_baseline.sh` (Bash/SQL)
Compares query performance Oracle vs. PostgreSQL.
```bash
bash scripts/performance_baseline.sh \
  --oracle-dsn "oracle://user:pwd@10.0.0.1:1521/ORCL" \
  --pg-dsn "postgresql://user:pwd@pg-target:5432/mydb" \
  --query-file config/sample_queries.sql
```

---

## Estimated Project Timeline

| Phase | Week(s) | Activities | Key Deliverable |
|-------|---------|-----------|-----------------|
| Assessment & Planning | 1 | Audit schema, size estimate, team onboarding | Migration Plan |
| Schema Extraction & Conversion | 1-2 | DDL extraction, type mapping, index design | PostgreSQL DDL script |
| Data Box & Azure Setup | 2-3 | Parallel CSV exports, Data Box ship, ADLS ingestion | CSV → Parquet staging |
| Initial Load (ADF) | 3-4 | Parquet load, row count validation, checksum spot checks | PostgreSQL with initial data |
| CDC Ramp-Up (parallel) | 2-3 | LogMiner config, CDC extractor testing, replay pipeline | CDC queue flowing |
| Delta Sync (continuous) | 2-11 | Monitor CDC lag, replay changes, incremental validation | Low-lag, current state |
| Cutoff Prep | 11-12 | Final reconciliation, business validation, performance baseline | Sign-off checklist |
| Cutoff & Go-Live | 12 | Quiesce source, final CDC sync, switch DNS, smoke test | Live on PostgreSQL |
| Post-Cutoff Support | +1 to +4 | Monitor stability, performance tuning, rollback standby | Stable production |

**Total Duration**: 8-12 weeks (varies by data complexity, team size, number of post-load iterations)

---

## Success Criteria

- ✅ **Row Parity**: 100% row count match across all tables
- ✅ **Data Integrity**: All PKs, UKs, FKs validated; no orphans
- ✅ **Checksum Validation**: ≥99.9% row-level checksums match
- ✅ **Business Validation**: 100% of sample queries return identical results
- ✅ **Performance**: 90% of queries perform within ±20% of Oracle baseline
- ✅ **CDC Completeness**: Zero missed changes since snapshot
- ✅ **Cutoff Window**: ≤2 hours of application downtime
- ✅ **Rollback Ready**: Source Oracle maintained in read-only for 72 hours post-cutoff

---

## Known Challenges & Mitigations

| Challenge | Mitigation |
|-----------|-----------|
| LOB handling (CLOBs >100 MB) | Use Oracle external tables + chunked Parquet export |
| Sequence gaps/resets post-load | Manually adjust PostgreSQL sequences; accept minor gaps |
| Custom Oracle types (objects, VARRAYs) | Flatten to relational tables pre-export; rebuild views |
| Oracle-specific functions in UDFs | Rewrite in PL/pgSQL or application tier |
| High CDC lag during peak load | Partition by table; run parallel CDC extractors |
| Time zone handling (DATE vs. TIMESTAMP) | Standardize to TIMESTAMP WITH TIME ZONE in PostgreSQL |
| Collation/character set differences | Validate UTF-8 consistency; test special characters early |

---

## Support & Escalation

- **Schema issues**: Review ora2pg docs; test DDL in non-prod PostgreSQL
- **Data type conversion**: Consult `config/datatype_mapping.yaml`
- **Performance tuning**: Use PostgreSQL EXPLAIN ANALYZE; compare to Oracle EXPLAIN PLAN
- **CDC lag**: Monitor LogMiner performance; consider table-level parallelization
- **Cutoff delays**: Pre-stage rollback script; alert stakeholders early

---

## Related Documentation

- [Architecture Details](docs/ARCHITECTURE.md)
- [Migration Runbook (Step-by-Step)](docs/MIGRATION_RUNBOOK.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Cutoff Procedure & Rollback](docs/CUTOFF_PROCEDURE.md)

---

## Version History

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| 1.0 | 2026-04-30 | DBRE Team | Initial comprehensive project structure |

---

**Last Updated**: 2026-04-30
**Status**: Active
**Owner**: Database Reliability Engineering

# Oracle to Amazon Aurora PostgreSQL Migration
## 100 GB Migration Using AWS DMS

## Executive Summary

This project documents a production-oriented migration of a 100 GB on-premises Oracle database to Amazon Aurora PostgreSQL using AWS Database Migration Service (AWS DMS). The migration pattern assumes:

- Schema conversion is completed before data movement.
- Initial seeding is performed through AWS DMS full load.
- Ongoing changes are synchronized through AWS DMS CDC.
- Final cutover is approved only after technical and business reconciliation.

This size is small enough to avoid offline data transfer devices, but large enough that poor schema conversion, unsupported object handling, or weak validation can still create production issues. The project is written for real execution, not just architecture review.

## Migration Goals

- Move Oracle source data and dependent application workload to Aurora PostgreSQL with minimal downtime.
- Convert Oracle schema, procedural logic, and access patterns into Aurora-compatible constructs.
- Use AWS DMS to reduce manual data copy and CDC complexity.
- Prove cutover readiness through repeatable validation and reconciliation.

## Target Use Case

Recommended for:
- 50 GB to 500 GB Oracle OLTP or mixed workload databases
- Moderate stored procedure/package usage
- Limited downtime window requiring CDC catch-up before cutover
- Teams using AWS DMS rather than custom CDC tooling

## End-to-End Flow

1. Discover source inventory, dependencies, and risk areas.
2. Extract Oracle schema and assess conversion complexity.
3. Convert schema using ora2pg and manual remediation for unsupported patterns.
4. Provision Aurora PostgreSQL and apply converted schema.
5. Run AWS DMS full load to seed target.
6. Keep target synchronized using AWS DMS CDC.
7. Validate rows, keys, hashes, and business outcomes.
8. Freeze source writes, drain CDC, reconcile, and cut over.

## Project Structure

oracle_to_aurora_postgresql_dms/
- README.md
- docs/
  - ARCHITECTURE.md
  - MIGRATION_RUNBOOK.md
  - SCHEMA_CONVERSION_GUIDE.md
  - VALIDATION_AND_CUTOVER.md
  - TROUBLESHOOTING.md
- scripts/
  - pre_migration_assessment.sql
  - dms_preflight_checks.sql
  - reconciliation_queries.sql
  - cutover_checklist.sh
  - sequence_reseed.sql
- config/
  - migration_config.yaml
  - dms_task_settings.json
  - dms_table_mappings.json
  - ora2pg.conf
  - security_and_network_controls.yaml
- logs/
  - .gitkeep

## Detailed Usage Walkthrough

### 1. Source discovery and readiness checks

Run source assessment from a host with SQL*Plus installed:

```bash
sqlplus system@ORCLPRD @scripts/pre_migration_assessment.sql
```

This collects:
- database version and character set
- largest tables and LOB footprint
- invalid objects
- archive log generation trend
- object types likely to need manual conversion

Run DMS preflight checks:

```bash
sqlplus system@ORCLPRD @scripts/dms_preflight_checks.sql dms_user APP_SCHEMA
```

This verifies:
- ARCHIVELOG and FORCE LOGGING state
- supplemental logging posture
- DMS user privileges
- long-running transactions
- tables without primary keys

### 2. Schema conversion using ora2pg

This project assumes ora2pg is used for first-pass conversion, with manual review for packages, triggers, and Oracle-specific semantics.

Example workflow:

```bash
ora2pg -c config/ora2pg.conf -p -t SHOW_REPORT > logs/ora2pg_report.txt
ora2pg -c config/ora2pg.conf -t TABLE -o logs/schema_tables.sql
ora2pg -c config/ora2pg.conf -t VIEW -o logs/schema_views.sql
ora2pg -c config/ora2pg.conf -t SEQUENCE -o logs/schema_sequences.sql
ora2pg -c config/ora2pg.conf -t FUNCTION -o logs/schema_functions.sql
```

Then apply reviewed DDL to Aurora PostgreSQL:

```bash
psql "host=aurora-pg.cluster-xxxx.us-east-1.rds.amazonaws.com port=5432 dbname=appdb user=migration_user sslmode=require" -f logs/schema_tables.sql
psql "host=aurora-pg.cluster-xxxx.us-east-1.rds.amazonaws.com port=5432 dbname=appdb user=migration_user sslmode=require" -f logs/schema_views.sql
psql "host=aurora-pg.cluster-xxxx.us-east-1.rds.amazonaws.com port=5432 dbname=appdb user=migration_user sslmode=require" -f logs/schema_sequences.sql
```

### 3. Initial seeding with AWS DMS full load

Use these config files:
- config/dms_task_settings.json
- config/dms_table_mappings.json

Example AWS CLI pattern:

```bash
aws dms create-replication-task \
  --replication-task-identifier oracle100gb-full-load-cdc \
  --source-endpoint-arn arn:aws:dms:us-east-1:123456789012:endpoint:SRCENDPOINT \
  --target-endpoint-arn arn:aws:dms:us-east-1:123456789012:endpoint:TGTENDPOINT \
  --replication-instance-arn arn:aws:dms:us-east-1:123456789012:rep:REPLICATIONINSTANCE \
  --migration-type full-load-and-cdc \
  --table-mappings file://config/dms_table_mappings.json \
  --replication-task-settings file://config/dms_task_settings.json
```

Start the task:

```bash
aws dms start-replication-task \
  --replication-task-arn arn:aws:dms:us-east-1:123456789012:task:TASKARN \
  --start-replication-task-type start-replication
```

### 4. CDC monitoring and operational checks

Monitor task health and lag:

```bash
aws dms describe-replication-tasks \
  --filters Name=replication-task-id,Values=oracle100gb-full-load-cdc
```

Validate that:
- full load has completed successfully
- CDC latency is within agreed threshold
- no repeated table-level apply failures exist
- no unresolved LOB truncation or datatype mapping issues remain

### 5. Reconciliation and validation

Use scripts/reconciliation_queries.sql as a template for Oracle and Aurora PostgreSQL comparison queries. Replace placeholders before execution.

Example Aurora run:

```bash
psql "host=aurora-pg.cluster-xxxx.us-east-1.rds.amazonaws.com port=5432 dbname=appdb user=validator sslmode=require" -f scripts/reconciliation_queries.sql
```

After DMS full load, and again before cutover, validate:
- table row counts
- primary key uniqueness
- sampled checksum parity
- nullability drift on critical columns
- business KPI parity on critical reports

### 6. Sequence reseed before write cutover

After final CDC drain and before enabling writes on Aurora PostgreSQL, run:

```bash
psql "host=aurora-pg.cluster-xxxx.us-east-1.rds.amazonaws.com port=5432 dbname=appdb user=migration_user sslmode=require" -f scripts/sequence_reseed.sql
```

### 7. Cutover execution

Set required environment variables and run the checklist driver:

```bash
export DMS_TASK_ARN="arn:aws:dms:us-east-1:123456789012:task:TASKARN"
export DMS_LAG_CHECK_COMMAND="./ops/check_dms_lag_zero.sh"
export SOURCE_FREEZE_COMMAND="./ops/freeze_oracle_writes.sh"
export RECON_SCRIPT_PATH="./ops/run_final_reconciliation.sh"
export ROLLBACK_COMMAND="./ops/rollback_to_oracle.sh"
export MAX_WAIT_SECONDS=1800
bash scripts/cutover_checklist.sh
```

## Known Issues Covered in This Pack

- Oracle NUMBER without precision causing unsafe PostgreSQL type guesses
- Empty string versus NULL behavior changes in PostgreSQL
- Oracle packages and autonomous transactions requiring redesign
- AWS DMS LOB mode tuning and truncation risk
- Missing PKs causing update/delete ambiguity during CDC
- Sequence drift after full load and CDC
- DDL drift after DMS task start
- Business reports matching row counts but failing semantic validation

## Success Criteria

- Schema conversion issues are cataloged and resolved before DMS full load.
- DMS full load completes without unresolved critical table failures.
- CDC lag remains within agreed SLO before freeze.
- Reconciliation passes technical and business thresholds.
- Cutover completes within approved downtime with tested rollback path.

## Author

Author: Nitish Anand Srivastava

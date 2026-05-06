# Oracle (On-Prem) to Azure Database for PostgreSQL Flexible Server
## Migration Blueprint: 40+ TB with Azure Data Box + Azure DMS

## Executive Summary

This project provides a production-grade migration blueprint for moving a 40+ TB on-premises Oracle workload to Azure Database for PostgreSQL Flexible Server using a two-track strategy:

1. Initial bulk transfer via Azure Data Box (offline physical transfer to avoid WAN bottlenecks)
2. Continuous synchronization via Azure Database Migration Service (DMS) from Oracle source to PostgreSQL target

The content is designed for enterprise migrations that include strict change control, limited downtime, high-volume CDC, schema conversion challenges, and non-functional requirements (performance, security, rollback, and reconciliation).

## Why This Pattern

For very large Oracle estates, network-only migration often fails on timeline and consistency requirements. Data Box + DMS enables:

- Fast initial load without saturating MPLS/ExpressRoute for weeks
- CDC catch-up while applications remain online
- Controlled cutover with measured downtime window
- Repeatable validation and reconciliation checkpoints

## Scope

In scope:
- Oracle schema and code conversion assessment and remediation
- Data movement for 40+ TB baseline and continuous changes
- DMS configuration and tuning for high-throughput CDC
- Cutover orchestration and application switchover
- Data validation, reconciliation, and rollback preparedness

Out of scope:
- Application functional refactoring
- Full Oracle feature parity for proprietary packages without redesign
- Non-relational or external system reconciliation not tied to migration scope

## Target Architecture (Condensed)

1. Oracle source exports baseline slices (partition/window based) to flat files.
2. Files are copied to Azure Data Box and ingested into Azure Storage.
3. Baseline data is loaded to Azure PostgreSQL Flexible Server staging/final schemas.
4. Azure DMS keeps target synchronized using ongoing replication.
5. Reconciliation gates verify row counts, hashes, business KPIs, and CDC lag.
6. Controlled freeze and cutover complete migration.

See detailed diagrams and dependency flows in docs/ARCHITECTURE.md.

## Phased Delivery Model

- Phase 0: Discovery and readiness (2-4 weeks)
- Phase 1: Schema conversion and compatibility remediation (2-6 weeks)
- Phase 2: Baseline extraction and Data Box transfer (1-3 weeks)
- Phase 3: DMS continuous sync and defect burn-down (2-6 weeks)
- Phase 4: Dress rehearsal cutovers and production cutover (1-2 weeks)
- Phase 5: Hypercare and optimization (1-2 weeks)

## Key Real-World Risks Covered

- SCN drift and CDC start-point mismatch
- Unlogged source-side DDL during migration window
- LOB handling edge cases and character set corruption
- Oracle package/function translation gaps
- DMS task backpressure and apply latency spikes
- Checkpoint inconsistencies and replay duplication risk
- Sequence reseeding issues post-cutover
- Business reconciliation deltas despite technical row-count match

## Project Structure

oracle_to_azure_postgresql_flexible_server_dms_databox/
- README.md
- docs/
  - ARCHITECTURE.md
  - MIGRATION_RUNBOOK.md
  - SCHEMA_CONVERSION_GUIDE.md
  - CUTOVER_VALIDATION_RECONCILIATION.md
  - TROUBLESHOOTING.md
- scripts/
  - pre_migration_assessment.sql
  - databox_export_manifest_template.csv
  - dms_preflight_checks.sql
  - reconciliation_queries.sql
  - cutover_orchestration.sh
- config/
  - migration_config.yaml
  - dms_task_settings.json
  - dms_table_mappings.json
  - security_and_network_controls.yaml
- logs/
  - .gitkeep

## Success Criteria

- 100% critical schemas migrated and validated
- CDC lag within agreed SLO before freeze window
- Reconciliation thresholds met:
  - Row count mismatch <= 0.01% non-critical tables
  - Hash mismatch = 0 for critical entities
  - Financial/business KPI parity within signed tolerance
- Cutover completed within approved downtime
- Rollback plan tested and executable

## Tooling Reference

- Azure Database Migration Service (online mode where supported)
- Azure Data Box for physical transfer
- Azure Storage account staging zone
- Azure Database for PostgreSQL Flexible Server
- Optional conversion helpers: ora2pg, SCT, custom SQL/Python mappers

## Script Usage Examples

The examples below show a practical run order for the scripts in this project.

Minimum tools expected on operator host:
- Oracle SQL*Plus client
- psql client for PostgreSQL
- Azure CLI authenticated to target subscription
- Bash shell for cutover orchestration script

### 1. Run source assessment on Oracle

```bash
sqlplus system@ORCLP01 @scripts/pre_migration_assessment.sql
```

Expected output:
- Oracle version and character set details
- Largest-table and LOB footprint profile
- Invalid object list and redo generation trend

### 2. Run DMS preflight checks on Oracle

```bash
sqlplus system@ORCLP01 @scripts/dms_preflight_checks.sql dms_user ERP
```

This validates ARCHIVELOG mode, supplemental logging, privileges, and tables without PKs.

### 3. Prepare Data Box manifest for baseline exports

Use the template file:

```text
scripts/databox_export_manifest_template.csv
```

Populate one row per export chunk with:
- table name and chunk id
- anchor SCN
- row count and file size
- SHA-256 checksum
- source path and Data Box path

### 4. Apply DMS settings and table mappings

Use:
- `config/dms_task_settings.json`
- `config/dms_table_mappings.json`

Example Azure CLI flow:

```bash
az dms task create \
  --resource-group rg-migration \
  --service-name dms-prod \
  --project-name oracle-to-pg \
  --name oracle40tb-prod-cdc \
  --source-endpoint source-oracle \
  --target-endpoint target-pg-flex \
  --table-mappings "@config/dms_table_mappings.json" \
  --task-type migrate \
  --migration-type online
```

Note: exact DMS CLI parameters can vary by service/API version. Keep this as a template and adjust to your subscription setup.

### 5. Execute reconciliation queries during dry-run/cutover

The file `scripts/reconciliation_queries.sql` is a template. Replace placeholders such as `%TABLE_NAME%`, `%PK_COL%`, and `%FILTER_PREDICATE%` before execution.

Example on PostgreSQL:

```bash
psql "host=pg-flex-prod.postgres.database.azure.com port=5432 dbname=appdb user=migration_user sslmode=require" \
  -f scripts/reconciliation_queries.sql
```

Important:
- This file includes separate Oracle and PostgreSQL query blocks.
- Replace placeholders like <TABLE_NAME>, <PK_COL>, <WINDOW_START> before execution.
- Keep the same table window and sort key in both engines for meaningful checksum comparison.

### 6. Run cutover orchestration skeleton

Set required environment variables and execute:

```bash
export SOURCE_FREEZE_COMMAND="./ops/freeze_writes.sh"
export DMS_TASK_NAME="oracle40tb-prod-cdc"
export RECON_SCRIPT_PATH="./ops/run_final_reconciliation.sh"
export DMS_LAG_CHECK_COMMAND="./ops/check_dms_lag_zero.sh"
export DMS_MAX_WAIT_SECONDS=3600
export DMS_POLL_INTERVAL_SECONDS=20
export ROLLBACK_COMMAND="./ops/rollback_cutover.sh"
bash scripts/cutover_orchestration.sh
```

PowerShell equivalent:

```powershell
$env:SOURCE_FREEZE_COMMAND = "./ops/freeze_writes.sh"
$env:DMS_TASK_NAME = "oracle40tb-prod-cdc"
$env:RECON_SCRIPT_PATH = "./ops/run_final_reconciliation.sh"
$env:DMS_LAG_CHECK_COMMAND = "./ops/check_dms_lag_zero.sh"
$env:DMS_MAX_WAIT_SECONDS = "3600"
$env:DMS_POLL_INTERVAL_SECONDS = "20"
$env:ROLLBACK_COMMAND = "./ops/rollback_cutover.sh"
bash scripts/cutover_orchestration.sh
```

### Junior DBA Dry-Run Checklist (recommended before production)

1. Execute pre-assessment and save output logs.
2. Execute DMS preflight checks and resolve all privilege/PK gaps.
3. Validate Data Box manifest entries for chunk counts and checksums.
4. Start DMS in rehearsal environment and validate lag behavior over peak traffic window.
5. Run reconciliation template for at least five critical tables and confirm parity.
6. Execute cutover_orchestration.sh in rehearsal with timeout and rollback hooks configured.

### Recommended execution order

1. `pre_migration_assessment.sql`
2. `dms_preflight_checks.sql`
3. Data Box manifest population and baseline export shipment
4. DMS task creation using config JSON files
5. Reconciliation template adaptation and repeated validation runs
6. `cutover_orchestration.sh` during rehearsal and production cutover

## Author

Author: Nitish Anand Srivastava

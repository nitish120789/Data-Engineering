# SQL Server to Azure SQL Database Hyperscale
## Migration Blueprint: Azure DMS Online Sync + Exhaustive Reconciliation

## Executive Summary

This project provides a production-ready migration blueprint for SQL Server to Azure SQL Database Hyperscale using:

1. Baseline seed via native backup/restore or bulk load
2. Continuous delta sync via Azure Database Migration Service (Azure DMS)
3. Exhaustive reconciliation with row counts, bucketed hashing for large tables, and business aggregate validation (SUM, MIN, MAX)

The package is designed for enterprise cutovers where low downtime and high confidence validation are mandatory.

## Why This Project

Compared to custom CDC workers, this pattern is used when teams prefer managed replication and centralized operational controls:

- Managed online migration orchestration with Azure DMS
- Lower custom-code maintenance burden during sync
- Repeatable, auditable reconciliation process with strict sign-off gates
- Scalable hash validation on very large tables using deterministic buckets

## Scope

In scope:
- SQL Server readiness and DMS preflight validation
- Azure DMS task templates for online migration
- Exhaustive reconciliation script framework for technical and business parity
- Cutover orchestration skeleton with lag and validation gates

Out of scope:
- Application refactor
- Cross-platform SQL rewrite for non-SQL-Server engines
- End-user functional test automation

## Project Structure

sqlserver_to_azure_sql_hyperscale_azure_dms/
- README.md
- docs/
  - ARCHITECTURE.md
  - MIGRATION_RUNBOOK.md
  - VALIDATION_AND_RECONCILIATION.md
  - TROUBLESHOOTING.md
- scripts/
  - pre_migration_assessment.sql
  - dms_preflight_checks.sql
  - exhaustive_reconciliation_and_hashing.sql
  - business_validation.sql
  - run_reconciliation.ps1
  - cutover_orchestration.ps1
- config/
  - migration_config.yaml
  - dms_task_settings.json
  - dms_table_mappings.json
  - business_validation_rules.yaml
- logs/
  - .gitkeep

## Key Validation Features

The reconciliation framework in this project includes:

1. Table-level row count parity
2. PK coverage and duplicate checks
3. Bucketed hash validation for large tables (scales without full-table string aggregation)
4. Business aggregate checks with SUM, MIN, MAX, COUNT for critical columns
5. Deterministic run-id snapshots for source/target comparison
6. Threshold-based severity model (critical vs non-critical)

## Success Criteria

- DMS task running with healthy CDC lag before freeze
- All critical tables: row_count_diff = 0 and bucket_hash_mismatch = 0
- Business aggregate mismatches <= signed tolerance
- Cutover completed in approved downtime window
- Rollback path verified before production switch

## Recommended Execution Order

1. scripts/pre_migration_assessment.sql
2. scripts/dms_preflight_checks.sql
3. Azure DMS task create/start using config JSON templates
4. scripts/exhaustive_reconciliation_and_hashing.sql on SOURCE with shared run_id
5. scripts/exhaustive_reconciliation_and_hashing.sql on TARGET with same run_id
6. scripts/business_validation.sql on SOURCE and TARGET
7. scripts/run_reconciliation.ps1 for automated compare output
8. scripts/cutover_orchestration.ps1 during final cutover

## Script Usage (Quick)

Source snapshot capture:

```powershell
sqlcmd -S sql-prod.company.local -d ERPDB -E -v RUN_ID="A6F52B4A-4D6A-4FD4-9988-5D4C3CBE8C20" ROLE="SOURCE" LINKED_SERVER="" SOURCE_DB="" -i scripts/exhaustive_reconciliation_and_hashing.sql
```

Target snapshot capture + compare to source:

```powershell
sqlcmd -S sql-target.database.windows.net -d ERPDB -G -v RUN_ID="A6F52B4A-4D6A-4FD4-9988-5D4C3CBE8C20" ROLE="TARGET" LINKED_SERVER="LS_SQL_SOURCE" SOURCE_DB="ERPDB" -i scripts/exhaustive_reconciliation_and_hashing.sql
```

Business aggregate validation:

```powershell
sqlcmd -S sql-prod.company.local -d ERPDB -E -i scripts/business_validation.sql > logs/business_source.txt
sqlcmd -S sql-target.database.windows.net -d ERPDB -G -i scripts/business_validation.sql > logs/business_target.txt
```

## Author

Author: Nitish Anand Srivastava

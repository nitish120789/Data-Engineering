# Migration Runbook

## 1. Pre-Migration Readiness

1. Run scripts/pre_migration_assessment.sql on source SQL Server.
2. Resolve unsupported features and tables missing primary keys.
3. Run scripts/dms_preflight_checks.sql and close all blockers.
4. Confirm target Azure SQL Hyperscale sizing (compute tier, storage, HA).

## 2. Baseline Load

1. Seed target using restore/load process.
2. Validate table counts and object inventory after baseline.
3. Record baseline completion timestamp and migration ticket id.

## 3. Azure DMS Setup

1. Create Azure DMS service and migration project.
2. Define source and target endpoints.
3. Create task with config/dms_table_mappings.json and config/dms_task_settings.json.
4. Start task and monitor lag/throughput.

## 4. Reconciliation Dress Rehearsal

1. Generate a shared run_id (GUID).
2. Capture SOURCE snapshot using exhaustive_reconciliation_and_hashing.sql.
3. Capture TARGET snapshot using same run_id.
4. Run compare section from target using linked server to source.
5. Fix all critical mismatches before production window.

## 5. Cutover

1. Freeze source writes.
2. Wait until DMS lag reaches defined threshold (for example, <= 30 seconds).
3. Execute final reconciliation snapshot and comparison.
4. Switch application connection to target.
5. Run smoke tests and business validation queries.

## 6. Rollback Gate

Rollback trigger examples:
- Critical hash mismatch on critical table
- Business KPI mismatch beyond signed tolerance
- Application regression during smoke tests

If rollback is triggered:
1. Route application back to source
2. Unfreeze source writes
3. Archive cutover evidence and incident timeline

## 7. Hypercare

1. Monitor p95 latency and error rates for 24-72 hours.
2. Track blocked sessions, deadlocks, and top waits.
3. Re-run business validation daily in hypercare window.

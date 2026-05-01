# Commit Manifest: Cross-Engine Reconciliation Framework

Date: 2026-05-01
Owner: Database Reliability Engineering

## Objective

Add a dedicated, detailed, cross-engine reconciliation project focused on validating and remediating migration gaps during and post migration.

## Core Coverage

- Count(*) parity and segmented count parity
- Hash and sum-of-hash parity
- Object and constraint parity
- Update/delete parity validation
- Gap classification and fix planning
- Gap remediation SQL patterns by engine

## Engines Included

- Oracle
- SQL Server
- MySQL
- PostgreSQL

## Script Types Included

- SQL templates per engine (reconciliation + remediation)
- Shell runners per engine
- Python runners per engine
- Common Python comparator/classifier and shell orchestrator

## Added Paths

- projects/db_migration/cross_engine_reconciliation_framework/README.md
- projects/db_migration/cross_engine_reconciliation_framework/docs/RECONCILIATION_STRATEGIES.md
- projects/db_migration/cross_engine_reconciliation_framework/docs/GAP_REMEDIATION_PLAYBOOK.md
- projects/db_migration/cross_engine_reconciliation_framework/config/reconciliation_config.yaml
- projects/db_migration/cross_engine_reconciliation_framework/scripts/common/reconciliation_runner.py
- projects/db_migration/cross_engine_reconciliation_framework/scripts/common/reconciliation_runner.sh
- projects/db_migration/cross_engine_reconciliation_framework/scripts/common/gap_classifier.py
- projects/db_migration/cross_engine_reconciliation_framework/scripts/oracle/reconciliation.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/oracle/gap_fix.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/oracle/run_reconciliation.sh
- projects/db_migration/cross_engine_reconciliation_framework/scripts/oracle/run_reconciliation.py
- projects/db_migration/cross_engine_reconciliation_framework/scripts/sqlserver/reconciliation.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/sqlserver/gap_fix.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/sqlserver/run_reconciliation.sh
- projects/db_migration/cross_engine_reconciliation_framework/scripts/sqlserver/run_reconciliation.py
- projects/db_migration/cross_engine_reconciliation_framework/scripts/mysql/reconciliation.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/mysql/gap_fix.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/mysql/run_reconciliation.sh
- projects/db_migration/cross_engine_reconciliation_framework/scripts/mysql/run_reconciliation.py
- projects/db_migration/cross_engine_reconciliation_framework/scripts/postgresql/reconciliation.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/postgresql/gap_fix.sql
- projects/db_migration/cross_engine_reconciliation_framework/scripts/postgresql/run_reconciliation.sh
- projects/db_migration/cross_engine_reconciliation_framework/scripts/postgresql/run_reconciliation.py
- COMMIT_MANIFEST_RECONCILIATION_FRAMEWORK.md

## Notes

- Scripts are template-grade and require environment-specific table/column mapping before production execution.
- Hash parity uses canonical expression patterns and should be aligned with approved datatype normalization rules.

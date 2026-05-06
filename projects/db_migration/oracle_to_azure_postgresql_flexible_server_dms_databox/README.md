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

## Author

Author: Nitish Anand Srivastava

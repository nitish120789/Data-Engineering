# Migration Runbook
## Oracle to Amazon Aurora PostgreSQL Using AWS DMS

## 1. Pre-Migration Prerequisites

Source Oracle:
- ARCHIVELOG enabled
- FORCE LOGGING enabled for consistency
- Supplemental logging enabled for in-scope schemas/tables
- DMS user created with required dictionary and object privileges
- Backup/restore validated before migration window

Target Aurora PostgreSQL:
- Cluster and writer instance provisioned
- Parameter group reviewed for workload profile
- Migration user, application user, and validation user created
- Storage, connection count, and failover posture validated

AWS DMS infrastructure:
- Replication instance sized for full load plus CDC overhead
- Replication subnet group and security groups configured
- Source and target endpoint creation planned and tested
- CloudWatch logs and metrics access confirmed for migration team

Operator host:
- SQL*Plus installed
- psql installed
- aws cli installed and authenticated
- ora2pg installed and tested
- output directory for evidence and logs created in advance

## 2. Phase 0: Discovery

1. Run scripts/pre_migration_assessment.sql.
2. Capture top 20 tables by size and growth rate.
3. Inventory packages, triggers, materialized views, jobs, synonyms, and DB links.
4. Classify objects into:
   - automatic conversion likely
   - manual remediation required
   - redesign needed

Exit criteria:
- migration scope frozen
- unsupported Oracle features cataloged
- cutover window assumptions approved

## 3. Phase 1: Schema Conversion

1. Configure config/ora2pg.conf for source schema.
2. Generate ora2pg assessment report.
3. Export schema objects in batches: tables, views, sequences, functions.
4. Review generated DDL for datatype correctness and naming conventions.
5. Apply converted schema to lower environment Aurora instance.
6. Run unit validation for application-critical routines.

Common conversion issues and fixes:
- NUMBER without precision:
  - profile actual values and choose bigint or numeric explicitly.
- Oracle DATE semantics include time:
  - map intentionally to timestamp where application expects time component.
- Empty string handling:
  - patch application logic and queries that depended on Oracle behavior.
- Packages and autonomous transactions:
  - refactor to PL/pgSQL plus app/service logic where needed.
- Function-based indexes:
  - use PostgreSQL expression indexes or generated columns.

Exit criteria:
- critical schema objects created successfully on Aurora
- open conversion defects prioritized and owned

## 4. Phase 2: AWS DMS Preflight and Full Load

1. Run scripts/dms_preflight_checks.sql.
2. Create source and target endpoints.
3. Validate endpoint connectivity from AWS DMS to Oracle and Aurora.
4. Review config/dms_table_mappings.json and config/dms_task_settings.json.
5. Create replication task in full-load-and-cdc mode.
6. Start task and monitor full-load progress.

Watch for:
- tables failing due to unsupported datatypes
- large LOB columns stuck in retry loops
- constraint violations during target apply
- apply pauses due to insufficient target capacity
- DMS endpoint tests failing because of network ACL, routing, or DNS problems

Exit criteria:
- full load completed for all in-scope critical tables
- no unresolved critical DMS table failures
- endpoint tests are successful for both source and target

## 5. Phase 3: CDC Stabilization

1. Keep AWS DMS task running after full load.
2. Monitor CDCLatencySource and CDCLatencyTarget.
3. Review task logs for repeated warnings and retries.
4. Validate no in-scope DDL changes are occurring on source.
5. Reconcile high-churn tables multiple times before cutover.

Healthy target state:
- source and target latency remain within threshold
- no repeated apply errors on critical tables
- business owners accept rehearsal validation results

## 6. Phase 4: Validation and Reconciliation

1. Run row-count checks for all critical tables.
2. Run duplicate PK and nullability checks.
3. Run deterministic checksums on representative windows.
4. Compare application-facing reports and aggregates.
5. Validate sequences and generated keys.
6. Record all mismatches with severity and disposition.

Mismatch handling:
- block cutover for financial/compliance mismatches
- quarantine and resolve sequence issues before enabling writes
- do not accept row-count-only validation as sufficient

## 7. Phase 5: Production Cutover

1. Freeze source writes.
2. Wait for AWS DMS CDC lag to drain.
3. Run final reconciliation pack.
4. Run scripts/sequence_reseed.sql.
5. Switch application connection strings and secrets.
6. Execute smoke tests and business validation.
7. Keep Oracle available for rollback window until sign-off.

Rollback triggers:
- critical transaction failures
- unreconciled Class A data mismatch
- unacceptable performance regression on critical workload

## 8. Hypercare

- monitor Aurora performance, locks, connections, and replication artifacts
- compare business KPIs for at least one full business cycle
- retire DMS task only after business and operational sign-off

## Author

Author: Nitish Anand Srivastava

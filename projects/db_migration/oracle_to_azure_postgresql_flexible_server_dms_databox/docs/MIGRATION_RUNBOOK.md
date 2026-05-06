# Migration Runbook
## Oracle On-Prem (40+ TB) to Azure PostgreSQL Flexible Server
## With Azure Data Box Baseline + Azure DMS Continuous Sync

## 1. Program Governance and Controls

- Change model: CAB-approved wave plan with freeze windows.
- Command center: migration bridge with incident timeline and single decision owner.
- Environments: DEV -> SIT -> PERF -> DRESS_REHEARSAL -> PROD.
- Required artifacts before PROD: signed architecture, rollback, and reconciliation playbook.

## 2. Prerequisites

Source Oracle:
- ARCHIVELOG enabled
- Supplemental logging enabled for in-scope objects
- Stable backup and restore validation completed
- DDL freeze policy accepted by application owners

Target PostgreSQL Flexible Server:
- Capacity sized for baseline load + CDC catch-up + cutover spikes
- Parameter baseline validated in non-prod
- Role model implemented (migration role, app role, read-only validation role)

Azure Components:
- Data Box order and logistics confirmed
- Storage account + container hierarchy for manifests and payloads
- Azure DMS instance deployed in network path with source and target reachability

Operator readiness:
- SQL*Plus, psql, Azure CLI, and bash installed on jump host
- Access validated for Oracle source and PostgreSQL target from same host
- Command output logging location defined for audit evidence

## 3. Phase-by-Phase Execution

## Phase 0: Discovery and Readiness

1. Inventory schemas, object counts, LOB footprint, and growth profile.
2. Classify objects by conversion complexity (simple, moderate, hard).
3. Capture top SQL workload and business criticality mapping.
4. Define reconciliation KPI catalog with business owners.

Exit criteria:
- Conversion backlog estimated and resourced
- Downtime target and rollback SLA approved

## Phase 1: Schema Conversion and Hardening

1. Extract Oracle DDL and metadata using consistent snapshot.
2. Convert to PostgreSQL-compatible DDL.
3. Review object-level gaps:
   - Datatypes (NUMBER precision, DATE/TIMESTAMP semantics)
   - Packages/procedures
   - Synonyms, DB links, editioned objects
4. Generate idempotent deployment scripts for PostgreSQL.
5. Run conversion tests and query-plan sanity checks.

Real-world issues and handling:
- Oracle empty string vs NULL behavior:
  - Implement explicit normalization in app/ETL paths.
- Implicit datatype conversions in Oracle SQL:
  - Rewrite predicates to preserve index usability in PostgreSQL.
- Sequence/identity drift:
  - Maintain sequence manifest and setval operations in cutover script.

Exit criteria:
- Critical path objects converted and validated
- Open conversion defects triaged with owners and target date

## Phase 2: Baseline Extraction and Data Box Transfer

1. Capture anchor SCN and freeze it in migration config.
2. Export in slices (partition/date/range) with deterministic naming.
3. Produce manifest:
   - table_name, chunk_id, rows, bytes, checksum, anchor_scn
4. Load files onto Data Box.
5. Verify file-level checksum before handoff.
6. Track chain-of-custody and ingestion completion in Azure.

Real-world issues and handling:
- Data skew causes very large chunks and import hotspots:
  - Re-slice oversized chunks and prioritize hot tables.
- Data Box logistics delay:
  - Keep contingency window and staged mini-network transfer for critical tables.
- Corrupt or partial files:
  - Reject chunk at validation gate, re-export from source with same anchor rules.

Exit criteria:
- 100% expected chunk manifests ingested to Azure staging
- Checksums matched at destination

## Phase 3: Baseline Load to PostgreSQL

1. Load chunks to staging schema.
2. Validate row counts and nullability profile.
3. Promote staging to final schema using controlled merge scripts.
4. Build indexes in planned order (largest first, with lock awareness).
5. Enable constraints in validation mode and resolve violations.

Real-world issues and handling:
- WAL growth pressure during high-speed load:
  - Tune batch sizes and checkpoint settings; monitor storage headroom.
- Index build contention:
  - Stagger high-cost indexes and disable non-critical concurrent jobs.
- Constraint violations from historical source inconsistencies:
  - Quarantine exceptions; resolve with business-approved remediation rules.

Exit criteria:
- Baseline fully loaded and promoted
- Validation summary signed by DBA and app data owner

## Phase 4: DMS Continuous Sync

1. Configure DMS source/target endpoints.
2. Apply table mappings and task settings.
3. Start DMS task using approved anchor and inclusion rules.
4. Monitor lag and apply throughput.
5. Resolve task errors and unsupported pattern exceptions.

Real-world issues and handling:
- LOB truncation or unsupported mode:
  - Align DMS LOB settings to object profile, retest with largest rows.
- Frequent endpoint reconnects:
  - Check network jitter, DNS, firewall timeouts.
- Apply errors due to DDL drift:
  - Enforce freeze, queue DDL changes through controlled migration path only.

Exit criteria:
- Lag stable within SLO
- No unresolved high-severity DMS task errors

Minimum monitoring cadence during this phase:
- Every 15 minutes during first 24 hours after task start
- Every hour once stability is confirmed
- Immediate escalation for repeated apply failures, not only hard task stops

## Phase 5: Dress Rehearsal Cutovers

1. Simulate freeze and production-like CDC drain.
2. Run full reconciliation suite and business KPI checks.
3. Measure timeline against downtime budget.
4. Document defects and close actions.

Exit criteria:
- At least one successful rehearsal under downtime target
- All critical defects closed or accepted with mitigation

## Phase 6: Production Cutover

1. Start command center bridge.
2. Freeze source writes and enforce read-only mode.
3. Drain DMS to near-zero lag.
4. Execute final reconciliation pack.
5. Perform go/no-go checkpoint.
6. Switch application endpoints to PostgreSQL.
7. Execute smoke tests and critical transaction tests.
8. Monitor hypercare dashboard for first 24-72 hours.

Rollback trigger examples:
- Critical business transaction failures not resolved within decision window
- Unrecoverable data integrity mismatch in critical entities
- Severe performance regression breaching agreed thresholds

Rollback execution discipline:
- Assign one rollback owner and one approver before freeze starts
- Keep rollback command/script pre-tested and immutable for production run
- Record exact rollback invocation timestamp and rationale in cutover log

## 4. Cutover Timeline Template (Example)

- T-48h: Freeze non-essential releases and schema changes
- T-24h: Final health checks, backup verification, bridge activation prep
- T-4h: DMS lag checkpoint, dry-run scripts staged
- T-60m: Application write freeze start
- T-30m: Final CDC drain and validation
- T-15m: Go/no-go board decision
- T0: Endpoint switch
- T+30m: Smoke tests complete
- T+2h: Business KPI verification
- T+24h: Hypercare checkpoint

## 5. Observability Requirements

Mandatory dashboards:
- Oracle redo generation and archive health
- DMS task state, lag, throughput, errors/retries
- PostgreSQL CPU/memory/IOPS/storage/WAL/checkpoints
- Reconciliation status by table and business domain

Mandatory alerts:
- DMS lag beyond threshold
- DMS task error bursts
- PostgreSQL storage growth anomaly
- Reconciliation critical mismatch

## 6. Evidence Pack for Audit and Sign-off

- SCN anchor record
- File manifest and checksum records
- DMS task configuration and run logs
- Reconciliation reports and exceptions with disposition
- CAB approvals and go/no-go minutes

## Author

Author: Nitish Anand Srivastava

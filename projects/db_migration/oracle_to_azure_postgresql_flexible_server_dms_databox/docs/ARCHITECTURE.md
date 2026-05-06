# Architecture: Oracle On-Prem to Azure PostgreSQL Flexible Server
## Using Azure Data Box + Azure DMS for 40+ TB Migration

## 1. Reference Topology

```text
On-Prem DC
+---------------------------------------------------------------+
| Oracle Primary + Standby                                      |
|  - ARCHIVELOG enabled                                         |
|  - Supplemental logging enabled                               |
|  - Export hosts (parallel workers)                            |
+---------------------+-----------------------------------------+
                      |
                      | Baseline export files (partitioned)
                      v
               Azure Data Box Device
                      |
                      | Physical shipment
                      v
Azure
+---------------------------------------------------------------+
| Storage Account (staging container)                           |
|  - Raw baseline files                                         |
|  - Manifests/checksums                                        |
+---------------------+-----------------------------------------+
                      |
                      | Controlled bulk load
                      v
+---------------------------------------------------------------+
| Azure Database for PostgreSQL Flexible Server                 |
|  - Staging schema                                             |
|  - Final schema                                               |
|  - Validation schema                                          |
+---------------------+-----------------------------------------+
                      ^
                      |
                      | Continuous replication (CDC)
+---------------------+-----------------------------------------+
| Azure Database Migration Service (DMS)                        |
|  - Source: Oracle                                             |
|  - Target: PostgreSQL Flexible Server                         |
|  - Table mappings and task tuning                             |
+---------------------------------------------------------------+
```

## 2. Design Principles

- Baseline and CDC are decoupled but strictly checkpointed.
- Every phase has entry/exit criteria and rollback point.
- Business reconciliation is equal in importance to technical reconciliation.
- Schema conversion is treated as an engineering program, not a one-time tool output.
- DDL governance is enforced to avoid CDC inconsistency.

## 3. Data Flow by Stage

### Stage A: Baseline Export and Data Box Load

1. Capture migration anchor SCN and metadata snapshot.
2. Export selected Oracle tables using partition-aware extracts.
3. Generate file manifest with row counts and checksums.
4. Copy export bundles to Data Box.
5. Receive ingestion completion in Azure Storage.

Controls:
- File integrity checks at source and destination.
- Reproducible export scripts with retry semantics.
- Explicit exclusion list for transient/audit tables.

### Stage B: Baseline Import to PostgreSQL

1. Load baseline files to PostgreSQL staging.
2. Validate row counts and data profiles.
3. Promote from staging to final schema by deterministic scripts.
4. Build secondary indexes and constraints in controlled order.

Controls:
- Deferred FK creation for load throughput.
- Lock-sensitive operations scheduled in low-risk windows.
- Sequence tracking table for post-load reseeding.

### Stage C: DMS Continuous Sync

1. DMS task starts from agreed SCN boundary.
2. Ongoing source changes are replicated to target.
3. Lag, errors, retries, and conflict classes are monitored.
4. Weekly burn-down resolves conversion and data anomalies.

Controls:
- DDL freeze policy for in-scope objects.
- Explicit mappings for unsupported objects.
- Alerting thresholds for lag, apply failures, and reconnect storms.

### Stage D: Cutover

1. Announce freeze and stop writes on source.
2. Allow DMS to drain to zero-lag checkpoint.
3. Execute final reconciliation suite.
4. Switch application connection and secrets.
5. Run smoke tests and business validation.

Controls:
- Go/no-go gate led by CAB and command center.
- Time-boxed rollback decision checkpoint.
- Immutable evidence pack captured in logs and reports.

## 4. Non-Functional Architecture Requirements

Performance:
- Target sizing with headroom for catch-up spikes (not steady-state only).
- Load and CDC concurrency tuned to avoid checkpoint I/O saturation.

Reliability:
- Multi-AZ deployment for PostgreSQL Flexible Server where RTO/RPO requires.
- DMS task restart procedures validated before production run.

Security:
- Private endpoint/VNet integration for database services.
- TLS enforced in flight, encryption at rest, key management controls.
- Least-privilege roles for migration workers.

Compliance:
- Audit trail for schema/object changes during program window.
- PII masking for test/dress rehearsal datasets.
- Chain-of-custody records for Data Box handling.

## 5. Object Conversion Strategy

Priority 1 (must be native on cutover):
- Tables, PK/FK, indexes, sequences, views used by online paths

Priority 2 (can be remediated during dress rehearsal):
- Stored procedures/packages rewritten to PL/pgSQL or service layer logic
- Materialized views and scheduler jobs

Priority 3 (decommission or redesign):
- Oracle-specific features without direct equivalents
- DB links and tightly coupled proprietary constructs

## 6. Operational Command Model

Roles:
- Migration Lead: schedule, gates, ownership
- Oracle DBA Lead: source stability, SCN governance, logging
- PostgreSQL DBA Lead: target performance, constraints/indexes, recovery
- DMS Engineer: task tuning, lag/error handling
- App Lead: freeze execution, smoke and business UAT
- SRE/Observability: dashboards, alert triage, incident timeline

## 7. High-Risk Failure Modes and Mitigations

- Baseline export does not align to CDC anchor:
  - Mitigation: SCN capture signed-off before first export job and recorded in config.
- Charset mismatch causes invisible corruption:
  - Mitigation: pre-migration charset profiling and canonical conversion tests.
- DMS lag never converges under peak traffic:
  - Mitigation: throttle source write bursts, tune task settings, increase target capacity.
- Reconciliation passes technically but fails business outcomes:
  - Mitigation: mandatory KPI comparison suite at each cutover rehearsal.

## Author

Author: Nitish Anand Srivastava

# Cross-Engine Database Migration Reconciliation Framework

## Purpose

This project provides a detailed, production-oriented reconciliation framework for validating data consistency during and after database migrations across:
- Oracle
- SQL Server
- MySQL
- PostgreSQL

It includes:
- Reconciliation strategy documentation and edge-case handling
- Gap detection SQL for each engine
- Gap remediation SQL patterns for each engine
- Python orchestration for cross-source/target comparisons and fix-plan generation
- Shell execution wrappers for repeatable runbook execution

This project is designed as the critical control layer for migration go/no-go decisions.

---

## Why This Framework Exists

Data migration failures are rarely caused by one obvious mismatch. Most production failures come from a combination of:
- Row count drift due to late writes
- Inconsistent update/delete replay order
- Missing constraints or disabled triggers
- Collation/timezone normalization differences
- Partial retries that duplicate or skip rows
- Snapshot misalignment between source and target

This framework addresses all of the above with multiple reconciliation lenses, not a single check.

---

## Reconciliation Coverage Matrix

| Category | Covered | During Migration | Post Migration |
|---|---|---|---|
| Total row count | Yes | Yes | Yes |
| Partition/key-range count | Yes | Yes | Yes |
| Count by business state | Yes | Yes | Yes |
| Hash sum (row-signature aggregate) | Yes | Yes | Yes |
| Object count (tables/views/indexes) | Yes | Optional | Yes |
| Constraint count and status | Yes | Optional | Yes |
| PK uniqueness check | Yes | Yes | Yes |
| FK orphan check | Yes | Optional | Yes |
| Update count parity (windowed) | Yes | Yes | Yes |
| Delete count parity (hard/soft) | Yes | Yes | Yes |
| CDC/checkpoint lag sanity | Yes | Yes | Optional |
| Data type/encoding anomaly checks | Yes | Optional | Yes |

---

## Reconciliation Strategies

## 1. Count(*) Strategy

Use when:
- You need a fast first-pass parity check
- You need broad coverage across all migrated tables

Strength:
- Very fast and easy to automate

Limitation:
- Can miss value-level corruption if row counts still match

Implementation in this framework:
- Global row counts per table
- Key-range row counts to localize drift quickly
- Optional state-based counts (for example by status or date)

---

## 2. Hash and Sum-of-Hash Strategy

Use when:
- You need value-level confidence without extracting full datasets
- You want deterministic comparison of row signatures

Strength:
- Detects value mismatches even when count matches

Limitation:
- Requires careful normalization across engines (nulls, precision, timezone, collation)

Implementation in this framework:
- Canonical row signature generation
- Aggregate hash (sum/checksum over row signatures)
- Segment hash by key range for targeted triage

---

## 3. Object and Constraint Parity Strategy

Use when:
- Schema correctness must be validated before go-live

Checks included:
- Object count parity (tables/indexes/views/triggers)
- Constraint count and status (PK, FK, unique, check)
- Disabled/invalid constraints

---

## 4. Update/Delete Reconciliation Strategy

This is mandatory for online migrations and CDC-driven cutovers.

Checks included:
- Update volume parity in control windows
- Delete volume parity (hard delete and soft delete patterns)
- Replay ordering sanity (late-arriving updates/deletes)
- CDC checkpoint gap analysis (position, SCN, LSN, binlog)

Note:
- If source does not expose operation metadata directly, this framework supports fallback checks using audit columns (updated_at, deleted_flag, deleted_at).

---

## 5. Business Invariant Strategy

Technical parity can pass while business logic still breaks.

Checks included:
- Balance invariants (debit-credit style controls)
- Referential business integrity beyond FK (for example account lifecycle rules)
- Time-window aggregates and top-N comparisons

---

## During Migration Reconciliation Model

Run cadence:
- Every 15 to 60 minutes for high churn systems
- Hourly for medium churn systems

Recommended sequence:
1. CDC lag and checkpoint sanity
2. Count parity on hot tables
3. Update/delete parity for current window
4. Segment-hash parity on critical tables
5. Escalate to targeted row diff when mismatch appears

Outcome:
- Early drift detection before cutover day

---

## Post Migration Reconciliation Model

Run windows:
- T+0 immediately after cutover
- T+1h, T+6h, T+24h, T+72h during hypercare

Recommended sequence:
1. Full object and constraint parity
2. Full table count parity
3. Full hash parity on critical tables
4. Business invariant suite
5. Performance baseline + plan regression checks

Outcome:
- Evidence-based sign-off and rollback confidence

---

## Gap Detection and Fix Workflow

## Step 1: Classify the gap

Gap classes:
- CLASS-A: Count mismatch only
- CLASS-B: Count match but hash mismatch
- CLASS-C: Update/delete mismatch
- CLASS-D: Constraint/object mismatch
- CLASS-E: Encoding/precision normalization mismatch

## Step 2: Localize the gap

Techniques:
- Key-range partitioning
- Time-window partitioning
- Operation-type partitioning (insert/update/delete)

## Step 3: Apply targeted remediation

Primary remediation patterns:
- Re-extract and replay missing key-ranges
- Re-run CDC from safe checkpoint window
- Delete-and-reload affected key-ranges in target
- Rebuild missing constraints and revalidate
- Normalize data representation and rerun hash checks

## Step 4: Reconcile again

A fix is complete only when:
- Gap class resolves
- No collateral mismatches introduced
- Regression check passes on adjacent key ranges

---

## Edge Cases Covered

1. Snapshot skew between source and target baselines
2. Timezone conversion drift (TIMESTAMP vs DATETIME semantics)
3. Floating-point precision drift
4. String collation/case-folding differences
5. Soft delete vs hard delete semantic mismatch
6. Out-of-order CDC apply during retries
7. Duplicate replay due to non-idempotent apply logic
8. Missing late updates after checkpoint jump
9. Sequence/identity divergence after backfill
10. Constraint disabled during load and never re-enabled

---

## Repository Structure

```text
cross_engine_reconciliation_framework/
  README.md
  docs/
    RECONCILIATION_STRATEGIES.md
    GAP_REMEDIATION_PLAYBOOK.md
  config/
    reconciliation_config.yaml
  scripts/
    common/
      reconciliation_runner.py
      reconciliation_runner.sh
      gap_classifier.py
    oracle/
      reconciliation.sql
      gap_fix.sql
      run_reconciliation.py
      run_reconciliation.sh
    sqlserver/
      reconciliation.sql
      gap_fix.sql
      run_reconciliation.py
      run_reconciliation.sh
    mysql/
      reconciliation.sql
      gap_fix.sql
      run_reconciliation.py
      run_reconciliation.sh
    postgresql/
      reconciliation.sql
      gap_fix.sql
      run_reconciliation.py
      run_reconciliation.sh
  reports/
```

---

## How to Run

## 1. Configure

Edit:
- config/reconciliation_config.yaml

Define:
- Source and target connection details
- Table scope
- Key columns and optional audit columns
- Reconciliation thresholds

## 2. Run engine-specific SQL collection

Use engine wrappers in scripts/<engine>/run_reconciliation.sh.

## 3. Compare and classify

Use Python runner:
- scripts/common/reconciliation_runner.py

Engine-specific Python runners are also available:
- scripts/oracle/run_reconciliation.py
- scripts/sqlserver/run_reconciliation.py
- scripts/mysql/run_reconciliation.py
- scripts/postgresql/run_reconciliation.py

## 4. Generate remediation plan

If mismatch exists, run:
- scripts/common/gap_classifier.py

Then apply appropriate engine gap_fix.sql patterns.

Recommended remediation order:
1. Materialize scoped mismatch keys into recon_gap_keys.
2. Execute scripts/<engine>/gap_fix.sql for the impacted table scope.
3. Re-run reconciliation for impacted tables.
4. Re-run adjacent key-range checks to prevent collateral drift.

## 5. Re-run reconciliation

Do not close incident until post-fix validation passes.

---

## Recommended Thresholds

- Count parity: 100%
- Hash parity: 100% on critical tables, >= 99.99% on low-risk tables with approved exceptions
- Update/delete parity window: 100% for cutover-bound windows
- Constraint parity: 100% enabled and validated

---

## Security and Compliance Controls

- No plaintext secrets in scripts
- TLS required for all DB connections
- Reconciliation artifacts timestamped and immutable
- Fix actions logged with ticket/change reference

---

## Production Sign-Off Checklist

- All critical tables pass count + hash checks
- Update/delete parity validated for final pre-cutover window
- All required constraints enabled and trusted
- Business invariant suite passes
- Gap report is empty or approved exceptions documented
- Rollback path remains available for hypercare window

---

## Notes

- SQL files use portable templates and require schema/table parameterization.
- Operation-level checks assume availability of CDC/change-tracking/audit metadata; fallback models are provided.

Last Updated: 2026-05-01
Owner: Database Reliability Engineering

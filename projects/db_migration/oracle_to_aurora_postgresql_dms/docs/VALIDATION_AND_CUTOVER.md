# Validation and Cutover
## Oracle to Amazon Aurora PostgreSQL via AWS DMS

## Validation Principles

Cutover must be based on layered evidence, not a single successful DMS task status.

Required validation layers:
- structural validation
- quantitative row-count validation
- deterministic checksum validation
- business KPI validation
- operational validation of CDC lag and task health

## Reconciliation Checklist

Before cutover:
- all critical tables loaded and included in DMS task
- no unresolved PK duplication on target
- no unresolved NOT NULL drift on critical columns
- checksum parity confirmed on agreed windows
- sequence reseed plan prepared
- business report parity signed off
- source and target CDC latency within agreed threshold for at least one stable monitoring window

Suggested default thresholds for broad internal use:
- critical row-count mismatch: 0
- non-critical row-count mismatch: less than or equal to 0.01%
- critical checksum mismatch: 0
- CDC latency at freeze decision point: 0 seconds preferred, explicitly approved if non-zero

## Severity Classification

- Class A: financial, compliance, or security mismatch
- Class B: core business workflow mismatch
- Class C: non-critical reporting difference
- Class D: metadata or cosmetic issue

Class A and B issues block cutover.

## Final Cutover Sequence

1. Freeze application writes to Oracle.
2. Confirm no bypass channels remain writable.
3. Wait for AWS DMS CDC latency to drain.
4. Run final reconciliation queries.
5. Run sequence reseed script.
6. Switch applications to Aurora.
7. Run smoke tests.
8. Monitor critical KPIs during rollback window.

## Typical Late-Stage Issues

- hidden batch job still writing to Oracle after freeze
- sequence values lower than target max keys
- DMS task still retrying specific tables despite overall running state
- time-zone or rounding differences changing report results

## Smoke Test Expectations

At minimum, validate after cutover:
- application login and connection initialization
- one create transaction
- one update transaction
- one read/reporting workflow
- one batch or scheduled process if the workload depends on it

## Evidence Pack

- DMS task status export
- reconciliation reports
- sequence reseed output
- smoke test evidence
- go/no-go decision log
- endpoint connectivity test evidence

## Author

Author: Nitish Anand Srivastava

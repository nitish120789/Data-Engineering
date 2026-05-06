# Troubleshooting Guide
## Oracle to Azure PostgreSQL Flexible Server (Data Box + DMS)

## 1. Data Box and Baseline Load Issues

Issue: Missing chunks after Azure ingestion
- Symptoms: Manifest count mismatch, missing table partitions
- Checks:
  - Compare source manifest vs Azure staging manifest
  - Validate checksum files and byte counts
- Actions:
  - Re-export only missing chunk IDs
  - Preserve same naming/version scheme to avoid duplicate loads

Issue: Baseline load too slow
- Symptoms: Throughput much lower than expected
- Checks:
  - Target CPU/IO saturation
  - Lock waits and autovacuum pressure
- Actions:
  - Increase parallelism gradually
  - Disable non-essential indexes during ingest
  - Tune checkpoint and batch sizing

## 2. DMS Replication Issues

Issue: DMS lag keeps increasing
- Checks:
  - Source redo/transaction volume spikes
  - Target resource saturation
  - Error retries in DMS task logs
- Actions:
  - Increase target compute/storage throughput
  - Tune DMS task batch and commit settings
  - Isolate highest-churn tables for focused remediation

Issue: Task failures on unsupported object behavior
- Checks:
  - DMS diagnostics and table-level error details
- Actions:
  - Implement custom transform/staging route for impacted objects
  - Exclude non-essential objects with governance approval

Issue: LOB replication failures
- Checks:
  - LOB mode configuration
  - Maximum row size and truncation indicators
- Actions:
  - Adjust full-lob/chunk settings and retest on largest sample rows

## 3. Cutover and Validation Issues

Issue: Row counts match but business KPI differs
- Checks:
  - Time zone and calendar logic in transformed queries
  - Null/default handling changes
- Actions:
  - Compare canonical KPI SQL side-by-side
  - Patch semantic differences before go-live

Issue: Post-cutover duplicate key errors
- Checks:
  - Sequence current values vs max table key
- Actions:
  - Reseed sequence values and rerun write-path smoke tests

Issue: Application latency regression
- Checks:
  - Query plans on top endpoints
  - Missing or suboptimal indexes
- Actions:
  - Add/tune indexes
  - Refresh stats and tune connection pooling

## 4. Escalation Guidance

Escalate immediately when:
- Class A reconciliation mismatch appears
- DMS task enters repeated fail/restart loop
- Source cannot guarantee write freeze correctness
- Rollback decision point is approaching without resolution

## Author

Author: Nitish Anand Srivastava

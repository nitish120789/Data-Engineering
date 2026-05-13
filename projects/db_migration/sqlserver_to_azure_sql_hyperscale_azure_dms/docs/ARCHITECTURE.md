# Architecture: SQL Server to Azure SQL Hyperscale with Azure DMS

## Pattern

This project uses a managed migration pattern:

1. Baseline load into Azure SQL Hyperscale
2. Azure DMS online replication for ongoing changes
3. Reconciliation gates with deterministic snapshot comparisons
4. Controlled freeze, delta drain, and app cutover

## Logical Flow

Phase 1: Baseline
- Source SQL Server backup/export
- Restore/load to Azure SQL Hyperscale target

Phase 2: DMS Delta Sync
- Azure DMS reads source transaction changes
- Azure DMS applies changes to target continuously
- DMS lag monitored to keep within SLO

Phase 3: Validation and Cutover
- Capture source reconciliation snapshot (run_id)
- Capture target reconciliation snapshot (same run_id)
- Compare row profile, bucket hashes, and business aggregates
- Freeze writes and drain lag to near-zero
- Final validation and switch application traffic

## Why Bucketed Hashing for Large Tables

Full-table deterministic hashes are expensive and can fail at scale due to memory and sorting pressure. This project instead computes per-bucket hashes:

- Bucket id = ABS(CHECKSUM(pk)) % bucket_modulus
- Per bucket validation includes:
  - row count
  - checksum_agg(binary_checksum(...))
  - pk min and pk max

This approach gives high confidence while scaling to large tables with predictable compute.

## Reliability Controls

- Shared run_id used across source and target snapshots
- Dedicated recon schema to keep audit artifacts
- Critical/non-critical severity model
- Comparison queries return explicit PASS/FAIL indicators

## Security Controls

- SQL authentication secrets should be sourced from Key Vault, not stored in scripts
- DMS service uses minimum required privileges
- Network path should use private endpoints where possible
- Reconciliation outputs should be retained in controlled logs storage

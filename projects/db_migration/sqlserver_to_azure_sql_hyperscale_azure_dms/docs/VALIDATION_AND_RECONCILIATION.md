# Validation and Reconciliation Guide

## Objectives

The reconciliation pack validates both technical parity and business parity:

- Technical parity:
  - row counts
  - null/duplicate key issues
  - large-table bucketed hashing
- Business parity:
  - SUM, MIN, MAX, COUNT on key measures
  - optional filtered aggregates for open or recent transactions

## Snapshot Model

The script scripts/exhaustive_reconciliation_and_hashing.sql writes snapshots to recon schema tables:

- recon.row_profile
- recon.bucket_hash
- recon.business_profile

Use the same run_id for source and target snapshots.

## Hash Strategy for Large Tables

For each scoped table:

- bucket_id = ABS(CHECKSUM(pk)) % bucket_modulus
- per bucket capture:
  - row_count
  - bucket_checksum (CHECKSUM_AGG over row fingerprint)
  - min_pk / max_pk

If row_count matches but bucket_checksum differs, inspect conversion, truncation, collation, or rounding issues.

## Comparison Outputs

The target-side compare section returns:

1. Row profile mismatches by table
2. Bucket hash mismatches by table and bucket
3. Business aggregate mismatches by rule name

## Threshold Recommendations

- Critical tables: no mismatch accepted
- Non-critical tables: optional small tolerance if formally approved
- Financial aggregates: 0 tolerance unless explicitly signed off

## Large Table Guidance

- Start with bucket_modulus = 1024 for very large tables
- Increase to 2048/4096 for tighter localization of mismatch buckets
- Keep hash scope to deterministic stable columns only

## Business Validation Rules

Edit config/business_validation_rules.yaml and mirror those rules in scripts/business_validation.sql.

Required aggregate types in this project:
- SUM
- MIN
- MAX
- COUNT

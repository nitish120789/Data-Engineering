# Troubleshooting

## DMS Lag Not Decreasing

Checks:
1. Confirm source transaction rate is not exceeding target apply capacity.
2. Review DMS task status and warnings.
3. Check target blocking and long transactions.
4. Validate network throughput and packet loss.

Actions:
- Scale target compute temporarily.
- Reduce concurrent write pressure if possible.
- Tune table mappings or task settings for parallelism.

## Bucket Hash Mismatch but Row Count Match

Likely causes:
- Data type coercion differences
- Collation/case normalization differences
- Date/time precision differences
- Decimal scale rounding

Actions:
1. Recompute hash on narrowed PK range in mismatched bucket.
2. Compare canonical string rendering for suspect columns.
3. Validate ETL/conversion functions and defaults.

## Business Aggregate Mismatch

Checks:
1. Verify source/target filters are identical.
2. Confirm timezone normalization in date predicates.
3. Validate exclusion of soft-deleted or archival rows.

Actions:
- Re-run business_validation.sql with fixed snapshot window.
- Add diagnostic per-dimension breakdown (for example by day/region).

## Linked Server Compare Fails

Checks:
1. Linked server exists and login mapping is valid.
2. RPC OUT and data access are enabled.
3. Source recon schema objects are present.

Actions:
- Run source and target snapshots independently and export to CSV.
- Compare offline using scripts/run_reconciliation.ps1.

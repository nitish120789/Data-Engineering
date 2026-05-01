# Reconciliation Strategies and Decision Guide

## Strategy Selection by Migration Stage

| Stage | Mandatory Checks | Optional High-Value Checks |
|---|---|---|
| Initial seed | count, object, constraint | segment hash, PK uniqueness |
| Continuous CDC | count on hot tables, update/delete parity, checkpoint sanity | rolling segment hash |
| Pre-cutover | full count, full hash (critical), constraint status, business invariants | full row-diff on high risk tables |
| Post-cutover | count/hash/business invariants at T+0/T+24/T+72 | trend drift monitoring |

## Why Count + Hash + Ops All Matter

- Count detects missing or duplicate rows.
- Hash detects changed values when counts still match.
- Update/delete parity detects replay-order and operation-loss issues.

Relying on only one of these is a high-risk anti-pattern.

## Hash Normalization Rules

Before hashing, normalize:
1. Nulls -> explicit token
2. Timestamp -> UTC canonical string
3. Numeric -> fixed precision string
4. Text -> trim/normalize collation where agreed

If rules are inconsistent between source and target, false positives will occur.

## Segmentation Tactics

Use segmentation to localize gaps quickly:
- By key ranges (id buckets)
- By time windows (updated_at)
- By partition keys
- By operation type

## Gap Severity Model

- Sev-1: critical table mismatch pre-cutover
- Sev-2: non-critical mismatch or drift with workaround
- Sev-3: known approved exception

## Approved Exception Handling

Any exception must include:
- explicit table/key scope
- reason and business impact
- remediation owner and date
- expiry date for exception

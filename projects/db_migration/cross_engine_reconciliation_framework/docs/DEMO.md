# Demo Walkthrough

## Purpose

This demo runs the reconciliation comparator and gap classifier without connecting to any database.

It uses realistic mock source and target summaries to show:
- Count mismatch detection
- Hash mismatch detection
- Update/delete drift detection
- Gap classification and recommended remediation guidance

## Files Used

- samples/mock_outputs/source_summary.csv
- samples/mock_outputs/target_summary.csv
- scripts/common/reconciliation_runner.py
- scripts/common/gap_classifier.py
- scripts/common/run_demo.sh

## How to Run

From the project root:

```bash
bash scripts/common/run_demo.sh
```

## Expected Outcome

The sample data intentionally contains three kinds of drift:
1. `orders`
Count mismatch + hash mismatch + update/delete mismatch
Expected class: `CLASS-A`
Expected action: re-extract and replay affected key ranges, then revalidate hash

2. `payments`
Count matches but hash mismatch and update mismatch
Expected class: `CLASS-B`
Expected action: row-level diff and targeted patching

3. `shipments`
Count mismatch and delete mismatch
Expected class: `CLASS-A`
Expected action: reconcile missing/extra keys and re-check deletes

## Output Artifacts

Generated under samples/demo_reports:
- reconciliation_report.json
- reconciliation_report.csv
- reconciliation_classified.csv

## How to Extend the Demo

1. Add more rows to the mock source and target CSV summaries.
2. Simulate object/constraint drift by adding companion metadata CSVs if you want to extend the comparator.
3. Add a post-fix target summary and rerun the demo to prove remediation closure.

## Recommended Next Step

After validating the demo flow, connect real engine SQL output into the same CSV schema and run the common comparator/classifier in your migration pipeline.

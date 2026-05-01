#!/usr/bin/env bash
# Wrapper to execute reconciliation compare and classification.
# Author: Nitish Anand Srivastava

set -euo pipefail

SRC_SUMMARY="${SRC_SUMMARY:-reports/source_summary.csv}"
TGT_SUMMARY="${TGT_SUMMARY:-reports/target_summary.csv}"
OUT_JSON="${OUT_JSON:-reports/reconciliation_report.json}"
OUT_CSV="${OUT_CSV:-reports/reconciliation_report.csv}"
OUT_CLASSIFIED="${OUT_CLASSIFIED:-reports/reconciliation_classified.csv}"

python scripts/common/reconciliation_runner.py \
  --source-summary "$SRC_SUMMARY" \
  --target-summary "$TGT_SUMMARY" \
  --out-json "$OUT_JSON" \
  --out-csv "$OUT_CSV"

python scripts/common/gap_classifier.py \
  --input-csv "$OUT_CSV" \
  --output-csv "$OUT_CLASSIFIED"

echo "Reconciliation artifacts generated:" \
  "$OUT_JSON" "$OUT_CSV" "$OUT_CLASSIFIED"

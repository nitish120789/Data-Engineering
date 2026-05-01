#!/usr/bin/env bash
# End-to-end demo runner for the reconciliation framework.
# Author: Nitish Anand Srivastava

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_SUMMARY="${SRC_SUMMARY:-$BASE_DIR/samples/mock_outputs/source_summary.csv}"
TGT_SUMMARY="${TGT_SUMMARY:-$BASE_DIR/samples/mock_outputs/target_summary.csv}"
OUT_JSON="${OUT_JSON:-$BASE_DIR/samples/demo_reports/reconciliation_report.json}"
OUT_CSV="${OUT_CSV:-$BASE_DIR/samples/demo_reports/reconciliation_report.csv}"
OUT_CLASSIFIED="${OUT_CLASSIFIED:-$BASE_DIR/samples/demo_reports/reconciliation_classified.csv}"

mkdir -p "$BASE_DIR/samples/demo_reports"

python "$BASE_DIR/scripts/common/reconciliation_runner.py" \
  --source-summary "$SRC_SUMMARY" \
  --target-summary "$TGT_SUMMARY" \
  --out-json "$OUT_JSON" \
  --out-csv "$OUT_CSV"

python "$BASE_DIR/scripts/common/gap_classifier.py" \
  --input-csv "$OUT_CSV" \
  --output-csv "$OUT_CLASSIFIED"

echo "Demo completed. Review:"
echo "  JSON report      : $OUT_JSON"
echo "  CSV report       : $OUT_CSV"
echo "  Classified report: $OUT_CLASSIFIED"

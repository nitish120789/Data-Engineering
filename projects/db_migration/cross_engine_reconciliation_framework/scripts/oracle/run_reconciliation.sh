#!/usr/bin/env bash
# Oracle reconciliation executor
# Author: Nitish Anand Srivastava

set -euo pipefail

ORACLE_CONN="${ORACLE_CONN:?Set ORACLE_CONN like user/pass@host:port/service}"
SCHEMA_NAME="${SCHEMA_NAME:-APP}"
TABLE_NAME="${TABLE_NAME:-ORDERS}"
PK_COL="${PK_COL:-ID}"
UPDATED_COL="${UPDATED_COL:-UPDATED_AT}"
DELETED_FLAG_COL="${DELETED_FLAG_COL:-IS_DELETED}"
WINDOW_START="${WINDOW_START:-2026-05-01 00:00:00}"
WINDOW_END="${WINDOW_END:-2026-05-01 01:00:00}"
OUT_FILE="${OUT_FILE:-reports/oracle_${SCHEMA_NAME}_${TABLE_NAME}_summary.out}"

mkdir -p reports
sqlplus -s "$ORACLE_CONN" @scripts/oracle/reconciliation.sql \
  "$SCHEMA_NAME" "$TABLE_NAME" "$PK_COL" "$UPDATED_COL" "$DELETED_FLAG_COL" "$WINDOW_START" "$WINDOW_END" \
  > "$OUT_FILE"

echo "Oracle reconciliation output: $OUT_FILE"

#!/usr/bin/env bash
# PostgreSQL reconciliation executor
# Author: Nitish Anand Srivastava

set -euo pipefail

PG_DSN="${PG_DSN:?Set PG_DSN}"
SCHEMA_NAME="${SCHEMA_NAME:-public}"
TABLE_NAME="${TABLE_NAME:-orders}"
PK_COL="${PK_COL:-id}"
UPDATED_COL="${UPDATED_COL:-updated_at}"
DELETED_FLAG_COL="${DELETED_FLAG_COL:-is_deleted}"
WINDOW_START="${WINDOW_START:-2026-05-01 00:00:00}"
WINDOW_END="${WINDOW_END:-2026-05-01 01:00:00}"
OUT_FILE="${OUT_FILE:-reports/postgresql_${SCHEMA_NAME}_${TABLE_NAME}_summary.out}"

mkdir -p reports
psql "$PG_DSN" \
  -v schema_name="$SCHEMA_NAME" \
  -v table_name="$TABLE_NAME" \
  -v pk_col="$PK_COL" \
  -v updated_col="$UPDATED_COL" \
  -v deleted_flag_col="$DELETED_FLAG_COL" \
  -v window_start="$WINDOW_START" \
  -v window_end="$WINDOW_END" \
  -f scripts/postgresql/reconciliation.sql > "$OUT_FILE"

echo "PostgreSQL reconciliation output: $OUT_FILE"

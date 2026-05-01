#!/usr/bin/env bash
# MySQL reconciliation executor
# Author: Nitish Anand Srivastava

set -euo pipefail

MYSQL_CONN="${MYSQL_CONN:?Set MYSQL_CONN like mysql -h host -P 3306 -u user -p*** db}"
SCHEMA_NAME="${SCHEMA_NAME:-salesdb}"
TABLE_NAME="${TABLE_NAME:-orders}"
PK_COL="${PK_COL:-id}"
UPDATED_COL="${UPDATED_COL:-updated_at}"
DELETED_FLAG_COL="${DELETED_FLAG_COL:-is_deleted}"
WINDOW_START="${WINDOW_START:-2026-05-01 00:00:00}"
WINDOW_END="${WINDOW_END:-2026-05-01 01:00:00}"
OUT_FILE="${OUT_FILE:-reports/mysql_${SCHEMA_NAME}_${TABLE_NAME}_summary.out}"

mkdir -p reports
{
  echo "SET @schema_name='${SCHEMA_NAME}';"
  echo "SET @table_name='${TABLE_NAME}';"
  echo "SET @pk_col='${PK_COL}';"
  echo "SET @updated_col='${UPDATED_COL}';"
  echo "SET @deleted_flag_col='${DELETED_FLAG_COL}';"
  echo "SET @window_start='${WINDOW_START}';"
  echo "SET @window_end='${WINDOW_END}';"
  cat scripts/mysql/reconciliation.sql
} | eval "$MYSQL_CONN" > "$OUT_FILE"

echo "MySQL reconciliation output: $OUT_FILE"

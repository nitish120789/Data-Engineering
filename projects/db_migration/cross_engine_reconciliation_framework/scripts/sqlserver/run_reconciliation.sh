#!/usr/bin/env bash
# SQL Server reconciliation executor
# Author: Nitish Anand Srivastava

set -euo pipefail

SQLSERVER_HOST="${SQLSERVER_HOST:?Set SQLSERVER_HOST}"
SQLSERVER_DB="${SQLSERVER_DB:?Set SQLSERVER_DB}"
SCHEMA_NAME="${SCHEMA_NAME:-dbo}"
TABLE_NAME="${TABLE_NAME:-orders}"
PK_COL="${PK_COL:-id}"
UPDATED_COL="${UPDATED_COL:-updated_at}"
DELETED_FLAG_COL="${DELETED_FLAG_COL:-is_deleted}"
WINDOW_START="${WINDOW_START:-2026-05-01T00:00:00}"
WINDOW_END="${WINDOW_END:-2026-05-01T01:00:00}"
OUT_FILE="${OUT_FILE:-reports/sqlserver_${SCHEMA_NAME}_${TABLE_NAME}_summary.out}"

mkdir -p reports
sqlcmd -S "$SQLSERVER_HOST" -d "$SQLSERVER_DB" -E \
  -v SCHEMA_NAME="$SCHEMA_NAME" TABLE_NAME="$TABLE_NAME" PK_COL="$PK_COL" UPDATED_COL="$UPDATED_COL" DELETED_FLAG_COL="$DELETED_FLAG_COL" WINDOW_START="$WINDOW_START" WINDOW_END="$WINDOW_END" \
  -i scripts/sqlserver/reconciliation.sql > "$OUT_FILE"

echo "SQL Server reconciliation output: $OUT_FILE"

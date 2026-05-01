-- PostgreSQL reconciliation template
-- Author: Nitish Anand Srivastava
-- Usage example:
-- psql "$PG_DSN" -v schema_name=public -v table_name=orders -v pk_col=id -v updated_col=updated_at -v deleted_flag_col=is_deleted -v window_start='2026-05-01 00:00:00' -v window_end='2026-05-01 01:00:00' -f scripts/postgresql/reconciliation.sql

\set ON_ERROR_STOP on

WITH object_counts AS (
  SELECT
    :'schema_name'::text AS schema_name,
    COUNT(*) FILTER (WHERE c.relkind='r') AS table_count,
    COUNT(*) FILTER (WHERE c.relkind='v') AS view_count,
    (SELECT COUNT(*) FROM pg_indexes pi WHERE pi.schemaname = :'schema_name') AS index_count,
    (SELECT COUNT(*) FROM pg_trigger t JOIN pg_class cc ON cc.oid=t.tgrelid JOIN pg_namespace n ON n.oid=cc.relnamespace WHERE n.nspname=:'schema_name' AND NOT t.tgisinternal) AS trigger_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname = :'schema_name'
)
SELECT * FROM object_counts;

WITH constraint_counts AS (
  SELECT
    :'schema_name'::text AS schema_name,
    COUNT(*) FILTER (WHERE contype='p') AS pk_count,
    COUNT(*) FILTER (WHERE contype='f') AS fk_count,
    COUNT(*) FILTER (WHERE contype='u') AS uk_count,
    COUNT(*) FILTER (WHERE contype='c') AS check_count
  FROM pg_constraint con
  JOIN pg_namespace n ON n.oid=con.connamespace
  WHERE n.nspname = :'schema_name'
)
SELECT * FROM constraint_counts;

DO $$
DECLARE
  q text;
BEGIN
  q := format($f$
    SELECT
      %L AS schema_name,
      %L AS table_name,
      COUNT(*) AS row_count,
      SUM((('x' || substr(md5(COALESCE(%I::text,'~') || '|' || COALESCE(%I::text,'~') || '|' || COALESCE(%I::text,'~')),1,16))::bit(64)::bigint)) AS hash_sum,
      SUM(CASE WHEN %I >= %L::timestamp AND %I < %L::timestamp THEN 1 ELSE 0 END) AS updated_count,
      SUM(CASE WHEN COALESCE(%I::text,'0') IN ('1','Y','true','t') THEN 1 ELSE 0 END) AS deleted_count,
      clock_timestamp() AS run_ts
    FROM %I.%I
  $f$,
    :'schema_name', :'table_name',
    :'pk_col', :'updated_col', :'deleted_flag_col',
    :'updated_col', :'window_start', :'updated_col', :'window_end',
    :'deleted_flag_col',
    :'schema_name', :'table_name'
  );
  EXECUTE q;
END $$;

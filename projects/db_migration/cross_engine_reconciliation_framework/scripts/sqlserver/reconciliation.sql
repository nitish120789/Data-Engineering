-- SQL Server reconciliation template
-- Author: Nitish Anand Srivastava
-- Usage:
-- sqlcmd -S server -d db -E -v SCHEMA_NAME="dbo" TABLE_NAME="orders" PK_COL="id" UPDATED_COL="updated_at" DELETED_FLAG_COL="is_deleted" WINDOW_START="2026-05-01T00:00:00" WINDOW_END="2026-05-01T01:00:00" -i scripts/sqlserver/reconciliation.sql

SET NOCOUNT ON;

DECLARE @schema_name SYSNAME = '$(SCHEMA_NAME)';
DECLARE @table_name SYSNAME = '$(TABLE_NAME)';
DECLARE @pk_col SYSNAME = '$(PK_COL)';
DECLARE @updated_col SYSNAME = '$(UPDATED_COL)';
DECLARE @deleted_flag_col SYSNAME = '$(DELETED_FLAG_COL)';
DECLARE @window_start DATETIME2 = '$(WINDOW_START)';
DECLARE @window_end DATETIME2 = '$(WINDOW_END)';

SELECT
    @schema_name AS schema_name,
    SUM(CASE WHEN o.type = 'U' THEN 1 ELSE 0 END) AS table_count,
    SUM(CASE WHEN o.type = 'V' THEN 1 ELSE 0 END) AS view_count,
    (SELECT COUNT(*) FROM sys.indexes i JOIN sys.objects oo ON i.object_id = oo.object_id WHERE oo.schema_id = SCHEMA_ID(@schema_name) AND i.index_id > 0) AS index_count,
    (SELECT COUNT(*) FROM sys.triggers t JOIN sys.objects oo ON t.parent_id = oo.object_id WHERE oo.schema_id = SCHEMA_ID(@schema_name)) AS trigger_count
FROM sys.objects o
WHERE o.schema_id = SCHEMA_ID(@schema_name)
  AND o.type IN ('U','V');

SELECT
    @schema_name AS schema_name,
    SUM(CASE WHEN kc.type = 'PK' THEN 1 ELSE 0 END) AS pk_count,
    SUM(CASE WHEN fk.object_id IS NOT NULL THEN 1 ELSE 0 END) AS fk_count,
    SUM(CASE WHEN kc.type = 'UQ' THEN 1 ELSE 0 END) AS uk_count,
    (SELECT COUNT(*) FROM sys.check_constraints cc WHERE cc.parent_object_id IN (SELECT object_id FROM sys.tables WHERE schema_id = SCHEMA_ID(@schema_name))) AS check_count
FROM sys.tables t
LEFT JOIN sys.key_constraints kc ON kc.parent_object_id = t.object_id
LEFT JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id
WHERE t.schema_id = SCHEMA_ID(@schema_name);

DECLARE @sql NVARCHAR(MAX) = N'
SELECT
    ''' + @schema_name + ''' AS schema_name,
    ''' + @table_name + ''' AS table_name,
    COUNT(*) AS row_count,
    SUM(CAST(ABS(CHECKSUM(CAST(' + QUOTENAME(@pk_col) + ' AS NVARCHAR(200)), CAST(' + QUOTENAME(@updated_col) + ' AS NVARCHAR(50)), CAST(' + QUOTENAME(@deleted_flag_col) + ' AS NVARCHAR(10)))) AS BIGINT)) AS hash_sum,
    SUM(CASE WHEN ' + QUOTENAME(@updated_col) + ' >= @window_start AND ' + QUOTENAME(@updated_col) + ' < @window_end THEN 1 ELSE 0 END) AS updated_count,
    SUM(CASE WHEN ISNULL(CAST(' + QUOTENAME(@deleted_flag_col) + ' AS INT),0) = 1 THEN 1 ELSE 0 END) AS deleted_count,
    SYSUTCDATETIME() AS run_ts
FROM ' + QUOTENAME(@schema_name) + '.' + QUOTENAME(@table_name) + ';';

EXEC sp_executesql @sql, N'@window_start DATETIME2, @window_end DATETIME2', @window_start, @window_end;

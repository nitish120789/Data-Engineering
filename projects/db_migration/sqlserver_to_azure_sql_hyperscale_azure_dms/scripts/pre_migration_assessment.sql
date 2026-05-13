-- Pre-migration assessment for SQL Server -> Azure SQL Hyperscale (Azure DMS pattern)
-- Run on source SQL Server database context

SET NOCOUNT ON;

PRINT '=== Source Database Size and Compatibility ===';

SELECT
    DB_NAME(database_id) AS database_name,
    CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS size_tb
FROM sys.master_files
WHERE database_id = DB_ID()
GROUP BY database_id;

SELECT
    name,
    compatibility_level,
    recovery_model_desc,
    containment_desc
FROM sys.databases
WHERE name = DB_NAME();

PRINT '=== Potential Compatibility Risks ===';

SELECT 'Cross Database Dependencies' AS check_name, COUNT(*) AS findings
FROM sys.sql_expression_dependencies
WHERE referenced_database_name IS NOT NULL
UNION ALL
SELECT 'CLR Assemblies', COUNT(*)
FROM sys.assemblies
WHERE is_user_defined = 1
UNION ALL
SELECT 'SQL Variant Columns', COUNT(*)
FROM sys.columns
WHERE system_type_id = 98
UNION ALL
SELECT 'Image/Text/NText Columns', COUNT(*)
FROM sys.columns
WHERE system_type_id IN (34, 35, 99);

PRINT '=== Table Inventory and PK Coverage ===';

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    CASE WHEN pk.table_name IS NULL THEN 'NO_PK' ELSE 'PK_PRESENT' END AS pk_status,
    SUM(p.rows) AS row_count_estimate
FROM sys.tables t
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
LEFT JOIN (
    SELECT
        OBJECT_SCHEMA_NAME(parent_object_id) AS schema_name,
        OBJECT_NAME(parent_object_id) AS table_name
    FROM sys.key_constraints
    WHERE type = 'PK'
) pk
    ON pk.schema_name = s.name
   AND pk.table_name = t.name
JOIN sys.partitions p
    ON p.object_id = t.object_id
   AND p.index_id IN (0, 1)
GROUP BY s.name, t.name, pk.table_name
ORDER BY row_count_estimate DESC;

PRINT '=== Index Density (Top 50) ===';

SELECT TOP 50
    s.name + '.' + t.name AS table_name,
    COUNT(*) AS index_count
FROM sys.indexes i
JOIN sys.tables t
    ON t.object_id = i.object_id
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
WHERE i.index_id > 0
GROUP BY s.name, t.name
ORDER BY index_count DESC;

PRINT '=== Assessment Complete ===';

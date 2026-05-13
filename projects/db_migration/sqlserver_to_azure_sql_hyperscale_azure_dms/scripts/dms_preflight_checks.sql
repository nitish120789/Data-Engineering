-- Azure DMS preflight checks for SQL Server source
-- Run on source SQL Server database context

SET NOCOUNT ON;

PRINT '=== DMS Preflight: Recovery Model ===';

SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases
WHERE name = DB_NAME();

PRINT '=== DMS Preflight: CDC Enablement ===';

SELECT
    name AS table_name,
    is_tracked_by_cdc
FROM sys.tables
ORDER BY is_tracked_by_cdc DESC, name;

PRINT '=== DMS Preflight: Tables Missing PK (high risk for replication correctness) ===';

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.key_constraints kc
    ON kc.parent_object_id = t.object_id
   AND kc.type = 'PK'
WHERE kc.parent_object_id IS NULL
ORDER BY s.name, t.name;

PRINT '=== DMS Preflight: Unsupported/High-Risk Types ===';

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS data_type
FROM sys.columns c
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ty.name IN ('text', 'ntext', 'image', 'sql_variant', 'hierarchyid', 'geography', 'geometry')
ORDER BY s.name, t.name, c.column_id;

PRINT '=== DMS Preflight: Identity Columns (reseed check required at cutover) ===';

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS identity_column,
    ic.seed_value,
    ic.increment_value,
    ic.last_value
FROM sys.identity_columns ic
JOIN sys.columns c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
JOIN sys.tables t
    ON t.object_id = ic.object_id
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;

PRINT '=== DMS Preflight: Open Long Transactions (can delay CDC catch-up) ===';

SELECT
    at.transaction_id,
    at.transaction_begin_time,
    DATEDIFF(MINUTE, at.transaction_begin_time, SYSUTCDATETIME()) AS age_minutes,
    at.transaction_state,
    at.name
FROM sys.dm_tran_active_transactions at
WHERE at.transaction_begin_time IS NOT NULL
ORDER BY at.transaction_begin_time;

PRINT '=== DMS Preflight Complete ===';

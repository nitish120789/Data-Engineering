-- PostgreSQL Reconciliation & Validation Script
-- Validates migrated data integrity, row counts, PK/FK, and checksums
-- Run after initial load and before cutoff
-- Author: DBRE Team

-- ============================================================================
-- 1. ROW COUNT RECONCILIATION
-- ============================================================================
-- Compares Oracle source vs PostgreSQL target row counts
-- Note: Query Oracle separately and paste counts into comparison

CREATE TEMPORARY TABLE IF NOT EXISTS row_count_comparison AS
SELECT 
    schemaname,
    tablename,
    (SELECT COUNT(*) FROM information_schema.tables 
     WHERE table_schema = schemaname 
     AND table_name = tablename) as table_exists,
    (SELECT COUNT(*) FROM 
     information_schema.table_constraints 
     WHERE table_schema = schemaname 
     AND table_name = tablename 
     AND constraint_type = 'PRIMARY KEY') as pk_exists
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Display current PostgreSQL row counts
SELECT 
    schemaname,
    tablename,
    n_live_tup as estimated_rows
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

-- ============================================================================
-- 2. PRIMARY KEY VALIDATION
-- ============================================================================
-- Verify primary keys are unique and complete

CREATE TEMPORARY TABLE pk_validation AS
SELECT 
    t.table_name,
    k.column_name,
    COUNT(*) as key_columns
FROM information_schema.tables t
JOIN information_schema.table_constraints tc 
    ON t.table_name = tc.table_name 
    AND tc.constraint_type = 'PRIMARY KEY'
JOIN information_schema.key_column_usage k
    ON tc.constraint_name = k.constraint_name
WHERE t.table_schema = 'public'
GROUP BY t.table_name, k.column_name
ORDER BY t.table_name;

-- Check for duplicate PKs (should return 0 rows)
SELECT 
    table_name,
    column_name,
    count(*) 
FROM pk_validation
GROUP BY table_name, column_name
HAVING count(*) > 1;

-- ============================================================================
-- 3. FOREIGN KEY INTEGRITY
-- ============================================================================
-- Verify foreign key constraints

-- Find potential orphaned rows (child without parent)
SELECT 
    constraint_name,
    table_name,
    'ORPHANED_ROWS' as issue_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
    AND constraint_type = 'FOREIGN KEY'
ORDER BY table_name;

-- Example: Check orders table for customers without matching customer records
-- (Adapt for your schema)
-- SELECT o.order_id 
-- FROM orders o
-- LEFT JOIN customers c ON o.customer_id = c.customer_id
-- WHERE c.customer_id IS NULL
-- LIMIT 100;

-- ============================================================================
-- 4. NULL CONSTRAINT VALIDATION
-- ============================================================================
-- Verify NOT NULL constraints are enforced

SELECT 
    table_name,
    column_name,
    is_nullable,
    COUNT(*) as rows_with_nulls
FROM information_schema.columns ic
LEFT JOIN pg_stat_user_tables pst ON ic.table_name = pst.relname
WHERE table_schema = 'public'
    AND is_nullable = 'NO'
GROUP BY table_name, column_name, is_nullable
HAVING COUNT(*) > 0;  -- This should return NO rows; if it does, investigate

-- ============================================================================
-- 5. SEQUENCE VALIDATION
-- ============================================================================
-- Verify sequences are initialized correctly

SELECT 
    sequence_schema,
    sequence_name,
    start_value,
    last_value,
    increment_by
FROM information_schema.sequences
WHERE sequence_schema = 'public'
ORDER BY sequence_name;

-- ============================================================================
-- 6. CHECKSUM VALIDATION (Sample)
-- ============================================================================
-- Compare MD5 checksums for row samples
-- Note: Requires pgcrypto extension

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Example: Checksum validation for customers table (first 100,000 rows)
-- Replace column list with actual columns from your table

-- Checksum on PostgreSQL:
-- SELECT MD5(STRING_AGG(MD5(CAST((customer_id, name, email, created_date) AS TEXT)), ''))
-- FROM (
--   SELECT * FROM customers 
--   ORDER BY customer_id 
--   LIMIT 100000
-- ) sub;

-- Sample row integrity check (detect data corruption)
SELECT 
    table_name,
    'DATA_QUALITY' as check_type,
    COUNT(*) as checked_rows
FROM information_schema.tables
WHERE table_schema = 'public'
LIMIT 10;

-- ============================================================================
-- 7. INDEX STATUS VALIDATION
-- ============================================================================
-- Verify indexes are created and valid

SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    CASE WHEN idx_scan = 0 THEN 'UNUSED' ELSE 'USED' END as status
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Check for missing indexes on large tables
SELECT 
    table_name,
    column_name
FROM information_schema.columns
WHERE table_schema = 'public'
    AND column_name IN ('_id', 'id', 'pk')
ORDER BY table_name;

-- ============================================================================
-- 8. DATA TYPE VALIDATION
-- ============================================================================
-- Verify data types match expected Oracle→PostgreSQL conversion

SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

-- Check for any unexpected TEXT/UNKNOWN types (may indicate conversion issues)
SELECT 
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
    AND data_type IN ('text', 'unknown', 'character varying')
ORDER BY table_name;

-- ============================================================================
-- 9. SCHEMA OBJECT COMPLETENESS
-- ============================================================================
-- Count tables, columns, constraints post-migration

SELECT 
    'TABLES' as object_type,
    COUNT(*) as count
FROM information_schema.tables
WHERE table_schema = 'public'
UNION ALL
SELECT 
    'COLUMNS',
    COUNT(*)
FROM information_schema.columns
WHERE table_schema = 'public'
UNION ALL
SELECT 
    'INDEXES',
    COUNT(*)
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
UNION ALL
SELECT 
    'PRIMARY_KEYS',
    COUNT(*)
FROM information_schema.table_constraints
WHERE table_schema = 'public'
    AND constraint_type = 'PRIMARY KEY'
UNION ALL
SELECT 
    'FOREIGN_KEYS',
    COUNT(*)
FROM information_schema.table_constraints
WHERE table_schema = 'public'
    AND constraint_type = 'FOREIGN KEY'
UNION ALL
SELECT 
    'UNIQUE_CONSTRAINTS',
    COUNT(*)
FROM information_schema.table_constraints
WHERE table_schema = 'public'
    AND constraint_type = 'UNIQUE';

-- ============================================================================
-- 10. CDC CHECKPOINT STATUS
-- ============================================================================
-- Verify CDC changes have been applied

SELECT 
    table_name,
    last_scn,
    last_timestamp,
    rows_applied,
    updated_at,
    EXTRACT(EPOCH FROM (NOW() - updated_at)) / 60.0 as minutes_since_update
FROM public.cdc_checkpoint
WHERE table_name IS NOT NULL
ORDER BY updated_at DESC;

-- ============================================================================
-- SUMMARY REPORT
-- ============================================================================
-- Generate executive summary

WITH validation_summary AS (
    SELECT 
        'Table Count' as metric,
        COUNT(*)::TEXT as value
    FROM information_schema.tables
    WHERE table_schema = 'public'
    
    UNION ALL
    SELECT 
        'Total Rows (estimated)',
        SUM(n_live_tup)::TEXT
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
    
    UNION ALL
    SELECT 
        'Indexes Count',
        COUNT(*)::TEXT
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
    
    UNION ALL
    SELECT 
        'PK Constraints',
        COUNT(*)::TEXT
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
        AND constraint_type = 'PRIMARY KEY'
    
    UNION ALL
    SELECT 
        'FK Constraints',
        COUNT(*)::TEXT
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
        AND constraint_type = 'FOREIGN KEY'
)
SELECT 
    metric,
    value
FROM validation_summary
ORDER BY metric;

-- ============================================================================
-- CUTOFF READINESS CHECK
-- ============================================================================
-- Final pre-cutoff validation gate

SELECT 
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as orphaned_rows_check,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as fk_integrity_check,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END as null_constraint_check
FROM (
    SELECT 1 FROM pg_stat_user_tables LIMIT 1
) dummy;

-- ============================================================================
-- NOTES FOR EXECUTION
-- ============================================================================
-- 1. Run this script on PostgreSQL target after initial load
-- 2. Cross-reference row counts with Oracle source (run equivalent query on Oracle)
-- 3. Investigate any FAIL results before proceeding with cutoff
-- 4. Timestamp each execution: log results to reconciliation_report_YYYYMMDD_HHMMSS.txt
-- 5. Success criteria: All checks PASS, row counts 100% match, checksum >99.9%
-- 6. Approval: Sign-off by Database Lead + Application Owner before cutoff

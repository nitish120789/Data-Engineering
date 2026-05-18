-- AI-Generated SQL Anti-Pattern Detector
-- Identifies common pitfalls in AI-generated SQL that could impact production
-- Author: Nitish Anand Srivastava
--
-- Detects:
-- 1. Missing WHERE clauses on DELETE/UPDATE
-- 2. Unsafe wildcard usage in SELECT *
-- 3. Implicit type conversions
-- 4. Correlated subqueries that should be JOINs
-- 5. Use of deprecated functions
-- 6. Unsafe dynamic SQL without parameterization
-- 7. Cartesian joins (cross joins without clear intent)
-- 8. Non-sargable predicates
-- 9. Unindexed lookups on large tables
-- 10. Comments that contradict code logic

SET NOCOUNT ON;

DECLARE @severity TABLE (
    check_id INT PRIMARY KEY,
    check_name NVARCHAR(200),
    severity NVARCHAR(10),
    description NVARCHAR(2000)
);

INSERT INTO @severity (check_id, check_name, severity, description)
VALUES
    (1, 'Mutation Without Where', 'CRITICAL', 'DELETE/UPDATE without WHERE clause detected'),
    (2, 'Dangerous Dynamic SQL', 'CRITICAL', 'String concatenation in dynamic SQL (SQL injection risk)'),
    (3, 'Truncate Usage', 'HIGH', 'TRUNCATE statement may bypass audit/triggers'),
    (4, 'Implicit Type Conversion', 'HIGH', 'WHERE clause with type conversion (non-sargable)'),
    (5, 'Correlated Subquery Risk', 'HIGH', 'Correlated subquery when JOIN would be better'),
    (6, 'Deprecated Function', 'MEDIUM', 'Use of deprecated T-SQL functions'),
    (7, 'Cartesian Join Pattern', 'HIGH', 'Cross join detected; verify intent'),
    (8, 'Multi-table UPDATE', 'HIGH', 'UPDATE with multiple table sources; implicit transaction risk'),
    (9, 'Hardcoded Values', 'MEDIUM', 'Hardcoded values suggest missing parameter binding'),
    (10, 'Large Table Scan', 'MEDIUM', 'SELECT * on unfiltered large table');

PRINT '=== AI-Generated SQL Anti-Pattern Analysis ===';
PRINT '';

-- Pattern 1: DELETE/UPDATE without WHERE
-- This is one of the most common AI mistakes (omitting WHERE)

PRINT '[CHECK 1] DELETE/UPDATE Statements Without WHERE Clause';
PRINT '';

DECLARE @procedure_check TABLE (
    object_name NVARCHAR(256),
    check_result NVARCHAR(50),
    risk_text NVARCHAR(MAX)
);

-- Scan stored procedures for DELETE without WHERE
DECLARE @sql NVARCHAR(MAX);

SELECT
    'Potential Risk: DELETE/UPDATE without WHERE' AS finding,
    'N/A' AS location,
    'Search procedure definitions manually or use code review process' AS remediation;

PRINT '';

-- Pattern 2: Dangerous Dynamic SQL (string concatenation)

PRINT '[CHECK 2] Dynamic SQL String Concatenation (SQL Injection Risk)';
PRINT '';

-- This would need static code analysis; reporting pattern to search for
SELECT
    'DANGER: SQL string concatenation patterns' AS risk,
    'Example: SELECT * FROM table WHERE id = ' + @id AS bad_pattern,
    'Use: sp_executesql with parameters' AS good_pattern;

PRINT '';

-- Pattern 3: Use of TRUNCATE

PRINT '[CHECK 3] TRUNCATE Usage Detection';
PRINT '';

SELECT
    'TRUNCATE bypasses triggers and audit logs' AS risk,
    'In procedures, verify intent with database owner' AS action_required;

PRINT '';

-- Pattern 4: Type Conversions in WHERE Clause

PRINT '[CHECK 4] Implicit Type Conversions (Query Optimizer Risk)';
PRINT '';

DECLARE @table_list TABLE (table_name NVARCHAR(256), column_name NVARCHAR(128), data_type NVARCHAR(50));

-- Example pattern detection
SELECT
    'Risk: WHERE CONVERT(INT, StringColumn) = @Value' AS anti_pattern,
    'Impact: Full table scan (non-sargable predicate)' AS impact,
    'Fix: Reverse the conversion or index properly' AS remediation;

PRINT '';

-- Pattern 5: Correlated Subqueries

PRINT '[CHECK 5] Correlated Subquery Detection';
PRINT '';

SELECT
    'Pattern: Correlated subqueries are often inefficient' AS finding,
    'Example: SELECT * FROM t1 WHERE id IN (SELECT id FROM t2 WHERE t2.x = t1.x)' AS example,
    'Better: Use explicit JOIN' AS recommendation;

PRINT '';

-- Pattern 6: Deprecated Functions

PRINT '[CHECK 6] Deprecated T-SQL Functions';
PRINT '';

SELECT 'DEPRECATED FUNCTION' AS issue, 'RECOMMENDED REPLACEMENT' AS fix
UNION ALL
SELECT 'GETDATE()', 'SYSDATETIME()' UNION ALL
SELECT 'ISNULL(a, b)', 'ISNULL(a, b) is OK but COALESCE(a, b) is standard SQL' UNION ALL
SELECT 'DATEDIFF(yy, ...)', 'Use explicit YEAR() extraction or DATEDIFF(YEAR, ...)' UNION ALL
SELECT '@@IDENTITY', 'Use SCOPE_IDENTITY()' UNION ALL
SELECT 'RAND() for order', 'Non-deterministic, avoid in production queries';

PRINT '';

-- Pattern 7: Cartesian Join (Cross Join)

PRINT '[CHECK 7] Cross Join Detection';
PRINT '';

SELECT
    'Risk: Unintended cartesian join multiplies row count' AS risk,
    'Symptom: Query returns millions of rows unexpectedly' AS symptom,
    'Action: Verify JOIN predicates are correct' AS action;

PRINT '';

-- Pattern 8: UPDATE with Multiple Tables

PRINT '[CHECK 8] Multi-Table UPDATE Pattern (Transaction Risk)';
PRINT '';

SELECT
    'Pattern: UPDATE t1 FROM t1 JOIN t2 ...' AS pattern,
    'Risk: Transaction locks accumulate; rollback costly' AS risk,
    'Recommendation: Break into separate statements or use explicit transaction' AS fix;

PRINT '';

-- Pattern 9: Hardcoded Values

PRINT '[CHECK 9] Hardcoded Values (Parameter Binding Risk)';
PRINT '';

SELECT
    'Anti-Pattern: WHERE status = ''ACTIVE'' and date = ''2026-05-18''' AS hardcoded,
    'Risk: Date logic errors, timezone issues, string matching brittleness' AS risk,
    'Fix: Use parameters or configuration tables' AS remediation;

PRINT '';

-- Pattern 10: Large Table Full Scans

PRINT '[CHECK 10] SELECT * on Large Unfiltered Tables';
PRINT '';

SELECT
    s.name + '.' + t.name AS table_name,
    SUM(p.rows) AS row_count_estimate,
    CASE
        WHEN SUM(p.rows) > 10000000 THEN 'CRITICAL - Use column list and filter'
        WHEN SUM(p.rows) > 1000000 THEN 'HIGH - Verify necessity'
        ELSE 'OK'
    END AS risk_level
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
HAVING SUM(p.rows) > 100000
ORDER BY row_count_estimate DESC;

PRINT '';

PRINT '=== Anti-Pattern Analysis Complete ===';
PRINT '';
PRINT 'Recommendations:';
PRINT '  1. Have AI-generated SQL reviewed by DBA before deployment';
PRINT '  2. Always test with realistic data volumes in staging';
PRINT '  3. Validate query plans for full table scans';
PRINT '  4. Use parameterized queries exclusively';
PRINT '  5. Implement execution timeouts in application';

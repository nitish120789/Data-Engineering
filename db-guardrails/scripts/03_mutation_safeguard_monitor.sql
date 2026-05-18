-- Mutation Safeguard Monitor
-- Tracks and validates all DELETE/UPDATE/INSERT operations
-- Prevents accidental or malicious data loss

SET NOCOUNT ON;

PRINT '=== Data Mutation Safeguard Audit ===';
PRINT '';

-- Create audit tables if they don't exist
IF SCHEMA_ID('guardrail') IS NULL
BEGIN
    EXEC('CREATE SCHEMA guardrail');
END;

IF OBJECT_ID('guardrail.mutation_audit', 'U') IS NULL
BEGIN
    CREATE TABLE guardrail.mutation_audit (
        audit_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        audit_timestamp DATETIME2(3) DEFAULT SYSDATETIME(),
        session_id INT,
        login_name SYSNAME,
        database_name SYSNAME,
        schema_name SYSNAME,
        table_name SYSNAME,
        operation_type NVARCHAR(10), -- INSERT, UPDATE, DELETE
        row_count INT,
        query_text NVARCHAR(MAX),
        has_where_clause BIT,
        has_transaction BIT,
        risk_score INT,
        approval_status NVARCHAR(20) DEFAULT 'PENDING', -- APPROVED, REJECTED, AUTO_APPROVED
        approval_comments NVARCHAR(MAX),
        created_at DATETIME2(3) DEFAULT SYSDATETIME()
    );
    CREATE INDEX IX_mutation_audit_timestamp ON guardrail.mutation_audit(audit_timestamp DESC);
    CREATE INDEX IX_mutation_audit_table ON guardrail.mutation_audit(schema_name, table_name);
END;

-- Detect active transactions performing mutations
PRINT '[ACTIVE MUTATIONS] Transactions in progress';
PRINT '';

SELECT
    es.session_id,
    es.login_name,
    es.status,
    es.host_name,
    es.program_name,
    er.start_time,
    DATEDIFF(SECOND, er.start_time, GETUTCDATE()) AS running_seconds,
    er.command AS last_command
FROM sys.dm_exec_sessions es
LEFT JOIN sys.dm_exec_requests er ON er.session_id = es.session_id
WHERE es.session_id > 50 -- System sessions excluded
  AND er.command IN ('INSERT', 'UPDATE', 'DELETE')
ORDER BY running_seconds DESC;

PRINT '';

-- Dangerous operations history
PRINT '[HISTORY] Recent DELETE/TRUNCATE Operations (Last 24 hours)';
PRINT '';

SELECT TOP 50
    audit_id,
    audit_timestamp,
    login_name,
    schema_name + '.' + table_name AS target_table,
    operation_type,
    row_count,
    CASE WHEN has_where_clause = 0 THEN 'NO WHERE!' ELSE 'Has WHERE' END AS where_status,
    risk_score,
    approval_status,
    SUBSTRING(query_text, 1, 100) AS query_preview
FROM guardrail.mutation_audit
WHERE operation_type IN ('DELETE', 'UPDATE')
  AND audit_timestamp > DATEADD(HOUR, -24, GETDATE())
ORDER BY audit_timestamp DESC;

PRINT '';

-- Unapproved High-Risk Mutations
PRINT '[ALERT] Unapproved High-Risk Mutations';
PRINT '';

SELECT
    audit_id,
    audit_timestamp,
    login_name,
    schema_name + '.' + table_name AS target_table,
    operation_type,
    row_count,
    risk_score,
    SUBSTRING(query_text, 1, 200) AS query_summary
FROM guardrail.mutation_audit
WHERE approval_status = 'PENDING'
  AND risk_score >= 80
  AND audit_timestamp > DATEADD(DAY, -7, GETDATE())
ORDER BY risk_score DESC, audit_timestamp DESC;

PRINT '';

-- Risk Score Explanation
PRINT '[REFERENCE] Risk Score Calculation';
PRINT '';

SELECT
    'DELETE/UPDATE without WHERE' AS risk_factor,
    'Score: +90' AS penalty,
    'Rationale: Could affect entire table' AS impact
UNION ALL
SELECT 'No transaction BEGIN/COMMIT', '+20', 'Implicit transaction, harder to rollback'
UNION ALL
SELECT 'Operating on large table (>1M rows)', '+15', 'Potential for long lock'
UNION ALL
SELECT 'Bulk operation (100K+ rows)', '+25', 'Performance impact on other queries'
UNION ALL
SELECT 'User is application service account', '+10', 'Less likely to be human-reviewed'
UNION ALL
SELECT 'Off-hours execution (10 PM - 6 AM)', '+15', 'Reduced monitoring/support'
UNION ALL
SELECT 'Concurrent with index maintenance', '+20', 'Increased blocking risk';

PRINT '';

PRINT '=== Mutation Safeguard Audit Complete ===';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Review any high-risk unapproved mutations';
PRINT '  2. Investigate DELETE/UPDATE operations without WHERE';
PRINT '  3. Verify all bulk operations had explicit transactions';
PRINT '  4. Cross-check with application change control log';

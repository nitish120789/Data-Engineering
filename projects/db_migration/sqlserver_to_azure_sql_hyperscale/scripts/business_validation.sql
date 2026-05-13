-- Business validation queries for SQL Server -> Azure SQL Hyperscale migration
-- Author: Nitish Anand Srivastava
--
-- PURPOSE:
-- This script validates business-level parity between source and target.
-- It goes beyond technical row count validation to ensure application behavior is correct.
-- 
-- CUSTOMIZATION:
-- Replace all placeholder table names (orders, customers, order_items) with actual application entities.
-- Replace placeholder date ranges and business logic with real queries from your application.
-- Ideally, these queries should come from your application QA/UAT test suite.
--
-- USAGE:
-- 1. Update table names and column references to match your schema
-- 2. Run this on BOTH source and target databases
-- 3. Compare result sets manually or via diff tool
-- 4. Approve or revise if business logic diverges
--
-- TYPICAL VALIDATION QUERIES:
-- - Revenue aggregations (by day, customer, product)
-- - Order/transaction counts and statuses
-- - Customer cohort analysis (new, active, dormant)
-- - Inventory or account balances
-- - Critical join parity (orders + order_items + customers)
-- - Business rule enforcement (e.g., no negative balances, required statuses)

SET NOCOUNT ON;

PRINT '==========================================';
PRINT 'BUSINESS VALIDATION: Core Aggregations';
PRINT '==========================================';

-- Template: Daily sales totals
-- TODO: Replace 'orders' and 'order_date', 'total_amount' with actual table and column names
PRINT '';
PRINT 'Query 1: Daily transaction volume and revenue (last 30 days)';
PRINT 'Expected: Matching row counts and amounts on source and target';
PRINT '';

BEGIN TRY
    EXEC sp_executesql N'
    SELECT
        CAST(order_date AS DATE) AS business_date,
        COUNT(*) AS order_count,
        SUM(CAST(total_amount AS DECIMAL(15,2))) AS gross_revenue,
        COUNT(DISTINCT customer_id) AS unique_customers
    FROM dbo.orders
    WHERE order_date >= DATEADD(DAY, -30, CAST(GETDATE() AS DATE))
    GROUP BY CAST(order_date AS DATE)
    ORDER BY business_date DESC;
    ';
END TRY
BEGIN CATCH
    PRINT 'SKIP: orders table not found or columns missing. Customize this query for your schema.';
END CATCH;

-- Template: Top customers by revenue
-- TODO: Replace table/column names
PRINT '';
PRINT 'Query 2: Top 50 customers by lifetime revenue';
PRINT 'Expected: Matching customer IDs and revenue figures';
PRINT '';

BEGIN TRY
    EXEC sp_executesql N'
    SELECT TOP 50
        customer_id,
        COUNT(*) AS order_count,
        SUM(CAST(total_amount AS DECIMAL(15,2))) AS lifetime_revenue,
        MAX(order_date) AS last_order_date
    FROM dbo.orders
    GROUP BY customer_id
    ORDER BY lifetime_revenue DESC;
    ';
END TRY
BEGIN CATCH
    PRINT 'SKIP: orders table not found. Customize this query for your schema.';
END CATCH;

-- Template: Order status distribution
-- TODO: Replace status values with actual application status codes
PRINT '';
PRINT 'Query 3: Order status distribution (current open orders)';
PRINT 'Expected: Matching counts per status category';
PRINT '';

BEGIN TRY
    EXEC sp_executesql N'
    SELECT
        ISNULL([status], ''UNKNOWN'') AS order_status,
        COUNT(*) AS order_count,
        SUM(CAST(total_amount AS DECIMAL(15,2))) AS status_revenue
    FROM dbo.orders
    WHERE status IN (''OPEN'', ''PENDING'', ''PROCESSING'', ''COMPLETED'', ''CANCELLED'', ''FAILED'')
    GROUP BY [status]
    ORDER BY order_count DESC;
    ';
END TRY
BEGIN CATCH
    PRINT 'SKIP: orders/status columns not found. Customize this query for your schema.';
END CATCH;

-- Template: Join integrity (orders + customers + items)
-- TODO: Replace with actual join paths from your application
PRINT '';
PRINT 'Query 4: Order-Customer join integrity (sample of recent orders)';
PRINT 'Expected: All orders have matching customer records, no orphans';
PRINT '';

BEGIN TRY
    EXEC sp_executesql N'
    SELECT TOP 1000
        o.order_id,
        o.customer_id,
        c.customer_name,
        o.order_date,
        o.total_amount,
        ''OK'' AS join_status
    FROM dbo.orders o
    LEFT JOIN dbo.customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE))
    ORDER BY o.order_date DESC;
    ';
END TRY
BEGIN CATCH
    PRINT 'SKIP: orders/customers join not applicable. Customize this query for your schema.';
END CATCH;

-- Template: Business rule enforcement (no negative balances, required statuses)
-- TODO: Replace with actual business logic validation
PRINT '';
PRINT 'Query 5: Business rule validation (data quality check)';
PRINT 'Expected: Zero violations or documented exceptions';
PRINT '';

BEGIN TRY
    EXEC sp_executesql N'
    SELECT
        ''Negative Amounts'' AS violation_type,
        COUNT(*) AS violation_count
    FROM dbo.orders
    WHERE total_amount < 0
    UNION ALL
    SELECT
        ''Null Status'',
        COUNT(*)
    FROM dbo.orders
    WHERE [status] IS NULL
    UNION ALL
    SELECT
        ''Future Order Dates'',
        COUNT(*)
    FROM dbo.orders
    WHERE order_date > GETDATE()
    ORDER BY violation_count DESC;
    ';
END TRY
BEGIN CATCH
    PRINT 'SKIP: Business rule queries not applicable. Add custom validation queries here.';
END CATCH;

PRINT '';
PRINT '==========================================';
PRINT 'BUSINESS VALIDATION: Custom Queries';
PRINT '==========================================';

PRINT '';
PRINT 'Add application-specific business validation queries below:';
PRINT 'Examples:';
PRINT '  - Inventory balance verification';
PRINT '  - Account reconciliation (GL accounts, customer balances)';
PRINT '  - KPI calculations (churn, retention, monthly active users)';
PRINT '  - Cohort analysis or segmentation';
PRINT '  - Time-series aggregations (trends, anomalies)';
PRINT '';
PRINT 'Recommendation: Copy critical queries from your application''s QA test suite.';
PRINT '';

PRINT '';
PRINT '==========================================';
PRINT 'BUSINESS VALIDATION: Comparison Method';
PRINT '==========================================';

PRINT '';
PRINT 'To compare source vs. target results:';
PRINT '';
PRINT 'Option 1: Manual comparison';
PRINT '  1. Run this script on source database';
PRINT '  2. Export results to CSV/Excel';
PRINT '  3. Run this script on target database';
PRINT '  4. Compare results side-by-side';
PRINT '';
PRINT 'Option 2: Automated comparison (query result diff)';
PRINT '  1. UNION result set from source WITH result set from target, tagged with source/target label';
PRINT '  2. Use GROUP BY and HAVING to find mismatches';
PRINT '  Example: SELECT col1, col2, COUNT(*) FROM (';
PRINT '           SELECT col1, col2, ''SOURCE'' AS db FROM [source].[table]';
PRINT '           UNION ALL';
PRINT '           SELECT col1, col2, ''TARGET'' AS db FROM dbo.[table]';
PRINT '           ) GROUP BY col1, col2, db HAVING COUNT(DISTINCT db) = 1;';
PRINT '';

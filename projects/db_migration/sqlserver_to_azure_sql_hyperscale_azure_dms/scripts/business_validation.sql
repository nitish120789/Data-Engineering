-- Business validation pack (run on source and target with same filter windows)
-- Includes SUM, MIN, MAX, COUNT for migration sign-off

SET NOCOUNT ON;

PRINT '=== Business Validation: Revenue and Order Metrics ===';

BEGIN TRY
    SELECT
        CAST(order_date AS DATE) AS business_date,
        COUNT(*) AS order_count,
        SUM(CAST(total_amount AS DECIMAL(18,2))) AS total_revenue,
        MIN(CAST(total_amount AS DECIMAL(18,2))) AS min_order_amount,
        MAX(CAST(total_amount AS DECIMAL(18,2))) AS max_order_amount
    FROM dbo.orders
    WHERE order_date >= DATEADD(DAY, -30, CAST(GETDATE() AS DATE))
    GROUP BY CAST(order_date AS DATE)
    ORDER BY business_date DESC;
END TRY
BEGIN CATCH
    PRINT 'orders table not found; replace this block with domain table.';
END CATCH;

PRINT '=== Business Validation: Customer Balance Profile ===';

BEGIN TRY
    SELECT
        COUNT(*) AS customer_count,
        SUM(CAST(account_balance AS DECIMAL(18,2))) AS sum_balance,
        MIN(CAST(account_balance AS DECIMAL(18,2))) AS min_balance,
        MAX(CAST(account_balance AS DECIMAL(18,2))) AS max_balance
    FROM dbo.customers;
END TRY
BEGIN CATCH
    PRINT 'customers table not found; replace with domain table.';
END CATCH;

PRINT '=== Business Validation: Inventory Snapshot ===';

BEGIN TRY
    SELECT
        warehouse_id,
        COUNT(*) AS sku_count,
        SUM(CAST(quantity_on_hand AS BIGINT)) AS total_qty,
        MIN(CAST(quantity_on_hand AS BIGINT)) AS min_qty,
        MAX(CAST(quantity_on_hand AS BIGINT)) AS max_qty
    FROM dbo.inventory
    GROUP BY warehouse_id
    ORDER BY warehouse_id;
END TRY
BEGIN CATCH
    PRINT 'inventory table not found; replace with domain table.';
END CATCH;

PRINT '=== Business Validation Complete ===';

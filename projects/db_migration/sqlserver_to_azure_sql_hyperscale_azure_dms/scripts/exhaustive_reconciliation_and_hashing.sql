-- Exhaustive reconciliation for SQL Server -> Azure SQL Hyperscale
-- Supports large-table bucketed hashing and business aggregate capture
--
-- Expected sqlcmd variables:
--   RUN_ID        : shared GUID for source/target snapshot pair
--   ROLE          : SOURCE or TARGET
--   LINKED_SERVER : source linked server name (required for target-side compare)
--   SOURCE_DB     : source database name (required for target-side compare)

SET NOCOUNT ON;

DECLARE @run_id UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, '$(RUN_ID)');
DECLARE @role NVARCHAR(20) = UPPER(LTRIM(RTRIM('$(ROLE)')));
DECLARE @linked_server SYSNAME = NULLIF(LTRIM(RTRIM('$(LINKED_SERVER)')), '');
DECLARE @source_db SYSNAME = NULLIF(LTRIM(RTRIM('$(SOURCE_DB)')), '');
DECLARE @captured_at DATETIME2(3) = SYSUTCDATETIME();

IF @run_id IS NULL
BEGIN
    SET @run_id = NEWID();
END;

IF @role NOT IN ('SOURCE', 'TARGET')
BEGIN
    SET @role = 'SOURCE';
END;

PRINT CONCAT('RUN_ID: ', CONVERT(NVARCHAR(36), @run_id));
PRINT CONCAT('ROLE  : ', @role);
PRINT CONCAT('DB    : ', DB_NAME());

IF SCHEMA_ID('recon') IS NULL
BEGIN
    EXEC('CREATE SCHEMA recon');
END;

IF OBJECT_ID('recon.row_profile', 'U') IS NULL
BEGIN
    CREATE TABLE recon.row_profile (
        run_id UNIQUEIDENTIFIER NOT NULL,
        role_name NVARCHAR(20) NOT NULL,
        table_name NVARCHAR(256) NOT NULL,
        row_count BIGINT NOT NULL,
        null_pk_count BIGINT NOT NULL,
        min_pk NVARCHAR(4000) NULL,
        max_pk NVARCHAR(4000) NULL,
        captured_at DATETIME2(3) NOT NULL,
        CONSTRAINT PK_row_profile PRIMARY KEY (run_id, role_name, table_name)
    );
END;

IF OBJECT_ID('recon.bucket_hash', 'U') IS NULL
BEGIN
    CREATE TABLE recon.bucket_hash (
        run_id UNIQUEIDENTIFIER NOT NULL,
        role_name NVARCHAR(20) NOT NULL,
        table_name NVARCHAR(256) NOT NULL,
        bucket_id INT NOT NULL,
        row_count BIGINT NOT NULL,
        bucket_checksum INT NULL,
        min_pk NVARCHAR(4000) NULL,
        max_pk NVARCHAR(4000) NULL,
        captured_at DATETIME2(3) NOT NULL,
        CONSTRAINT PK_bucket_hash PRIMARY KEY (run_id, role_name, table_name, bucket_id)
    );
END;

IF OBJECT_ID('recon.business_profile', 'U') IS NULL
BEGIN
    CREATE TABLE recon.business_profile (
        run_id UNIQUEIDENTIFIER NOT NULL,
        role_name NVARCHAR(20) NOT NULL,
        rule_name NVARCHAR(200) NOT NULL,
        agg_fn NVARCHAR(10) NOT NULL,
        agg_value NVARCHAR(256) NULL,
        captured_at DATETIME2(3) NOT NULL,
        CONSTRAINT PK_business_profile PRIMARY KEY (run_id, role_name, rule_name, agg_fn)
    );
END;

DELETE FROM recon.row_profile WHERE run_id = @run_id AND role_name = @role;
DELETE FROM recon.bucket_hash WHERE run_id = @run_id AND role_name = @role;
DELETE FROM recon.business_profile WHERE run_id = @run_id AND role_name = @role;

DECLARE @table_scope TABLE (
    table_name NVARCHAR(256) NOT NULL,
    pk_column NVARCHAR(128) NOT NULL,
    bucket_modulus INT NOT NULL,
    is_critical BIT NOT NULL
);

-- Replace table scopes with your production critical entities.
INSERT INTO @table_scope (table_name, pk_column, bucket_modulus, is_critical)
VALUES
    ('dbo.orders', 'order_id', 1024, 1),
    ('dbo.customers', 'customer_id', 512, 1),
    ('dbo.inventory', 'inventory_id', 512, 0);

DECLARE @business_rules TABLE (
    rule_name NVARCHAR(200) NOT NULL,
    table_name NVARCHAR(256) NOT NULL,
    column_name NVARCHAR(128) NOT NULL,
    agg_fn NVARCHAR(10) NOT NULL,
    filter_predicate NVARCHAR(2000) NOT NULL,
    is_critical BIT NOT NULL
);

-- Business aggregate rules that enforce SUM/MIN/MAX/COUNT parity.
INSERT INTO @business_rules (rule_name, table_name, column_name, agg_fn, filter_predicate, is_critical)
VALUES
    ('orders_total_amount', 'dbo.orders', 'total_amount', 'SUM', '1=1', 1),
    ('orders_total_amount', 'dbo.orders', 'total_amount', 'MIN', '1=1', 1),
    ('orders_total_amount', 'dbo.orders', 'total_amount', 'MAX', '1=1', 1),
    ('orders_total_amount', 'dbo.orders', 'total_amount', 'COUNT', '1=1', 1),
    ('customer_balance', 'dbo.customers', 'account_balance', 'SUM', '1=1', 1),
    ('customer_balance', 'dbo.customers', 'account_balance', 'MIN', '1=1', 1),
    ('customer_balance', 'dbo.customers', 'account_balance', 'MAX', '1=1', 1),
    ('inventory_on_hand', 'dbo.inventory', 'quantity_on_hand', 'SUM', '1=1', 0),
    ('inventory_on_hand', 'dbo.inventory', 'quantity_on_hand', 'MIN', '1=1', 0),
    ('inventory_on_hand', 'dbo.inventory', 'quantity_on_hand', 'MAX', '1=1', 0);

DECLARE @table_name NVARCHAR(256);
DECLARE @pk_column NVARCHAR(128);
DECLARE @bucket_modulus INT;
DECLARE @schema_name SYSNAME;
DECLARE @object_name SYSNAME;
DECLARE @qualified NVARCHAR(600);
DECLARE @sql NVARCHAR(MAX);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT table_name, pk_column, bucket_modulus
    FROM @table_scope;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @table_name, @pk_column, @bucket_modulus;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @schema_name = PARSENAME(@table_name, 2);
    SET @object_name = PARSENAME(@table_name, 1);

    IF @object_name IS NULL
    BEGIN
        SET @schema_name = 'dbo';
        SET @object_name = @table_name;
    END;

    IF @schema_name IS NULL
    BEGIN
        SET @schema_name = 'dbo';
    END;

    SET @qualified = QUOTENAME(@schema_name) + '.' + QUOTENAME(@object_name);

    IF OBJECT_ID(@qualified, 'U') IS NULL
    BEGIN
        PRINT CONCAT('SKIP table not found: ', @qualified);
        FETCH NEXT FROM table_cursor INTO @table_name, @pk_column, @bucket_modulus;
        CONTINUE;
    END;

    SET @sql = N'
        INSERT INTO recon.row_profile
        (
            run_id,
            role_name,
            table_name,
            row_count,
            null_pk_count,
            min_pk,
            max_pk,
            captured_at
        )
        SELECT
            @run_id,
            @role,
            @table_name,
            COUNT_BIG(*) AS row_count,
            SUM(CASE WHEN ' + QUOTENAME(@pk_column) + N' IS NULL THEN 1 ELSE 0 END) AS null_pk_count,
            CONVERT(NVARCHAR(4000), MIN(' + QUOTENAME(@pk_column) + N')) AS min_pk,
            CONVERT(NVARCHAR(4000), MAX(' + QUOTENAME(@pk_column) + N')) AS max_pk,
            @captured_at
        FROM ' + @qualified + N';';

    EXEC sp_executesql
        @sql,
        N'@run_id UNIQUEIDENTIFIER, @role NVARCHAR(20), @table_name NVARCHAR(256), @captured_at DATETIME2(3)',
        @run_id = @run_id,
        @role = @role,
        @table_name = @table_name,
        @captured_at = @captured_at;

    SET @sql = N'
        ;WITH bucketed AS (
            SELECT
                ABS(CHECKSUM(CONVERT(NVARCHAR(4000), ' + QUOTENAME(@pk_column) + N'))) % @bucket_modulus AS bucket_id,
                BINARY_CHECKSUM(*) AS row_checksum,
                CONVERT(NVARCHAR(4000), ' + QUOTENAME(@pk_column) + N') AS pk_value
            FROM ' + @qualified + N'
        )
        INSERT INTO recon.bucket_hash
        (
            run_id,
            role_name,
            table_name,
            bucket_id,
            row_count,
            bucket_checksum,
            min_pk,
            max_pk,
            captured_at
        )
        SELECT
            @run_id,
            @role,
            @table_name,
            bucket_id,
            COUNT_BIG(*) AS row_count,
            CHECKSUM_AGG(row_checksum) AS bucket_checksum,
            MIN(pk_value) AS min_pk,
            MAX(pk_value) AS max_pk,
            @captured_at
        FROM bucketed
        GROUP BY bucket_id;';

    EXEC sp_executesql
        @sql,
        N'@run_id UNIQUEIDENTIFIER, @role NVARCHAR(20), @table_name NVARCHAR(256), @captured_at DATETIME2(3), @bucket_modulus INT',
        @run_id = @run_id,
        @role = @role,
        @table_name = @table_name,
        @captured_at = @captured_at,
        @bucket_modulus = @bucket_modulus;

    FETCH NEXT FROM table_cursor INTO @table_name, @pk_column, @bucket_modulus;
END;

CLOSE table_cursor;
DEALLOCATE table_cursor;

DECLARE @rule_name NVARCHAR(200);
DECLARE @rule_table NVARCHAR(256);
DECLARE @rule_column NVARCHAR(128);
DECLARE @agg_fn NVARCHAR(10);
DECLARE @filter_predicate NVARCHAR(2000);
DECLARE @agg_value NVARCHAR(256);

DECLARE rule_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT rule_name, table_name, column_name, agg_fn, filter_predicate
    FROM @business_rules;

OPEN rule_cursor;
FETCH NEXT FROM rule_cursor INTO @rule_name, @rule_table, @rule_column, @agg_fn, @filter_predicate;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @schema_name = PARSENAME(@rule_table, 2);
    SET @object_name = PARSENAME(@rule_table, 1);

    IF @object_name IS NULL
    BEGIN
        SET @schema_name = 'dbo';
        SET @object_name = @rule_table;
    END;

    IF @schema_name IS NULL
    BEGIN
        SET @schema_name = 'dbo';
    END;

    SET @qualified = QUOTENAME(@schema_name) + '.' + QUOTENAME(@object_name);
    SET @agg_value = NULL;

    IF OBJECT_ID(@qualified, 'U') IS NOT NULL
    BEGIN
        SET @sql =
            CASE
                WHEN @agg_fn = 'SUM' THEN N'SELECT @out = CONVERT(NVARCHAR(256), SUM(CAST(' + QUOTENAME(@rule_column) + N' AS DECIMAL(38,6)))) FROM ' + @qualified + N' WHERE ' + @filter_predicate + N';'
                WHEN @agg_fn = 'MIN' THEN N'SELECT @out = CONVERT(NVARCHAR(256), MIN(CAST(' + QUOTENAME(@rule_column) + N' AS DECIMAL(38,6)))) FROM ' + @qualified + N' WHERE ' + @filter_predicate + N';'
                WHEN @agg_fn = 'MAX' THEN N'SELECT @out = CONVERT(NVARCHAR(256), MAX(CAST(' + QUOTENAME(@rule_column) + N' AS DECIMAL(38,6)))) FROM ' + @qualified + N' WHERE ' + @filter_predicate + N';'
                WHEN @agg_fn = 'COUNT' THEN N'SELECT @out = CONVERT(NVARCHAR(256), COUNT_BIG(*)) FROM ' + @qualified + N' WHERE ' + @filter_predicate + N';'
                ELSE N'SELECT @out = NULL;'
            END;

        BEGIN TRY
            EXEC sp_executesql @sql, N'@out NVARCHAR(256) OUTPUT', @out = @agg_value OUTPUT;
        END TRY
        BEGIN CATCH
            SET @agg_value = NULL;
            PRINT CONCAT('SKIP business rule failed: ', @rule_name, ' / ', @agg_fn, ' / ', ERROR_MESSAGE());
        END CATCH;
    END
    ELSE
    BEGIN
        PRINT CONCAT('SKIP business table not found: ', @qualified);
    END;

    INSERT INTO recon.business_profile (run_id, role_name, rule_name, agg_fn, agg_value, captured_at)
    VALUES (@run_id, @role, @rule_name, @agg_fn, @agg_value, @captured_at);

    FETCH NEXT FROM rule_cursor INTO @rule_name, @rule_table, @rule_column, @agg_fn, @filter_predicate;
END;

CLOSE rule_cursor;
DEALLOCATE rule_cursor;

PRINT '=== Snapshot Capture Complete ===';
SELECT * FROM recon.row_profile WHERE run_id = @run_id AND role_name = @role ORDER BY table_name;
SELECT TOP 100 * FROM recon.bucket_hash WHERE run_id = @run_id AND role_name = @role ORDER BY table_name, bucket_id;
SELECT * FROM recon.business_profile WHERE run_id = @run_id AND role_name = @role ORDER BY rule_name, agg_fn;

IF @role = 'TARGET' AND @linked_server IS NOT NULL AND @source_db IS NOT NULL
BEGIN
    PRINT '=== Source vs Target Comparison (Row Profile) ===';

    SET @sql = N'
        SELECT
            ISNULL(t.table_name, s.table_name) AS table_name,
            s.row_count AS source_row_count,
            t.row_count AS target_row_count,
            ISNULL(t.row_count, 0) - ISNULL(s.row_count, 0) AS row_count_diff,
            s.null_pk_count AS source_null_pk,
            t.null_pk_count AS target_null_pk,
            CASE
                WHEN s.table_name IS NULL OR t.table_name IS NULL THEN ''FAIL_MISSING_TABLE''
                WHEN ISNULL(t.row_count, -1) <> ISNULL(s.row_count, -1) THEN ''FAIL_ROW_COUNT''
                WHEN ISNULL(t.null_pk_count, -1) <> ISNULL(s.null_pk_count, -1) THEN ''FAIL_NULL_PK''
                ELSE ''PASS''
            END AS status
        FROM recon.row_profile t
        FULL OUTER JOIN [' + @linked_server + N'].[' + @source_db + N'].[recon].[row_profile] s
            ON s.run_id = t.run_id
           AND s.table_name = t.table_name
           AND s.role_name = ''SOURCE''
                WHERE
                        (t.run_id = @run_id AND t.role_name = ''TARGET'')
                        OR
                        (s.run_id = @run_id AND s.role_name = ''SOURCE'')
        ORDER BY table_name;';

    EXEC sp_executesql @sql, N'@run_id UNIQUEIDENTIFIER', @run_id = @run_id;

    PRINT '=== Source vs Target Comparison (Bucket Hash) ===';

    SET @sql = N'
        SELECT
            ISNULL(t.table_name, s.table_name) AS table_name,
            ISNULL(t.bucket_id, s.bucket_id) AS bucket_id,
            s.row_count AS source_bucket_rows,
            t.row_count AS target_bucket_rows,
            s.bucket_checksum AS source_bucket_checksum,
            t.bucket_checksum AS target_bucket_checksum,
            CASE
                WHEN s.table_name IS NULL OR t.table_name IS NULL THEN ''FAIL_MISSING_BUCKET''
                WHEN ISNULL(t.row_count, -1) <> ISNULL(s.row_count, -1) THEN ''FAIL_BUCKET_ROW_COUNT''
                WHEN ISNULL(t.bucket_checksum, -2147483648) <> ISNULL(s.bucket_checksum, -2147483648) THEN ''FAIL_BUCKET_HASH''
                ELSE ''PASS''
            END AS status
        FROM recon.bucket_hash t
        FULL OUTER JOIN [' + @linked_server + N'].[' + @source_db + N'].[recon].[bucket_hash] s
            ON s.run_id = t.run_id
           AND s.table_name = t.table_name
           AND s.bucket_id = t.bucket_id
           AND s.role_name = ''SOURCE''
                WHERE
                        (t.run_id = @run_id AND t.role_name = ''TARGET'')
                        OR
                        (s.run_id = @run_id AND s.role_name = ''SOURCE'')
        ORDER BY table_name, bucket_id;';

    EXEC sp_executesql @sql, N'@run_id UNIQUEIDENTIFIER', @run_id = @run_id;

    PRINT '=== Source vs Target Comparison (Business Aggregates) ===';

    SET @sql = N'
        SELECT
            ISNULL(t.rule_name, s.rule_name) AS rule_name,
            ISNULL(t.agg_fn, s.agg_fn) AS agg_fn,
            s.agg_value AS source_agg_value,
            t.agg_value AS target_agg_value,
            CASE
                WHEN s.rule_name IS NULL OR t.rule_name IS NULL THEN ''FAIL_MISSING_RULE''
                WHEN ISNULL(t.agg_value, ''<null>'') <> ISNULL(s.agg_value, ''<null>'') THEN ''FAIL_AGG_MISMATCH''
                ELSE ''PASS''
            END AS status
        FROM recon.business_profile t
        FULL OUTER JOIN [' + @linked_server + N'].[' + @source_db + N'].[recon].[business_profile] s
            ON s.run_id = t.run_id
           AND s.rule_name = t.rule_name
           AND s.agg_fn = t.agg_fn
           AND s.role_name = ''SOURCE''
                WHERE
                        (t.run_id = @run_id AND t.role_name = ''TARGET'')
                        OR
                        (s.run_id = @run_id AND s.role_name = ''SOURCE'')
        ORDER BY rule_name, agg_fn;';

    EXEC sp_executesql @sql, N'@run_id UNIQUEIDENTIFIER', @run_id = @run_id;
END
ELSE
BEGIN
    PRINT 'Comparison section skipped. Run with ROLE=TARGET and provide LINKED_SERVER + SOURCE_DB to compare.';
END;

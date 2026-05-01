-- SQL Server gap remediation template
-- Author: Nitish Anand Srivastava
-- Assumes linked server SOURCE_LINK and key scope table dbo.recon_gap_keys(key_id)

SET NOCOUNT ON;
BEGIN TRAN;

-- 1) Missing rows in target
INSERT INTO dbo.orders (id, status, total_amount, updated_at, is_deleted)
SELECT s.id, s.status, s.total_amount, s.updated_at, s.is_deleted
FROM [SOURCE_LINK].[SalesDB].[dbo].[orders] s
LEFT JOIN dbo.orders t ON t.id = s.id
WHERE t.id IS NULL
  AND s.id IN (SELECT key_id FROM dbo.recon_gap_keys);

-- 2) Extra rows in target
DELETE t
FROM dbo.orders t
WHERE t.id IN (SELECT key_id FROM dbo.recon_gap_keys)
  AND NOT EXISTS (
      SELECT 1 FROM [SOURCE_LINK].[SalesDB].[dbo].[orders] s WHERE s.id = t.id
  );

-- 3) Hash mismatch rows: targeted upsert via MERGE
MERGE dbo.orders AS t
USING (
    SELECT id, status, total_amount, updated_at, is_deleted
    FROM [SOURCE_LINK].[SalesDB].[dbo].[orders]
    WHERE id IN (SELECT key_id FROM dbo.recon_gap_keys)
) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    t.status = s.status,
    t.total_amount = s.total_amount,
    t.updated_at = s.updated_at,
    t.is_deleted = s.is_deleted
WHEN NOT MATCHED THEN
    INSERT (id, status, total_amount, updated_at, is_deleted)
    VALUES (s.id, s.status, s.total_amount, s.updated_at, s.is_deleted);

-- 4) Replay missed CDC operations from staging table
-- Expect staging table: dbo.cdc_delta_orders(op_type, id, status, total_amount, updated_at, is_deleted)
MERGE dbo.orders AS t
USING dbo.cdc_delta_orders AS d
ON t.id = d.id
WHEN MATCHED AND d.op_type IN ('U','I') THEN UPDATE SET
    t.status = d.status,
    t.total_amount = d.total_amount,
    t.updated_at = d.updated_at,
    t.is_deleted = d.is_deleted
WHEN NOT MATCHED BY TARGET AND d.op_type IN ('I','U') THEN
    INSERT (id, status, total_amount, updated_at, is_deleted)
    VALUES (d.id, d.status, d.total_amount, d.updated_at, d.is_deleted)
WHEN MATCHED AND d.op_type = 'D' THEN DELETE;

COMMIT TRAN;

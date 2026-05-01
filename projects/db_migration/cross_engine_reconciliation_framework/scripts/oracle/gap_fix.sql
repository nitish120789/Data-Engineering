-- Oracle gap remediation template
-- Author: Nitish Anand Srivastava
-- Assumes source access via DB link SOURCE_DB_LINK and staging keys in RECON_GAP_KEYS(key_id)

SET SERVEROUTPUT ON

-- 1) Missing rows in target: insert from source for scoped key range
INSERT /*+ APPEND */ INTO APP.ORDERS t
SELECT s.*
FROM APP.ORDERS@SOURCE_DB_LINK s
LEFT JOIN APP.ORDERS t2 ON t2.ID = s.ID
WHERE t2.ID IS NULL
  AND s.ID IN (SELECT key_id FROM RECON_GAP_KEYS);

-- 2) Extra rows in target: delete rows not present in source snapshot
DELETE FROM APP.ORDERS t
WHERE t.ID IN (SELECT key_id FROM RECON_GAP_KEYS)
  AND NOT EXISTS (
      SELECT 1 FROM APP.ORDERS@SOURCE_DB_LINK s WHERE s.ID = t.ID
  );

-- 3) Hash mismatch rows: targeted update from source for scoped keys
MERGE INTO APP.ORDERS t
USING (
    SELECT * FROM APP.ORDERS@SOURCE_DB_LINK
    WHERE ID IN (SELECT key_id FROM RECON_GAP_KEYS)
) s
ON (t.ID = s.ID)
WHEN MATCHED THEN UPDATE SET
    t.STATUS = s.STATUS,
    t.TOTAL_AMOUNT = s.TOTAL_AMOUNT,
    t.UPDATED_AT = s.UPDATED_AT,
    t.IS_DELETED = s.IS_DELETED;

-- 4) Replay missed updates/deletes from CDC staging (example)
-- Expect staging table: APP.CDC_DELTA_ORDERS(op_type, id, status, total_amount, updated_at, is_deleted)
MERGE INTO APP.ORDERS t
USING APP.CDC_DELTA_ORDERS d
ON (t.ID = d.ID)
WHEN MATCHED THEN UPDATE SET
    t.STATUS = d.STATUS,
    t.TOTAL_AMOUNT = d.TOTAL_AMOUNT,
    t.UPDATED_AT = d.UPDATED_AT,
    t.IS_DELETED = d.IS_DELETED
WHEN NOT MATCHED THEN
    INSERT (ID, STATUS, TOTAL_AMOUNT, UPDATED_AT, IS_DELETED)
    VALUES (d.ID, d.STATUS, d.TOTAL_AMOUNT, d.UPDATED_AT, d.IS_DELETED);

COMMIT;

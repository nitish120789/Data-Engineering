-- MySQL gap remediation template
-- Author: Nitish Anand Srivastava
-- Assumes key scope table: recon_gap_keys(key_id)
-- Assumes source data available via federated/staging table: source_orders_stage

START TRANSACTION;

-- 1) Missing rows in target
INSERT INTO orders (id, status, total_amount, updated_at, is_deleted)
SELECT s.id, s.status, s.total_amount, s.updated_at, s.is_deleted
FROM source_orders_stage s
LEFT JOIN orders t ON t.id = s.id
WHERE t.id IS NULL
  AND s.id IN (SELECT key_id FROM recon_gap_keys);

-- 2) Extra rows in target
DELETE t
FROM orders t
LEFT JOIN source_orders_stage s ON s.id = t.id
WHERE s.id IS NULL
  AND t.id IN (SELECT key_id FROM recon_gap_keys);

-- 3) Hash mismatch rows: targeted sync
UPDATE orders t
JOIN source_orders_stage s ON s.id = t.id
SET t.status = s.status,
    t.total_amount = s.total_amount,
    t.updated_at = s.updated_at,
    t.is_deleted = s.is_deleted
WHERE t.id IN (SELECT key_id FROM recon_gap_keys);

-- 4) Replay missed CDC operations
-- Expect staging: cdc_delta_orders(op_type,id,status,total_amount,updated_at,is_deleted)
INSERT INTO orders (id, status, total_amount, updated_at, is_deleted)
SELECT d.id, d.status, d.total_amount, d.updated_at, d.is_deleted
FROM cdc_delta_orders d
WHERE d.op_type IN ('I','U')
ON DUPLICATE KEY UPDATE
  status = VALUES(status),
  total_amount = VALUES(total_amount),
  updated_at = VALUES(updated_at),
  is_deleted = VALUES(is_deleted);

DELETE t
FROM orders t
JOIN cdc_delta_orders d ON d.id = t.id
WHERE d.op_type = 'D';

COMMIT;

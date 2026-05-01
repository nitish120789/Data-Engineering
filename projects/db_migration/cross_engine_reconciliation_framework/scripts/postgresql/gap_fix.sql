-- PostgreSQL gap remediation template
-- Author: Nitish Anand Srivastava
-- Assumes key scope table: recon_gap_keys(key_id)
-- Assumes source staging table: source_orders_stage

BEGIN;

-- 1) Missing rows in target
INSERT INTO public.orders (id, status, total_amount, updated_at, is_deleted)
SELECT s.id, s.status, s.total_amount, s.updated_at, s.is_deleted
FROM public.source_orders_stage s
LEFT JOIN public.orders t ON t.id = s.id
WHERE t.id IS NULL
  AND s.id IN (SELECT key_id FROM public.recon_gap_keys);

-- 2) Extra rows in target
DELETE FROM public.orders t
WHERE t.id IN (SELECT key_id FROM public.recon_gap_keys)
  AND NOT EXISTS (
      SELECT 1 FROM public.source_orders_stage s WHERE s.id = t.id
  );

-- 3) Hash mismatch rows: targeted upsert
INSERT INTO public.orders AS t (id, status, total_amount, updated_at, is_deleted)
SELECT s.id, s.status, s.total_amount, s.updated_at, s.is_deleted
FROM public.source_orders_stage s
WHERE s.id IN (SELECT key_id FROM public.recon_gap_keys)
ON CONFLICT (id) DO UPDATE
SET status = EXCLUDED.status,
    total_amount = EXCLUDED.total_amount,
    updated_at = EXCLUDED.updated_at,
    is_deleted = EXCLUDED.is_deleted;

-- 4) Replay missed CDC operations from staging
-- Expect staging: public.cdc_delta_orders(op_type,id,status,total_amount,updated_at,is_deleted)
INSERT INTO public.orders AS t (id, status, total_amount, updated_at, is_deleted)
SELECT d.id, d.status, d.total_amount, d.updated_at, d.is_deleted
FROM public.cdc_delta_orders d
WHERE d.op_type IN ('I','U')
ON CONFLICT (id) DO UPDATE
SET status = EXCLUDED.status,
    total_amount = EXCLUDED.total_amount,
    updated_at = EXCLUDED.updated_at,
    is_deleted = EXCLUDED.is_deleted;

DELETE FROM public.orders t
USING public.cdc_delta_orders d
WHERE d.op_type = 'D'
  AND t.id = d.id;

COMMIT;

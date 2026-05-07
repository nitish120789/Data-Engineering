-- Sequence reseed template for Aurora PostgreSQL
-- Author: Nitish Anand Srivastava

-- Replace sample objects with application-specific sequence ownership mappings.

SELECT setval('public.customer_id_seq', COALESCE((SELECT MAX(customer_id) FROM public.customers), 0) + 1, false);
SELECT setval('public.order_id_seq', COALESCE((SELECT MAX(order_id) FROM public.orders), 0) + 1, false);

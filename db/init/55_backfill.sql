CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO sanitized.customer AS sc(
  customer_id, store_id, first_name, last_name, email,
  address_id, activebool, create_date, last_update
)
SELECT
  c.customer_id,
  c.store_id,
  'fn_' || substr(encode(hmac(lower(coalesce(c.first_name,''))::bytea, 'demo-secret'::bytea, 'sha256'),'hex'),1,12),
  'ln_' || substr(encode(hmac(lower(coalesce(c.last_name ,''))::bytea, 'demo-secret'::bytea, 'sha256'),'hex'),1,12),
  'id_' ||       encode(hmac(lower(coalesce(c.email     ,''))::bytea, 'demo-secret'::bytea, 'sha256'),'hex'),
  c.address_id,
  c.activebool,
  c.create_date,
  NOW()
FROM public.customer c
ON CONFLICT (customer_id) DO UPDATE
  SET first_name = EXCLUDED.first_name,
      last_name  = EXCLUDED.last_name,
      email      = EXCLUDED.email,
      address_id = EXCLUDED.address_id,
      activebool = EXCLUDED.activebool,
      create_date= EXCLUDED.create_date,
      last_update= NOW();

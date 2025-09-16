CREATE SCHEMA IF NOT EXISTS sanitized;

DROP TABLE IF EXISTS sanitized.customer;
CREATE TABLE sanitized.customer (
  LIKE public.customer INCLUDING DEFAULTS INCLUDING CONSTRAINTS
);

-- Ensure ON CONFLICT works forever:
ALTER TABLE sanitized.customer
  ADD CONSTRAINT sanitized_customer_pkey PRIMARY KEY (customer_id);

CREATE INDEX IF NOT EXISTS ix_sanitized_customer_id ON sanitized.customer (customer_id);

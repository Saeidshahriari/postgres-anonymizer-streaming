CREATE OR REPLACE FUNCTION sanitized.write_customer_sanitized()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  tok_email TEXT;
  tok_first TEXT;
  tok_last  TEXT;
  k TEXT := coalesce(current_setting('app.hmac_key', true), 'demo-secret'); -- fallback
BEGIN
  tok_email := 'id_' || encode(hmac(lower(coalesce(NEW.email,''))::bytea, k::bytea, 'sha256'),'hex');
  tok_first := 'fn_' || substr(encode(hmac(lower(coalesce(NEW.first_name,''))::bytea, k::bytea, 'sha256'),'hex'),1,12);
  tok_last  := 'ln_' || substr(encode(hmac(lower(coalesce(NEW.last_name ,''))::bytea, k::bytea, 'sha256'),'hex'),1,12);

  INSERT INTO sanitized.customer AS sc(
    customer_id, store_id, first_name, last_name, email,
    address_id, activebool, create_date, last_update
  )
  VALUES (
    NEW.customer_id, NEW.store_id, tok_first, tok_last, tok_email,
    NEW.address_id, NEW.activebool, NEW.create_date, NOW()
  )
  ON CONFLICT (customer_id) DO UPDATE
    SET first_name = EXCLUDED.first_name,
        last_name  = EXCLUDED.last_name,
        email      = EXCLUDED.email,
        address_id = EXCLUDED.address_id,
        activebool = EXCLUDED.activebool,
        create_date= EXCLUDED.create_date,
        last_update= NOW();

  RETURN NEW;
END
$$;

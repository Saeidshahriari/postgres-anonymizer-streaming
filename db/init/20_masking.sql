-- Turn on dynamic masking engine
SELECT anon.start_dynamic_masking();

-- Masking rules on Pagila tables (examples)
SECURITY LABEL FOR anon ON COLUMN customer.first_name
  IS 'MASKED WITH FUNCTION anon.fake_first_name()';

SECURITY LABEL FOR anon ON COLUMN customer.last_name
  IS 'MASKED WITH FUNCTION anon.fake_last_name()';

SECURITY LABEL FOR anon ON COLUMN customer.email
  IS 'MASKED WITH FUNCTION anon.pseudo_email(email)';

-- Optional: blur dates +/- up to 90 days (example)
-- SECURITY LABEL FOR anon ON COLUMN payment.payment_date
--   IS 'MASKED WITH FUNCTION anon.random_date(payment_date, INTERVAL ''-90 days'', INTERVAL ''+90 days'')';

-- A downstream reader that sees only anonymized data
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consumer') THEN
    CREATE ROLE consumer LOGIN PASSWORD 'consumer';
  END IF;
END$$;

GRANT USAGE ON SCHEMA sanitized TO consumer;
GRANT SELECT ON ALL TABLES IN SCHEMA sanitized TO consumer;
ALTER DEFAULT PRIVILEGES IN SCHEMA sanitized GRANT SELECT ON TABLES TO consumer;

-- (Optional) Ensure consumer has NO access to raw public tables:
REVOKE ALL ON SCHEMA public FROM consumer;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM consumer;

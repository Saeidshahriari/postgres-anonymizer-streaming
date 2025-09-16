-- Role that must see only masked values
CREATE ROLE analyst LOGIN PASSWORD 'secret';
SECURITY LABEL FOR anon ON ROLE analyst IS 'MASKED';

-- Minimal read access
GRANT USAGE ON SCHEMA public TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analyst;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO analyst;

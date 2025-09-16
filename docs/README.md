# PostgreSQL Anonymizer Starter (Dynamic + Static)

A reproducible, Dockerized demo of [PostgreSQL Anonymizer](https://postgresql-anonymizer.readthedocs.io/) showing:
- **Dynamic masking**: masked roles see obfuscated values in real time.
- **Static anonymization**: irreversible transforms before sharing data.

Uses the **Pagila** sample DB plus Python/Rust generators.

## Architecture

- **Postgres + anon** (container) ← mounts `db/init/` and runs init scripts once.
- **Dynamic masking rules** via `SECURITY LABEL ... IS 'MASKED WITH FUNCTION ...'`.
- **Masked roles** (e.g., `analyst`) see fake/pseudo/partial values.
- **Static anonymization** (optional) rewrites data irreversibly prior to export.

## Quickstart

```bash
# 1) Bring up the DB
docker compose up -d
docker compose logs -f db  # wait until healthy

# 2) Verify masking: admin vs analyst
docker exec -it anon_db psql -U postgres -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"

docker exec -it anon_db psql -U analyst -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"

# 3) (Optional) Generate live data with Python
python -m venv venv && source venv/bin/activate
pip install -r app/requirements.txt
cp .env.example .env
python app/faker_loader.py

# 4) (Optional) Rust demo
cd app_rust && cargo run
```

### Pagila sample database (provenance & setup)

This demo uses the Pagila sample database. We download the official schema and data SQL files and place them under `db/init/` so the Postgres entrypoint runs them automatically:

- `db/init/11_pagila_schema.sql` – Pagila schema  
- `db/init/12_pagila_data.sql` – Pagila data

**Provenance (source):**
- Pagila schema & data are fetched from the public GitHub mirror by @devrimgunduz:
  - https://github.com/devrimgunduz/pagila/blob/master/pagila-schema.sql
  - https://github.com/devrimgunduz/pagila/blob/master/pagila-data.sql

We intentionally avoid downloading inside the container because the anonymizer image does not include `curl` by default. Instead, we fetch the files locally and let Docker mount them into `/docker-entrypoint-initdb.d`.
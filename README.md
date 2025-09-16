# PostgreSQL Anonymizer Starter
**Dynamic masking + Real-time streaming (triggers) + Static anonymization**  
_No Kafka/Flink. EU/GDPR-friendly demo._

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-informational)
![License](https://img.shields.io/badge/license-MIT-green)

This repository demonstrates **privacy-by-design** patterns for PostgreSQL:

- **Dynamic masking** — roles marked as `MASKED` see obfuscated values on raw tables (e.g., `public.customer`) **at read time**.
- **Real-time streaming anonymization** — **triggers** maintain a live, anonymized replica in the **`sanitized`** schema using **deterministic HMAC tokens** (great for downstream consumers and sharing).
- **Static anonymization** — one-shot irreversible transforms for safe dumps/hand-offs.

> Works fully inside Postgres (no external brokers). Designed for **EU/GDPR** contexts: keep raw PII confined to `public.*`, share only `sanitized.*` or masked views, and anonymize exports before they leave your perimeter.

---

## Table of contents
- [Architecture](#architecture)
- [Folder layout](#folder-layout)
- [Quickstart](#quickstart)
- [Real-time streaming (triggers)](#real-time-streaming-triggers)
- [Static anonymization & dumps](#static-anonymization--dumps)
- [Configuration & security](#configuration--security)
- [Troubleshooting](#troubleshooting)
- [Inspiration & references](#inspiration--references)
- [License](#license)

---

## Architecture

public.* (raw PII) --(dynamic masking at read)--> masked roles (analyst)

public.customer --(AFTER INSERT/UPDATE triggers)--> sanitized.customer (HMAC tokens)
|
+--> consumers read sanitized.* in real time

[optional] Static anonymization (irreversible) --> safe dump for external sharing


- **Dynamic masking** is enabled via `SECURITY LABEL ... IS 'MASKED WITH FUNCTION ...'` and a `MASKED` role (e.g., `analyst`).
- **Streaming anonymization** is implemented with:
  - `sanitized` schema + `sanitized.customer` (PK on `customer_id`),
  - a trigger function that HMAC-tokenizes sensitive fields,
  - insert/update triggers on `public.customer`,
  - a read-only `consumer` role limited to `sanitized.*`.

---

## Folder layout

.
├─ docker-compose.yml
├─ .gitignore / .gitattributes / .env.example
├─ db/
│ └─ init/
│ ├─ 00_init.sql # enable & init anonymizer extension
│ ├─ 11_pagila_schema.sql # Pagila schema (downloaded)
│ ├─ 12_pagila_data.sql # Pagila data (downloaded)
│ ├─ 20_masking.sql # dynamic masking rules
│ ├─ 25_leads.sql # optional (Rust demo table)
│ ├─ 30_roles.sql # roles: analyst (MASKED)
│ ├─ 40_static_demo.sql # static anonymization (commented)
│ ├─ 50_sanitized_schema.sql # sanitized schema + PK(customer_id)
│ ├─ 51_transform_fn.sql # trigger function (HMAC via app.hmac_key)
│ ├─ 52_triggers.sql # AFTER INSERT/UPDATE triggers
│ ├─ 53_consumer_role.sql # consumer role (read-only on sanitized)
│ └─ 55_backfill.sql # one-time backfill into sanitized.customer
├─ app/
│ ├─ requirements.txt
│ └─ faker_loader.py # live inserts/updates to exercise pipeline
├─ app_rust/ # optional
│ ├─ Cargo.toml
│ └─ src/main.rs
└─ tests/
└─ test_masked_visibility.sql

---

## Quickstart

### 0) Prereqs
- Docker Desktop / Docker Compose v2  
- Optional: Python 3.11+ (for `app/faker_loader.py`) and Rust toolchain (`app_rust/`)

### 1) Configure ports
By default the DB is exposed on **5432**.  
If 5432 is busy on your host, change the mapping to `5433:5432` in `docker-compose.yml` and use **port 5433** in your local DSNs.

# docker-compose.yml
services:
  db:
    image: registry.gitlab.com/dalibo/postgresql_anonymizer:stable
    ports:
      - "5432:5432"   # or "5433:5432" if 5432 is occupied on host

2) Bring up the DB
docker compose up -d
docker compose logs -f db   # wait for "ready to accept connections"
3) Verify dynamic masking

# admin (unmasked)
docker exec -it anon_db psql -U postgres -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"

# analyst (MASKED role) – sees obfuscated values
docker exec -it anon_db psql -U analyst  -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"

4) Initialize streaming & backfill
The init scripts already created the sanitized schema, PK, triggers, and consumer role.
Backfill existing rows once:


docker exec -i anon_db psql -U postgres -d demo -f /docker-entrypoint-initdb.d/55_backfill.sql
Check the sanitized copy:

docker exec -it anon_db psql -U consumer -d demo \
  -c "SELECT customer_id, first_name, last_name, email, last_update
      FROM sanitized.customer ORDER BY last_update DESC LIMIT 10;"

5) Generate live data (optional)
python -m venv venv && source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r app/requirements.txt
cp .env.example .env

# Choose the port you exposed:
# DB_DSN=host=localhost port=5432 dbname=demo user=postgres password=postgres
# or
# DB_DSN=host=localhost port=5433 dbname=demo user=postgres password=postgres

python app/faker_loader.py
Watch sanitized stream update in real time:


docker exec -it anon_db psql -U consumer -d demo \
  -c "SELECT customer_id, first_name, last_name, email, last_update
      FROM sanitized.customer ORDER BY last_update DESC LIMIT 10;"

Real-time streaming (triggers)
db/init/50_sanitized_schema.sql creates sanitized.customer with a PRIMARY KEY on customer_id to allow ON CONFLICT ... DO UPDATE.

db/init/51_transform_fn.sql defines sanitized.write_customer_sanitized() which:

builds deterministic HMAC tokens for first_name, last_name, email,

upserts into sanitized.customer with ON CONFLICT (customer_id).

db/init/52_triggers.sql attaches AFTER INSERT/UPDATE triggers on public.customer.

db/init/53_consumer_role.sql grants read-only access to sanitized.* for the consumer role (and revokes public.*).

Deterministic tokens (HMAC) let downstream tables join on identifiers without exposing real PII.
For true anonymization (irreversible, non-linkable), switch to non-deterministic replacements or drop identifiers in sanitized.*.

Static anonymization & dumps
Masked-role dump (masking applied at read time)


docker exec -it anon_db psql -U postgres -d demo -c "CREATE ROLE anon_dumper LOGIN PASSWORD 'dump';"
docker exec -it anon_db psql -U postgres -d demo -c "SECURITY LABEL FOR anon ON ROLE anon_dumper IS 'MASKED';"
docker exec -it anon_db psql -U postgres -d demo -c "GRANT pg_read_all_data TO anon_dumper;"

docker exec -it anon_db pg_dump -U anon_dumper --no-security-labels demo > demo_anonymized.sql.dump
Static anonymization (irreversible), then dump


docker exec -it anon_db psql -U postgres -d demo -c "SELECT anon.anonymize_table('customer');"
docker exec -it anon_db pg_dump -U postgres demo > demo_static_anonymized.sql.dump
Configuration & security
HMAC secret (tokens)
The trigger function reads a config key app.hmac_key. Set/rotate it (use a long random value):


docker exec -it anon_db psql -U postgres -d demo \
  -c "ALTER SYSTEM SET app.hmac_key = 'replace-with-a-long-random-secret'; SELECT pg_reload_conf();"
Keep the secret out of SQL bodies and backups.

Store secrets in your orchestrator (Docker/K8s secrets, Vault, etc.).


Inspiration & references

PostgreSQL Anonymizer (Neon fork) — https://github.com/neondatabase/postgresql_anonymizer
Official docs — https://postgresql-anonymizer.readthedocs.io/
Pagila — https://github.com/devrimgunduz/pagila
Psycopg 3 — https://www.psycopg.org/psycopg3/docs/
Faker — https://faker.readthedocs.io/
tokio-postgres — https://docs.rs/tokio-postgres/latest/tokio_postgres/
GDPR Art. 25 — https://eur-lex.europa.eu/eli/reg/2016/679/oj

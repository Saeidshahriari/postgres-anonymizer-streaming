# PostgreSQL Anonymizer Streaming

**Dynamic masking + Real‑time anonymized streaming (triggers + sanitized schema) + Static anonymization**  
_No Kafka / No Flink. EU/GDPR‑friendly demo._

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-blue)](#)
[![Docker](https://img.shields.io/badge/Docker-Compose-informational)](#)
[![Python](https://img.shields.io/badge/Python-3.12.x-blue)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

This repository demonstrates privacy‑by‑design patterns **entirely inside PostgreSQL**:

- **Dynamic masking** – roles labeled `MASKED` see obfuscated values at **read time** on raw tables (e.g., `public.customer`).  
- **Real‑time anonymized streaming** – **AFTER INSERT/UPDATE** triggers write a live, anonymized copy into the **`sanitized`** schema using **deterministic HMAC tokens**. Consumers read only `sanitized.*`.  
- **Static anonymization** – one‑shot irreversible transforms before exporting a dataset (safe hand‑offs).

> **Why (EU/GDPR)?** Keep raw PII confined to `public.*`. Grant analytics/QA/vendors access only to `sanitized.*` (or masked views). Anonymize exports before they leave your perimeter.

---

## Table of Contents

- [Architecture](#architecture)
- [Folder Layout](#folder-layout)
- [Quickstart](#quickstart)
- [How It Works](#how-it-works)
- [Static Anonymization & Dumps](#static-anonymization--dumps)
- [Configuration & Security](#configuration--security)
- [Troubleshooting](#troubleshooting)
- [Inspiration & References](#inspiration--references)
- [License](#license)

---

## Architecture

```text
public.* (raw PII) ──(dynamic masking at read)──► masked roles (e.g., analyst)

public.customer ──(AFTER INSERT/UPDATE triggers)──► sanitized.customer (HMAC tokens)
                                           │
                                           └──► downstream consumers read sanitized.* only

[optional] Static anonymization (irreversible) ──► safe export for external sharing
```

- Tokens are **deterministic HMACs** (config‑keyed) → enable safe joins across sanitized tables.  
- For true anonymization (non‑linkable), prefer non‑deterministic replacements or drop identifiers in `sanitized.*`.

---

## Folder Layout

> The tree below matches the recommended structure. If your repo currently uses `test/`, either rename it to `tests/` or update the README accordingly.

```
.
├─ docker-compose.yml
├─ .gitignore / .gitattributes / .env.example
├─ db/
│  └─ init/
│     ├─ 00_init.sql                 # enable & init anonymizer extension
│     ├─ 11_pagila_schema.sql        # Pagila schema   (downloaded)
│     ├─ 12_pagila_data.sql          # Pagila data     (downloaded)
│     ├─ 20_masking.sql              # dynamic masking rules (read-time)
│     ├─ 30_roles.sql                # roles: analyst (MASKED), etc.
│     ├─ 40_static_demo.sql          # static anonymization (optional)
│     ├─ 50_sanitized_schema.sql     # sanitized schema + PRIMARY KEY(customer_id)
│     ├─ 51_transform_fn.sql         # trigger fn using app.hmac_key (HMAC tokens)
│     ├─ 52_triggers.sql             # AFTER INSERT/UPDATE triggers on public.customer
│     ├─ 53_consumer_role.sql        # read-only role for sanitized.*
│     └─ 55_backfill.sql             # one-time backfill into sanitized.customer
├─ app/
│  ├─ requirements.txt
│  └─ faker_loader.py                # generates inserts/updates for live pipeline
├─ app_rust/                         # optional
│  ├─ Cargo.toml
│  └─ src/main.rs
└─ tests/
   └─ test_masked_visibility.sql
```

---

## Quickstart

### 0) Prerequisites

- Docker Desktop / Docker Compose v2  
- Optional: Python 3.11+ (for `app/faker_loader.py`) and Rust toolchain (for `app_rust/`).

### 1) Configure Ports

By default the DB is exposed on **5432**. If your host already uses 5432, change the mapping to `5433:5432` and use **port 5433** in local connections.

```yaml
# docker-compose.yml
services:
  db:
    image: registry.gitlab.com/dalibo/postgresql_anonymizer:stable
    ports:
      - "5432:5432"   # or "5433:5432" if 5432 is occupied on host
```

### 2) Bring Up the Database

```bash
docker compose up -d
docker compose logs -f db     # wait for "database system is ready to accept connections"
```

### 3) Verify Dynamic Masking

```bash
# admin (unmasked)
docker exec -it anon_db psql -U postgres -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"

# analyst (MASKED role) – will see obfuscated values
docker exec -it anon_db psql -U analyst -d demo \
  -c "SELECT customer_id, first_name, last_name, email FROM customer LIMIT 5;"
```

### 4) Initialize Streaming & Backfill

The init scripts create the sanitized schema, triggers, PK and roles. Backfill existing rows once:

```bash
docker exec -i anon_db psql -U postgres -d demo -f /docker-entrypoint-initdb.d/55_backfill.sql
```

Check the sanitized copy:

```bash
docker exec -it anon_db psql -U consumer -d demo \
  -c "SELECT customer_id, first_name, last_name, email, last_update
      FROM sanitized.customer
      ORDER BY last_update DESC
      LIMIT 10;"
```

### 5) Generate Live Data (optional)

```bash
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r app/requirements.txt
cp .env.example .env

# choose the port you exposed:
# DB_DSN=host=localhost port=5432 dbname=demo user=postgres password=postgres
# or
# DB_DSN=host=localhost port=5433 dbname=demo user=postgres password=postgres

python app/faker_loader.py
```

Observe updates flow into `sanitized.customer`:

```bash
docker exec -it anon_db psql -U consumer -d demo \
  -c "SELECT customer_id, first_name, last_name, email, last_update
      FROM sanitized.customer
      ORDER BY last_update DESC
      LIMIT 10;"
```

---

## How It Works

- **Sanitized schema** (`db/init/50_sanitized_schema.sql`): creates `sanitized.customer` with **PRIMARY KEY (customer_id)** so the trigger can **UPSERT** via `ON CONFLICT`.
- **Trigger function** (`db/init/51_transform_fn.sql`): computes deterministic HMAC tokens using the Postgres config key `app.hmac_key`, then UPSERTs into `sanitized.customer`.
- **Triggers** (`db/init/52_triggers.sql`): `AFTER INSERT` and `AFTER UPDATE` on `public.customer` call the function.
- **Consumer role** (`db/init/53_consumer_role.sql`): grants read‑only on `sanitized.*`, revokes access to `public.*`.

**Rotate HMAC key** (without editing SQL bodies):

```bash
docker exec -it anon_db psql -U postgres -d demo \
  -c "ALTER SYSTEM SET app.hmac_key = 'replace-with-a-long-random-secret'; SELECT pg_reload_conf();"
```

---

## Static Anonymization & Dumps

- **Masked‑role dump** (masking at read time):

```bash
docker exec -it anon_db psql -U postgres -d demo -c "CREATE ROLE anon_dumper LOGIN PASSWORD 'dump';"
docker exec -it anon_db psql -U postgres -d demo -c "SECURITY LABEL FOR anon ON ROLE anon_dumper IS 'MASKED';"
docker exec -it anon_db psql -U postgres -d demo -c "GRANT pg_read_all_data TO anon_dumper;"
docker exec -it anon_db pg_dump -U anon_dumper --no-security-labels demo > demo_anonymized.sql.dump
```

- **Static anonymization** (irreversible), then dump:

```bash
docker exec -it anon_db psql -U postgres -d demo -c "SELECT anon.anonymize_table('customer');"
docker exec -it anon_db pg_dump -U postgres demo > demo_static_anonymized.sql.dump
```

---

## Configuration & Security

- **Secrets**: store `app.hmac_key` via `ALTER SYSTEM SET` (or environment / secrets manager). Do **not** hardcode secrets in SQL.  
- **Ports**: container is always `5432`. If host maps `5433:5432`, use `port=5433` in local DSNs.  
- **Access control**: only admins can read `public.*`. Downstream users/BI tools connect as `consumer` to read `sanitized.*`.

---

## Troubleshooting

- **Port 5432 in use** → map to `5433:5432` and use `port=5433` locally.  
- **`(0 rows)` in `sanitized.customer`** → run the backfill once and/or perform a new `INSERT`/`UPDATE`.  
- **`there is no unique or exclusion constraint matching the ON CONFLICT specification`** → ensure the **PRIMARY KEY** exists on `sanitized.customer(customer_id)`.  
- **Auth errors** → default creds come from `docker-compose.yml` (`postgres/postgres`). If you changed them after first start, either keep the original password or recreate volumes (`docker compose down -v`).

---

## Optional: Rust Mini-Consumer

> You **don’t need Rust** to run this project. This client is optional and only demonstrates how a typed consumer could read from `sanitized.customer`.

### Prerequisites

- Install Rust toolchain: https://rustup.rs

### Configure & Run

```bash
cd app_rust
# If your host port is 5433, adjust the DSN accordingly:
export RUST_DB_DSN="host=localhost port=5432 dbname=demo user=consumer password=consumer"
cargo run
```

### What it does

- Connects using the `RUST_DB_DSN` connection string
- Every 2 seconds prints the latest 5 rows from `sanitized.customer`

> If you’re not using Rust at all, either keep `app_rust/` as an example or remove the folder to keep the repo minimal.


## Why Rust in this repo?

> Rust is **optional** here. The core anonymization pipeline runs fully inside PostgreSQL (dynamic masking + triggers → `sanitized.*`).  
> We include a tiny **Rust mini-consumer** only to show how a production-grade client could read from `sanitized.*` safely and efficiently.

### Goals

- **Separation of concerns**: Raw PII stays in `public.*` inside the DB. The Rust client connects as the low-privileged `consumer` role and reads **only** `sanitized.*`. This mirrors a real-world downstream service in EU/GDPR contexts.
- **Demonstrate a typed, safe consumer**: Rust’s strong typing helps encode domain contracts at compile-time (e.g., schema → struct mapping) and fail fast if queries drift.
- **Reliability & performance**: For long-running daemons (streams, pollers, push-servers), Rust gives low-latency I/O with `tokio`, predictable memory usage, and no GC pauses.
- **Small deployable artifacts**: Single static binary → tiny Docker image; easy to run in constrained environments.
- **Security posture**: Memory safety by design, minimal runtime surface, and easy to add TLS/mTLS later if you expose a network service that forwards sanitized events.

### When would you use Rust (vs Python) here?

- If you need a **long-running** microservice consuming `sanitized.*` and forwarding data to BI, cache, or message bus with **low latency** and **minimal resource usage**, Rust shines.
- If you’re just doing **quick seeding / scripting**, Python is faster to iterate. That’s why this repo uses Python (Faker) for synthetic writes and **Rust only as an optional consumer**.

### What the Rust example does (in `app_rust/`)

- Connects with `RUST_DB_DSN` as `consumer`.
- Every 2 seconds reads the latest 5 rows from `sanitized.customer` and prints them.
- Touches **only** the sanitized schema (no access to `public.*`), reinforcing the privacy boundary.

> If your project doesn’t need a compiled consumer, you can remove `app_rust/` and keep the README section noting that downstream systems should read `sanitized.*` using the least-privilege role.

---

## Inspiration & References

- CipherMQ — inspiration for documentation structure and secure transport ideas (no code copied).  
  https://github.com/fozouni/CipherMQ

- PostgreSQL Anonymizer (Neon fork) — masking methods and repo layout inspiration.  
  https://github.com/neondatabase/postgresql_anonymizer

- PostgreSQL Anonymizer (official docs): https://postgresql-anonymizer.readthedocs.io/  
- Pagila: https://github.com/devrimgunduz/pagila  
- Psycopg 3: https://www.psycopg.org/psycopg3/docs/  
- Faker: https://faker.readthedocs.io/  
- tokio-postgres: https://docs.rs/tokio-postgres/latest/tokio_postgres/  
- GDPR Art. 25 “Data protection by design”: https://eur-lex.europa.eu/eli/reg/2016/679/oj

---

## License

Released under the **MIT License**. See `LICENSE`.

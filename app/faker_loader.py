"""
Faker-driven data generator for Pagila.customer
- Inserts or updates rows to exercise dynamic masking.
Provenance: authored for this repo; uses psycopg3 + Faker per their docs.
"""

import os, time, random
from faker import Faker
import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

load_dotenv()
DB_DSN = os.getenv("DB_DSN", "host=localhost port=5432 dbname=demo user=postgres password=159357")
fake = Faker()

def random_address_id(conn):
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT address_id FROM address ORDER BY random() LIMIT 1;")
        row = cur.fetchone()
        return row["address_id"]

def maybe_update_customer(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT customer_id FROM customer ORDER BY random() LIMIT 1;")
        cid = cur.fetchone()[0]
        new_email = fake.email()
        cur.execute("UPDATE customer SET email=%s, last_update=NOW() WHERE customer_id=%s;", (new_email, cid))

def insert_customer(conn):
    addr_id = random_address_id(conn)
    first = fake.first_name()
    last  = fake.last_name()
    email = fake.email()
    store_id = random.choice([1,2])
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, create_date, last_update)
            VALUES (%s,%s,%s,%s,%s,true,CURRENT_DATE,NOW())
            RETURNING customer_id;
        """, (store_id, first, last, email, addr_id))
        return cur.fetchone()[0]

def main():
    with psycopg.connect(DB_DSN, autocommit=True) as conn:
        while True:
            if random.random() < 0.6:
                cid = insert_customer(conn)
                print(f"Inserted customer {cid}")
            else:
                maybe_update_customer(conn)
                print("Updated a customer")
            time.sleep(random.uniform(0.3, 1.2))

if __name__ == "__main__":
    main()

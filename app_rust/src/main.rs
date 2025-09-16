//! Minimal async Rust loader that inserts sample rows into `leads`.
//! Provenance: authored for this repo; API usage based on tokio-postgres docs.

use tokio_postgres::NoTls;
use fake::faker::name::en::{FirstName, LastName};
use fake::faker::internet::en::SafeEmail;
use fake::Fake;
use rand::Rng;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (client, connection) = tokio_postgres::connect(
        "host=localhost port=5433 dbname=demo user=postgres password=postgres",
        NoTls
    ).await?;

    // Drive the connection on a separate task
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });

    // Insert 10 fake leads
    for _ in 0..10 {
        let first: String = FirstName().fake();
        let last: String  = LastName().fake();
        let email: String = SafeEmail().fake();
        let phone: String = format!("+3247{:06}", rand::thread_rng().gen_range(100000..999999));
        let full_name = format!("{} {}", first, last);

        client.execute(
            "INSERT INTO leads(full_name, email, phone) VALUES ($1,$2,$3)",
            &[&full_name, &email, &phone]
        ).await?;
    }

    println!("Inserted 10 leads.");
    Ok(())
}

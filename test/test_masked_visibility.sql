-- Run as role 'analyst'. Should not expose real emails.
SELECT COUNT(*) AS masked_emails
FROM customer
WHERE email ~ '^[^@]+@[^@]+$';

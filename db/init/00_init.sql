-- Enable anon library and initialize the extension
ALTER DATABASE demo SET session_preload_libraries = 'anon';
CREATE EXTENSION IF NOT EXISTS anon CASCADE;
SELECT anon.init();

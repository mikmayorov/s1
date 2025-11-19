create role s1api login encrypted password 'password';
GRANT CONNECT ON DATABASE b TO s1api;
GRANT USAGE ON SCHEMA public TO s1api;

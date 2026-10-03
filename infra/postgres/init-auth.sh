#!/bin/sh
# Only Docker's freshly created, explicitly dev database calls this initializer.
set -eu
case "$AUTH_PARTY" in c|v) ;; *) exit 1 ;; esac
psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
 -v party="$AUTH_PARTY" -v db="$POSTGRES_DB" -v migrator_password="$AUTH_MIGRATOR_PASSWORD" \
 -v runtime_password="$AUTH_RUNTIME_PASSWORD" >/dev/null <<'SQL'
SELECT format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', 'hnuhole_' || :'party' || '_owner') \gexec
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', 'hnuhole_' || :'party' || '_migrator', :'migrator_password') \gexec
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', 'hnuhole_' || :'party' || '_runtime', :'runtime_password') \gexec
SELECT format('GRANT %I TO %I', 'hnuhole_' || :'party' || '_owner', 'hnuhole_' || :'party' || '_migrator') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db', 'hnuhole_' || :'party' || '_owner') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I,%I', :'db', 'hnuhole_' || :'party' || '_migrator', 'hnuhole_' || :'party' || '_runtime') \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
if [ "$AUTH_PARTY" = c ]; then
 psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v db="$POSTGRES_DB" -v recovery_password="$AUTH_RECOVERY_PASSWORD" >/dev/null <<'SQL'
CREATE ROLE hnuhole_c_recovery LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD :'recovery_password';
CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
SELECT format('GRANT CONNECT ON DATABASE %I TO hnuhole_c_recovery', :'db') \gexec
SQL
fi

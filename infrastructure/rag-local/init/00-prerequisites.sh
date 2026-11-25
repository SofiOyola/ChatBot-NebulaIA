#!/usr/bin/env bash
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=authenticator_password="$RAG_LOCAL_AUTHENTICATOR_PASSWORD" <<'SQL'
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE authenticator LOGIN PASSWORD :'authenticator_password' NOINHERIT;
GRANT anon, authenticated TO authenticator;
CREATE SCHEMA extensions;
CREATE EXTENSION vector WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions TO anon, authenticated;
SQL

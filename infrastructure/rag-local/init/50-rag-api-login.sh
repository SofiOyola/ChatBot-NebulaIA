#!/usr/bin/env bash
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=api_password="$RAG_LOCAL_API_PASSWORD" <<'SQL'
CREATE ROLE nebula_rag_api_login LOGIN PASSWORD :'api_password' INHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT nebula_rag_api TO nebula_rag_api_login;
SQL

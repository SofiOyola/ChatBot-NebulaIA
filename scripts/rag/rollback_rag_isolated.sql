\set ON_ERROR_STOP on
BEGIN;
DO $membership$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api_login') AND
     EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api') THEN
    REVOKE nebula_rag_api FROM nebula_rag_api_login;
  END IF;
END;
$membership$;
DROP FUNCTION IF EXISTS public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real);
DROP FUNCTION IF EXISTS public.nebula_search_academic_chunks(extensions.vector,text,integer,real);
DROP SCHEMA IF EXISTS rag CASCADE;
DO $roles$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api_login') THEN DROP ROLE nebula_rag_api_login; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api') THEN
    REVOKE ALL ON SCHEMA public, extensions FROM nebula_rag_api;
    DROP ROLE nebula_rag_api;
  END IF;
END;
$roles$;
COMMIT;

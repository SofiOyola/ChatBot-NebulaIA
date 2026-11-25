-- NEBULA 2.0 | Migracion 012 | Disponibilidad minima del perfil RAG
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preconditions$
DECLARE api_role pg_catalog.pg_roles%ROWTYPE;
BEGIN
  IF pg_catalog.to_regclass('rag.embedding_profiles') IS NULL THEN
    RAISE EXCEPTION 'required table rag.embedding_profiles does not exist';
  END IF;
  SELECT * INTO api_role FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api';
  IF NOT FOUND OR api_role.rolcanlogin OR api_role.rolsuper OR api_role.rolcreatedb OR
     api_role.rolcreaterole OR api_role.rolreplication OR api_role.rolbypassrls THEN
    RAISE EXCEPTION 'required nebula_rag_api role is missing or unsafe';
  END IF;
  IF pg_catalog.to_regprocedure('public.nebula_get_rag_profile_readiness(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'public.nebula_get_rag_profile_readiness(text) already exists';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(CURRENT_USER,'public','CREATE') OR
     NOT pg_catalog.has_table_privilege(CURRENT_USER,'rag.embedding_profiles','SELECT') THEN
    RAISE EXCEPTION 'migration owner lacks required CREATE or profile SELECT privilege';
  END IF;
END;
$preconditions$;

CREATE FUNCTION public.nebula_get_rag_profile_readiness(p_profile_id text)
RETURNS TABLE (ready boolean, profile_id text, dimension integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_dimension integer;
  v_ready boolean := false;
BEGIN
  IF p_profile_id IS NULL OR p_profile_id<>'gemini-embedding-001-768' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unsupported RAG embedding profile';
  END IF;

  SELECT ep.dimension,
         COALESCE(
           ep.status='active' AND
           ep.distance_metric='cosine' AND
           ep.dimension=768 AND
           ep.provider='google' AND
           ep.model='gemini-embedding-001' AND
           ep.normalization='unit_length',
           false)
  INTO v_dimension,v_ready
  FROM rag.embedding_profiles AS ep
  WHERE ep.profile_id=p_profile_id;

  IF NOT FOUND THEN
    v_dimension:=NULL;
    v_ready:=false;
  END IF;

  RETURN QUERY SELECT COALESCE(v_ready,false),p_profile_id,v_dimension;
END;
$function$;

DO $function_security$
DECLARE function_oid pg_catalog.oid;owner_name text;
BEGIN
  function_oid:=pg_catalog.to_regprocedure('public.nebula_get_rag_profile_readiness(text)');
  SELECT owner_role.rolname INTO owner_name
  FROM pg_catalog.pg_proc AS procedure
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid=procedure.proowner
  WHERE procedure.oid=function_oid;
  IF function_oid IS NULL OR owner_name IS NULL OR
     owner_name IN ('anon','authenticated','service_role','nebula_rag_api',
       'nebula_rag_api_login','nebula_rag_ingest','nebula_rag_reviewer') OR
     NOT pg_catalog.has_table_privilege(owner_name,'rag.embedding_profiles','SELECT') OR
     NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc
       WHERE oid=function_oid AND prosecdef AND provolatile='s'
         AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'unsafe owner or attributes for RAG readiness function';
  END IF;
END;
$function_security$;

REVOKE ALL ON FUNCTION public.nebula_get_rag_profile_readiness(text)
  FROM PUBLIC,anon,authenticated,service_role,nebula_rag_api,
       nebula_rag_api_login,nebula_rag_ingest,nebula_rag_reviewer;
GRANT EXECUTE ON FUNCTION public.nebula_get_rag_profile_readiness(text)
  TO nebula_rag_api;

COMMENT ON FUNCTION public.nebula_get_rag_profile_readiness(text) IS
  'Returns minimal readiness for the single approved RAG embedding profile.';

COMMIT;

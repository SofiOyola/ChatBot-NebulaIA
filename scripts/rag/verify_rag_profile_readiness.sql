BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE function_oid pg_catalog.oid;owner_oid pg_catalog.oid;owner_name text;
  unexpected_execute integer;actual_ready boolean;actual_profile text;actual_dimension integer;
  expected_ready boolean;expected_dimension integer;
BEGIN
  function_oid:=pg_catalog.to_regprocedure('public.nebula_get_rag_profile_readiness(text)');
  IF function_oid IS NULL THEN RAISE EXCEPTION 'readiness function is missing'; END IF;
  SELECT p.proowner,r.rolname INTO owner_oid,owner_name
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
  WHERE p.oid=function_oid AND p.prosecdef AND p.provolatile='s'
    AND p.proconfig @> ARRAY['search_path=""']
    AND p.proargtypes='25'::pg_catalog.oidvector
    AND p.proallargtypes=ARRAY[
      pg_catalog.to_regtype('pg_catalog.text')::pg_catalog.oid,
      pg_catalog.to_regtype('pg_catalog.bool')::pg_catalog.oid,
      pg_catalog.to_regtype('pg_catalog.text')::pg_catalog.oid,
      pg_catalog.to_regtype('pg_catalog.int4')::pg_catalog.oid]
    AND p.proargmodes=ARRAY['i','t','t','t']::"char"[]
    AND p.proargnames=ARRAY['p_profile_id','ready','profile_id','dimension'];
  IF owner_name IS NULL OR owner_name IN ('anon','authenticated','service_role','nebula_rag_api',
       'nebula_rag_api_login','nebula_rag_ingest','nebula_rag_reviewer') OR
     NOT pg_catalog.has_table_privilege(owner_name,'rag.embedding_profiles','SELECT') THEN
    RAISE EXCEPTION 'readiness function owner, signature or security attributes are unsafe';
  END IF;
  SELECT pg_catalog.count(*) INTO unexpected_execute
  FROM pg_catalog.aclexplode(COALESCE(
    (SELECT proacl FROM pg_catalog.pg_proc WHERE oid=function_oid),
    pg_catalog.acldefault('f',owner_oid))) acl
  WHERE acl.privilege_type='EXECUTE' AND acl.grantee NOT IN (
    owner_oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api'));
  IF unexpected_execute<>0 OR NOT pg_catalog.has_function_privilege('nebula_rag_api',function_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'readiness function EXECUTE ACL is not exclusive to nebula_rag_api';
  END IF;
  IF NOT pg_catalog.has_function_privilege('nebula_rag_api_login',function_oid,'EXECUTE') OR
     NOT pg_catalog.pg_has_role('nebula_rag_api_login','nebula_rag_api','MEMBER') THEN
    RAISE EXCEPTION 'limited API login cannot inherit readiness execution';
  END IF;
  -- PUBLIC is ACL grantee 0 and is covered by unexpected_execute above;
  -- it is not a PostgreSQL role name accepted by has_function_privilege.
  IF pg_catalog.has_function_privilege('anon',function_oid,'EXECUTE') OR
     pg_catalog.has_function_privilege('authenticated',function_oid,'EXECUTE') OR
     pg_catalog.has_function_privilege('service_role',function_oid,'EXECUTE') OR
     pg_catalog.has_function_privilege('nebula_rag_ingest',function_oid,'EXECUTE') OR
     pg_catalog.has_function_privilege('nebula_rag_reviewer',function_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'an unauthorized role can execute readiness';
  END IF;
  IF pg_catalog.has_schema_privilege('nebula_rag_api','rag','USAGE') OR
     pg_catalog.has_table_privilege('nebula_rag_api','rag.embedding_profiles','SELECT') OR
     pg_catalog.has_schema_privilege('nebula_rag_api_login','rag','USAGE') OR
     pg_catalog.has_table_privilege('nebula_rag_api_login','rag.embedding_profiles','SELECT') THEN
    RAISE EXCEPTION 'search role gained direct private profile access';
  END IF;
  IF NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'existing search RPC permissions changed';
  END IF;
  SELECT ep.dimension,COALESCE(ep.status='active' AND ep.distance_metric='cosine'
      AND ep.dimension=768 AND ep.provider='google' AND ep.model='gemini-embedding-001'
      AND ep.normalization='unit_length',false)
    INTO expected_dimension,expected_ready FROM rag.embedding_profiles ep
    WHERE ep.profile_id='gemini-embedding-001-768';
  SELECT r.ready,r.profile_id,r.dimension INTO actual_ready,actual_profile,actual_dimension
    FROM public.nebula_get_rag_profile_readiness('gemini-embedding-001-768') r;
  IF actual_ready IS NULL OR actual_ready IS DISTINCT FROM COALESCE(expected_ready,false) OR
     actual_profile IS DISTINCT FROM 'gemini-embedding-001-768' OR
     actual_dimension IS DISTINCT FROM expected_dimension THEN
    RAISE EXCEPTION 'readiness result does not match the approved profile contract';
  END IF;
END;
$verify$;
SELECT ready,profile_id,dimension,'RAG_PROFILE_READINESS_VERIFIED' AS result
FROM public.nebula_get_rag_profile_readiness('gemini-embedding-001-768');
ROLLBACK;

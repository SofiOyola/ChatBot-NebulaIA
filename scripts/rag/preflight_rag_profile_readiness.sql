BEGIN TRANSACTION READ ONLY;
DO $preflight$
DECLARE api_role pg_catalog.pg_roles%ROWTYPE;api_login pg_catalog.pg_roles%ROWTYPE;missing_columns integer;
BEGIN
  IF CURRENT_USER IN ('anon','authenticated','service_role','nebula_rag_api',
      'nebula_rag_api_login','nebula_rag_ingest','nebula_rag_ingest_login',
      'nebula_rag_reviewer','nebula_rag_reviewer_login') THEN
    RAISE EXCEPTION 'readiness deployment requires a reviewed administrative session';
  END IF;
  IF pg_catalog.to_regclass('rag.embedding_profiles') IS NULL THEN
    RAISE EXCEPTION 'rag.embedding_profiles is missing';
  END IF;
  WITH required(column_name,expected_type,is_not_null) AS (VALUES
    ('profile_id',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('provider',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('model',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('dimension',pg_catalog.to_regtype('pg_catalog.int4'),true),
    ('distance_metric',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('normalization',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('status',pg_catalog.to_regtype('pg_catalog.text'),true)
  )
  SELECT pg_catalog.count(*) INTO missing_columns FROM required req
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='rag.embedding_profiles'::pg_catalog.regclass
      AND a.attname=req.column_name AND NOT a.attisdropped
      AND a.atttypid=req.expected_type AND a.attnotnull=req.is_not_null);
  IF missing_columns<>0 THEN
    RAISE EXCEPTION 'required embedding profile columns missing or incompatible: %',missing_columns;
  END IF;
  SELECT * INTO api_role FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api';
  IF NOT FOUND OR api_role.rolcanlogin OR api_role.rolsuper OR api_role.rolcreatedb OR
     api_role.rolcreaterole OR api_role.rolreplication OR api_role.rolbypassrls THEN
    RAISE EXCEPTION 'nebula_rag_api is missing or unsafe';
  END IF;
  SELECT * INTO api_login FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api_login';
  IF NOT FOUND OR NOT api_login.rolcanlogin OR api_login.rolsuper OR api_login.rolcreatedb OR
     api_login.rolcreaterole OR api_login.rolreplication OR api_login.rolbypassrls OR
     NOT pg_catalog.pg_has_role('nebula_rag_api_login','nebula_rag_api','MEMBER') THEN
    RAISE EXCEPTION 'nebula_rag_api_login is missing, unsafe or lacks required membership';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_roles
      WHERE rolname IN ('anon','authenticated','service_role','nebula_rag_ingest','nebula_rag_reviewer'))<>5 THEN
    RAISE EXCEPTION 'one or more roles required by the migration ACL are missing';
  END IF;
  IF pg_catalog.to_regprocedure('public.nebula_get_rag_profile_readiness(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'readiness function name/signature collision detected';
  END IF;
  IF pg_catalog.to_regprocedure('public.nebula_search_academic_chunks(extensions.vector,text,integer,real)') IS NULL OR
     pg_catalog.to_regprocedure('public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)') IS NULL THEN
    RAISE EXCEPTION 'required RAG search functions are missing';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768' AND provider='google'
        AND model='gemini-embedding-001' AND dimension=768 AND distance_metric='cosine'
        AND normalization='unit_length' AND status IN ('inactive','active','retired'))<>1 THEN
    RAISE EXCEPTION 'approved embedding profile is missing or incompatible';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(CURRENT_USER,'public','CREATE') OR
     NOT pg_catalog.has_table_privilege(CURRENT_USER,'rag.embedding_profiles','SELECT') THEN
    RAISE EXCEPTION 'current session cannot safely create the readiness function';
  END IF;
  IF pg_catalog.has_schema_privilege('nebula_rag_api','rag','USAGE') OR
     pg_catalog.has_table_privilege('nebula_rag_api','rag.embedding_profiles','SELECT') OR
     pg_catalog.has_schema_privilege('nebula_rag_api_login','rag','USAGE') OR
     pg_catalog.has_table_privilege('nebula_rag_api_login','rag.embedding_profiles','SELECT') THEN
    RAISE EXCEPTION 'nebula_rag_api unexpectedly has direct profile access';
  END IF;
END;
$preflight$;
SELECT 'RAG_PROFILE_READINESS_PREFLIGHT_READY' AS result;
ROLLBACK;

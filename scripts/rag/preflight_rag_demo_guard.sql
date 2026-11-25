BEGIN TRANSACTION READ ONLY;

SELECT current_database() AS database_name,current_user AS audit_user,
       pg_catalog.current_setting('server_version') AS postgres_version,
       pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

SELECT e.extname,e.extversion,n.nspname AS extension_schema,r.rolname AS owner
FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
JOIN pg_catalog.pg_roles r ON r.oid=e.extowner WHERE e.extname='vector';

SELECT pg_catalog.count(*) AS existing_document_count,
       pg_catalog.count(*) FILTER (WHERE validation_status='pending') AS pending_count,
       pg_catalog.count(*) FILTER (WHERE validation_status='documented') AS documented_count
FROM rag.documents;

SELECT n.nspname,c.relname,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod) AS data_type
FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='rag' AND c.relname='documents' AND NOT a.attisdropped
  AND a.attname IN ('content_class','authorization_status','authorization_reference','authorization_date');

SELECT conname,pg_catalog.pg_get_constraintdef(oid) AS definition
FROM pg_catalog.pg_constraint WHERE conrelid='rag.documents'::pg_catalog.regclass
  AND conname IN ('documents_content_class_check','documents_authorization_status_check','documents_demo_safety_check');

SELECT p.oid::pg_catalog.regprocedure AS signature,r.rolname AS owner,p.prosecdef,p.proconfig,
       pg_catalog.has_function_privilege('nebula_rag_api',p.oid,'EXECUTE') AS rag_api_execute
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
WHERE p.oid IN (
  pg_catalog.to_regprocedure('public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'),
  pg_catalog.to_regprocedure('public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'));

DO $preflight$
DECLARE missing_columns integer;collision_count integer;policy_count integer;
BEGIN
  IF pg_catalog.current_setting('transaction_read_only')<>'on' THEN
    RAISE EXCEPTION 'preflight must run read only';
  END IF;
  IF pg_catalog.current_setting('server_version_num')::integer<170000 THEN
    RAISE EXCEPTION 'PostgreSQL 17 or newer is required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
      WHERE e.extname='vector' AND e.extversion='0.8.2' AND n.nspname='extensions') THEN
    RAISE EXCEPTION 'pgvector 0.8.2 in extensions is required';
  END IF;
  WITH required(column_name,expected_type) AS (VALUES
    ('source_type',pg_catalog.to_regtype('pg_catalog.text')),
    ('publisher',pg_catalog.to_regtype('pg_catalog.text')),
    ('metadata',pg_catalog.to_regtype('pg_catalog.jsonb')),
    ('information_type',pg_catalog.to_regtype('pg_catalog.text')),
    ('authority_level',pg_catalog.to_regtype('pg_catalog.text')),
    ('curriculum_scope',pg_catalog.to_regtype('pg_catalog.text')),
    ('validation_status',pg_catalog.to_regtype('pg_catalog.text')),
    ('validity_status',pg_catalog.to_regtype('pg_catalog.text')),
    ('is_current',pg_catalog.to_regtype('pg_catalog.bool'))
  ) SELECT pg_catalog.count(*) INTO missing_columns FROM required req
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='rag.documents'::pg_catalog.regclass AND a.attname=req.column_name
      AND NOT a.attisdropped AND a.atttypid=req.expected_type);
  IF missing_columns<>0 THEN RAISE EXCEPTION 'required document columns missing or incompatible: %',missing_columns; END IF;

  SELECT pg_catalog.count(*) INTO collision_count FROM pg_catalog.pg_attribute
  WHERE attrelid='rag.documents'::pg_catalog.regclass AND NOT attisdropped
    AND attname IN ('content_class','authorization_status','authorization_reference','authorization_date');
  collision_count:=collision_count+(SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint
    WHERE conrelid='rag.documents'::pg_catalog.regclass AND conname IN
      ('documents_content_class_check','documents_authorization_status_check','documents_demo_safety_check'));
  IF collision_count<>0 THEN RAISE EXCEPTION 'migration 011 column or constraint collision detected: %',collision_count; END IF;

  IF pg_catalog.to_regprocedure('public.nebula_search_academic_chunks(extensions.vector,text,integer,real)') IS NULL OR
     pg_catalog.to_regprocedure('public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)') IS NULL THEN
    RAISE EXCEPTION 'required search RPC signature is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid IN (
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::pg_catalog.regprocedure,
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::pg_catalog.regprocedure)
      AND (NOT p.prosecdef OR NOT p.proconfig @> ARRAY['search_path=""'])) THEN
    RAISE EXCEPTION 'search RPC security attributes are incompatible';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid IN (
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::pg_catalog.regprocedure,
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::pg_catalog.regprocedure)
      AND pg_catalog.pg_get_functiondef(p.oid) LIKE '%content_class%') THEN
    RAISE EXCEPTION 'search RPC already contains a content_class change; review partial deployment';
  END IF;
  IF NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'search service role cannot execute both existing RPCs';
  END IF;
  SELECT pg_catalog.count(*) INTO policy_count FROM pg_catalog.pg_policies
  WHERE schemaname='rag' AND policyname LIKE 'rag_%_ingest_%' OR
        schemaname='rag' AND policyname LIKE 'rag_%_reviewer_%';
  IF policy_count<>12 THEN RAISE EXCEPTION 'expected 12 ingestion/reviewer policies, found %',policy_count; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND (rolsuper OR rolcreaterole)) OR
     NOT pg_catalog.has_schema_privilege(current_user,'public','CREATE') THEN
    RAISE EXCEPTION 'audit session lacks required administrative authority';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      JOIN pg_catalog.pg_roles auditor ON auditor.rolname=current_user
      WHERE n.nspname='rag' AND c.relname='documents'
        AND NOT (c.relowner=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname=current_user)
          OR auditor.rolsuper OR pg_catalog.pg_has_role(current_user,c.relowner,'USAGE'))) THEN
    RAISE EXCEPTION 'audit session lacks effective ownership of rag.documents';
  END IF;
END;
$preflight$;

SELECT CASE WHEN pg_catalog.count(*)=0 THEN 'RAG_DEMO_GUARD_PREFLIGHT_READY'
            ELSE 'RAG_DEMO_GUARD_PREFLIGHT_PENDING_EXISTING_DOCUMENTS' END AS result
FROM rag.documents;
ROLLBACK;

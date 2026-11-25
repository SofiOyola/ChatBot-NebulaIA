BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE column_count integer;constraint_count integer;policy_count integer;filtered_rpc_count integer;
BEGIN
  WITH required(column_name,expected_type,not_null,expected_default) AS (VALUES
    ('content_class',pg_catalog.to_regtype('pg_catalog.text'),true,'''institutional''::text'),
    ('authorization_status',pg_catalog.to_regtype('pg_catalog.text'),true,'''pending''::text'),
    ('authorization_reference',pg_catalog.to_regtype('pg_catalog.text'),false,NULL::text),
    ('authorization_date',pg_catalog.to_regtype('pg_catalog.date'),false,NULL::text)
  ) SELECT pg_catalog.count(*) INTO column_count FROM required req
  JOIN pg_catalog.pg_attribute a ON a.attrelid='rag.documents'::pg_catalog.regclass
    AND a.attname=req.column_name AND NOT a.attisdropped AND a.atttypid=req.expected_type
    AND a.attnotnull=req.not_null
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE (req.expected_default IS NULL AND d.oid IS NULL) OR
        pg_catalog.pg_get_expr(d.adbin,d.adrelid)=req.expected_default;
  IF column_count<>4 THEN RAISE EXCEPTION 'demo guard columns are missing or incompatible'; END IF;

  SELECT pg_catalog.count(*) INTO constraint_count FROM pg_catalog.pg_constraint
  WHERE conrelid='rag.documents'::pg_catalog.regclass AND conname IN
    ('documents_content_class_check','documents_authorization_status_check','documents_demo_safety_check');
  IF constraint_count<>3 THEN RAISE EXCEPTION 'demo guard constraints are missing'; END IF;

  SELECT pg_catalog.count(*) INTO filtered_rpc_count FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
  WHERE n.nspname='public' AND p.proname IN
    ('nebula_search_academic_chunks','nebula_search_academic_chunks_hybrid')
    AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
    AND owner.rolname NOT IN ('anon','authenticated','service_role','nebula_rag_api')
    AND pg_catalog.pg_get_functiondef(p.oid) LIKE '%d.content_class=''institutional''%'
    AND pg_catalog.has_function_privilege('nebula_rag_api',p.oid,'EXECUTE');
  IF filtered_rpc_count<>2 THEN RAISE EXCEPTION 'both production search RPCs must exclude demo content'; END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      WHERE p.oid IN (
        'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::pg_catalog.regprocedure,
        'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::pg_catalog.regprocedure)
        AND acl.grantee=0 AND acl.privilege_type='EXECUTE') OR
     pg_catalog.has_function_privilege('anon',
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     pg_catalog.has_function_privilege('authenticated',
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'public client search RPC permissions are unsafe';
  END IF;

  SELECT pg_catalog.count(*) INTO policy_count FROM pg_catalog.pg_policies
  WHERE schemaname='rag' AND (policyname LIKE 'rag_%_ingest_%' OR policyname LIKE 'rag_%_reviewer_%');
  IF policy_count<>12 THEN RAISE EXCEPTION 'ingestion/reviewer RLS policy count changed: %',policy_count; END IF;
  IF pg_catalog.has_column_privilege('nebula_rag_reviewer','rag.documents','content_class','INSERT,UPDATE') OR
     NOT pg_catalog.has_column_privilege('nebula_rag_ingest','rag.documents','content_class','INSERT') OR
     pg_catalog.has_column_privilege('nebula_rag_ingest','rag.documents','content_class','UPDATE') THEN
    RAISE EXCEPTION 'demo metadata column privileges are unsafe';
  END IF;
END;
$verify$;
SELECT 'RAG_DEMO_GUARD_VERIFIED' AS result;
ROLLBACK;

BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE role_row pg_catalog.pg_roles%ROWTYPE; role_name text; policy_count integer;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['nebula_rag_ingest','nebula_rag_reviewer'] LOOP
    SELECT * INTO role_row FROM pg_catalog.pg_roles WHERE rolname=role_name;
    IF NOT FOUND OR role_row.rolcanlogin OR role_row.rolsuper OR role_row.rolcreatedb OR
       role_row.rolcreaterole OR role_row.rolreplication OR role_row.rolbypassrls THEN
      RAISE EXCEPTION 'missing or unsafe role %',role_name;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member=role_row.oid) THEN
      RAISE EXCEPTION 'role % inherits another role',role_name;
    END IF;
  END LOOP;
  SELECT count(*) INTO policy_count FROM pg_catalog.pg_policies
  WHERE schemaname='rag' AND policyname IN (
    'rag_profiles_ingest_read','rag_profiles_reviewer_read','rag_documents_ingest_read',
    'rag_documents_ingest_insert','rag_documents_reviewer_read','rag_chunks_ingest_read',
    'rag_chunks_ingest_insert','rag_chunks_reviewer_read','rag_embeddings_ingest_read',
    'rag_embeddings_ingest_insert','rag_embeddings_ingest_update','rag_embeddings_reviewer_read');
  IF policy_count<>12 THEN RAISE EXCEPTION 'expected 12 ingestion/review policies, found %',policy_count; END IF;
  IF pg_catalog.has_table_privilege('nebula_rag_ingest','rag.documents','DELETE') OR
     pg_catalog.has_table_privilege('nebula_rag_reviewer','rag.documents','INSERT,UPDATE,DELETE') OR
     pg_catalog.has_table_privilege('nebula_rag_ingest','rag.embedding_profiles','UPDATE') OR
     pg_catalog.has_table_privilege('nebula_rag_reviewer','rag.embedding_profiles','UPDATE') THEN
    RAISE EXCEPTION 'ingestion or reviewer role has an excessive table privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
    WHERE p.oid='public.nebula_review_rag_document(bigint,text,text)'::pg_catalog.regprocedure
      AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
      AND r.rolname NOT IN ('anon','authenticated','service_role','nebula_rag_api','nebula_rag_ingest','nebula_rag_reviewer')) THEN
    RAISE EXCEPTION 'review RPC security attributes or owner are unsafe';
  END IF;
  IF pg_catalog.has_function_privilege('nebula_rag_ingest',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege('nebula_rag_reviewer',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'review RPC grants do not match the separation contract';
  END IF;
  IF EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
       WHERE p.oid='public.nebula_review_rag_document(bigint,text,text)'::pg_catalog.regprocedure
         AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
     ) OR
     pg_catalog.has_function_privilege('anon',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') OR
     pg_catalog.has_function_privilege('authenticated',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'PUBLIC, anon or authenticated unexpectedly has review RPC execute privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') AND
     pg_catalog.has_function_privilege('service_role',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'service_role unexpectedly has review RPC execute privilege';
  END IF;
  IF NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') OR
     pg_catalog.has_function_privilege('nebula_rag_api',
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'existing search role contract changed';
  END IF;
END;
$verify$;
SELECT 'RAG_INGESTION_SECURITY_VERIFIED' AS result;
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls
FROM pg_catalog.pg_roles WHERE rolname IN ('nebula_rag_ingest','nebula_rag_reviewer') ORDER BY rolname;
SELECT schemaname,tablename,policyname,roles,cmd FROM pg_catalog.pg_policies
WHERE schemaname='rag' ORDER BY tablename,policyname;
ROLLBACK;

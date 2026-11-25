-- Compatible con psql y Supabase SQL Editor. Solo lectura.
BEGIN TRANSACTION READ ONLY;

DO $verify$
DECLARE
    vector_rpc oid := pg_catalog.to_regprocedure(
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)');
    hybrid_rpc oid := pg_catalog.to_regprocedure(
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)');
    api_role pg_catalog.pg_roles%ROWTYPE;
    actual integer;
BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_extension e
      JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
      WHERE e.extname='vector' AND e.extversion='0.8.2' AND n.nspname='extensions'
    ) THEN RAISE EXCEPTION 'expected vector 0.8.2 in extensions'; END IF;
    IF pg_catalog.to_regtype('extensions.vector') IS NULL THEN
      RAISE EXCEPTION 'extensions.vector type is missing';
    END IF;

    SELECT count(*) INTO actual
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='rag' AND c.relkind IN ('r','p');
    IF actual<>4 THEN RAISE EXCEPTION 'expected exactly four RAG tables, found %',actual; END IF;
    SELECT count(*) INTO actual
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='rag' AND c.relkind IN ('r','p')
      AND c.relname IN ('embedding_profiles','documents','document_chunks','chunk_embeddings')
      AND c.relrowsecurity;
    IF actual<>4 THEN RAISE EXCEPTION 'expected four RLS-enabled RAG tables'; END IF;

    SELECT count(*) INTO actual FROM (VALUES
      ('documents_supersedes_document_fkey'),('documents_current_requires_documented'),
      ('documents_information_type_check'),('documents_authority_level_check'),
      ('documents_validity_status_check'),('documents_curriculum_scope_check'),
      ('documents_current_requires_validity_check'),('documents_effective_dates_check')
    ) expected(name)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.connamespace
      WHERE n.nspname='rag' AND c.conname=expected.name
    );
    IF actual<>0 THEN RAISE EXCEPTION '% required named RAG constraints are missing',actual; END IF;

    SELECT count(*) INTO actual FROM (VALUES
      ('rag.embedding_profiles_one_active_idx'),('rag.document_chunks_document_idx'),
      ('rag.chunk_embeddings_profile_idx'),('rag.documents_one_current_source_idx'),
      ('rag.document_chunks_search_vector_idx'),('rag.documents_retrieval_filter_idx')
    ) expected(name) WHERE pg_catalog.to_regclass(expected.name) IS NULL;
    IF actual<>0 THEN RAISE EXCEPTION '% required RAG indexes are missing',actual; END IF;

    IF vector_rpc IS NULL OR hybrid_rpc IS NULL THEN
      RAISE EXCEPTION 'one or both exact RAG RPC signatures are missing';
    END IF;
    SELECT count(*) INTO actual
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
    WHERE p.oid IN (vector_rpc,hybrid_rpc)
      AND p.prosecdef AND p.provolatile='s'
      AND p.proconfig @> ARRAY['search_path=""'] AND r.rolname='postgres';
    IF actual<>2 THEN RAISE EXCEPTION 'RAG RPC owner or security attributes do not match'; END IF;

    -- PUBLIC es el grantee implicito OID 0, no una fila de pg_roles.
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      WHERE p.oid IN (vector_rpc,hybrid_rpc)
        AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) THEN RAISE EXCEPTION 'PUBLIC can execute a RAG RPC'; END IF;
    IF pg_catalog.has_function_privilege('anon',vector_rpc,'EXECUTE') OR
       pg_catalog.has_function_privilege('anon',hybrid_rpc,'EXECUTE') OR
       pg_catalog.has_function_privilege('authenticated',vector_rpc,'EXECUTE') OR
       pg_catalog.has_function_privilege('authenticated',hybrid_rpc,'EXECUTE') THEN
      RAISE EXCEPTION 'anon or authenticated can execute a RAG RPC';
    END IF;

    SELECT * INTO api_role FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api';
    IF NOT FOUND OR api_role.rolcanlogin OR api_role.rolsuper OR api_role.rolcreatedb OR
       api_role.rolcreaterole OR api_role.rolreplication OR api_role.rolbypassrls THEN
      RAISE EXCEPTION 'missing or unsafe nebula_rag_api role';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member=api_role.oid) THEN
      RAISE EXCEPTION 'nebula_rag_api inherits another role';
    END IF;
    IF NOT pg_catalog.has_function_privilege('nebula_rag_api',vector_rpc,'EXECUTE') OR
       NOT pg_catalog.has_function_privilege('nebula_rag_api',hybrid_rpc,'EXECUTE') THEN
      RAISE EXCEPTION 'nebula_rag_api cannot execute both RAG RPCs';
    END IF;
    IF NOT pg_catalog.has_type_privilege('nebula_rag_api','extensions.vector','USAGE') THEN
      RAISE EXCEPTION 'nebula_rag_api lacks effective USAGE on extensions.vector';
    END IF;

    IF pg_catalog.has_schema_privilege('anon','rag','USAGE') OR
       pg_catalog.has_schema_privilege('authenticated','rag','USAGE') OR
       pg_catalog.has_schema_privilege('nebula_rag_api','rag','USAGE') THEN
      RAISE EXCEPTION 'a client or API role has direct rag schema usage';
    END IF;
    IF EXISTS (
      SELECT 1 FROM (VALUES ('anon'),('authenticated'),('nebula_rag_api')) role_name(name)
      CROSS JOIN (VALUES ('embedding_profiles'),('documents'),('document_chunks'),('chunk_embeddings')) table_name(name)
      WHERE pg_catalog.has_table_privilege(role_name.name,
        pg_catalog.format('rag.%I',table_name.name),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    ) THEN RAISE EXCEPTION 'a client or API role has direct RAG table privileges'; END IF;
END;
$verify$;

SELECT 'RAG_DEPLOYMENT_SQL_VERIFIED' AS result;

-- Evidencia legible y no sensible para SQL Editor.
SELECT e.extversion,n.nspname AS extension_schema,r.rolname AS extension_owner
FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
JOIN pg_catalog.pg_roles r ON r.oid=e.extowner WHERE e.extname='vector';

SELECT n.nspname AS schema_name,c.relname AS table_name,r.rolname AS owner,c.relrowsecurity AS rls_enabled
FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
WHERE n.nspname='rag' AND c.relkind IN ('r','p') ORDER BY c.relname;

SELECT p.oid::pg_catalog.regprocedure AS signature,r.rolname AS owner,p.prosecdef AS security_definer,
       p.provolatile='s' AS stable,p.proconfig,
       EXISTS (SELECT 1 FROM pg_catalog.aclexplode(
         COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
         WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') AS public_execute,
       pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('nebula_rag_api',p.oid,'EXECUTE') AS rag_api_execute
FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
WHERE p.oid IN (
  pg_catalog.to_regprocedure('public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'),
  pg_catalog.to_regprocedure('public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'))
ORDER BY p.proname;

SELECT pg_catalog.to_regprocedure(
         'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)') AS vector_rpc,
       pg_catalog.to_regprocedure(
         'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)') AS hybrid_rpc;

SELECT t.oid::pg_catalog.regtype AS vector_type,r.rolname AS type_owner,t.typacl,
       EXISTS (SELECT 1 FROM pg_catalog.aclexplode(
         COALESCE(t.typacl,pg_catalog.acldefault('T',t.typowner))) acl
         WHERE acl.grantee=0 AND acl.privilege_type='USAGE') AS public_usage,
       pg_catalog.has_type_privilege('nebula_rag_api',t.oid,'USAGE') AS vector_usage_effective
FROM pg_catalog.pg_type t JOIN pg_catalog.pg_roles r ON r.oid=t.typowner
WHERE t.oid=pg_catalog.to_regtype('extensions.vector');

ROLLBACK;

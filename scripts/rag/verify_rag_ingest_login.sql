BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE login_role pg_catalog.pg_roles%ROWTYPE; membership_count integer; private_schema text;
BEGIN
  IF current_user<>'nebula_rag_ingest_login' OR session_user<>'nebula_rag_ingest_login' THEN
    RAISE EXCEPTION 'Session Pooler did not preserve the ingestion login identity';
  END IF;
  SELECT * INTO login_role FROM pg_catalog.pg_roles WHERE rolname=current_user;
  IF NOT FOUND OR NOT login_role.rolcanlogin OR NOT login_role.rolinherit OR login_role.rolsuper OR
     login_role.rolcreatedb OR login_role.rolcreaterole OR login_role.rolreplication OR login_role.rolbypassrls THEN
    RAISE EXCEPTION 'ingestion login attributes are unsafe';
  END IF;
  SELECT pg_catalog.count(*) INTO membership_count FROM pg_catalog.pg_auth_members WHERE member=login_role.oid;
  IF membership_count<>1 OR NOT pg_catalog.pg_has_role(current_user,'nebula_rag_ingest','MEMBER') OR
     pg_catalog.pg_has_role(current_user,'nebula_rag_reviewer','MEMBER') OR
     pg_catalog.pg_has_role(current_user,'nebula_rag_api','MEMBER') THEN
    RAISE EXCEPTION 'ingestion login membership is not exclusive';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user,'rag','USAGE') OR
     pg_catalog.has_schema_privilege(current_user,'rag','CREATE') OR
     pg_catalog.has_schema_privilege(current_user,'public','CREATE') THEN
    RAISE EXCEPTION 'ingestion schema privileges are unsafe';
  END IF;
  FOREACH private_schema IN ARRAY ARRAY['student','auth','memory'] LOOP
    IF pg_catalog.to_regnamespace(private_schema) IS NOT NULL AND
       pg_catalog.has_schema_privilege(current_user,private_schema,'USAGE') THEN
      RAISE EXCEPTION 'ingestion login has private schema usage: %',private_schema;
    END IF;
  END LOOP;
  IF NOT pg_catalog.has_table_privilege(current_user,'rag.documents','SELECT') OR
     NOT pg_catalog.has_column_privilege(current_user,'rag.documents','title','INSERT') OR
     pg_catalog.has_column_privilege(current_user,'rag.documents','ingested_by','INSERT') OR
     pg_catalog.has_column_privilege(current_user,'rag.documents','validation_status','UPDATE') OR
     pg_catalog.has_table_privilege(current_user,'rag.documents','DELETE') OR
     NOT pg_catalog.has_column_privilege(current_user,'rag.document_chunks','content','INSERT') OR
     NOT pg_catalog.has_column_privilege(current_user,'rag.chunk_embeddings','embedding','INSERT') OR
     NOT pg_catalog.has_column_privilege(current_user,'rag.chunk_embeddings','embedding','UPDATE') OR
     pg_catalog.has_column_privilege(current_user,'rag.chunk_embeddings','profile_id','UPDATE') OR
     pg_catalog.has_column_privilege(current_user,'rag.embedding_profiles','status','UPDATE') THEN
    RAISE EXCEPTION 'ingestion table or column privileges do not match the contract';
  END IF;
  IF pg_catalog.has_function_privilege(current_user,
       'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') OR
     pg_catalog.has_function_privilege(current_user,
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     pg_catalog.has_function_privilege(current_user,
       'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'ingestion login can execute a reserved RPC';
  END IF;
END;
$verify$;
SELECT current_user AS connected_role,session_user AS session_role,
       pg_catalog.has_schema_privilege(current_user,'rag','USAGE') AS rag_usage,
       pg_catalog.has_function_privilege(current_user,
         'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') AS review_execute,
       'RAG_INGEST_LOGIN_VERIFIED' AS result;
ROLLBACK;

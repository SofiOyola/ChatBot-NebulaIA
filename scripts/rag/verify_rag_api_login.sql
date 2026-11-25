BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE login_role pg_catalog.pg_roles%ROWTYPE; membership_count integer;
BEGIN
  IF current_user<>'nebula_rag_api_login' THEN
    RAISE EXCEPTION 'verification must run as nebula_rag_api_login, got %',current_user;
  END IF;
  SELECT * INTO login_role FROM pg_catalog.pg_roles WHERE rolname=current_user;
  IF NOT FOUND OR NOT login_role.rolcanlogin OR login_role.rolsuper OR login_role.rolcreatedb OR
     login_role.rolcreaterole OR login_role.rolreplication OR login_role.rolbypassrls THEN
    RAISE EXCEPTION 'login role attributes are unsafe';
  END IF;
  SELECT count(*) INTO membership_count
  FROM pg_catalog.pg_auth_members membership
  JOIN pg_catalog.pg_roles parent ON parent.oid=membership.roleid
  WHERE membership.member=login_role.oid AND parent.rolname='nebula_rag_api';
  IF membership_count<>1 THEN RAISE EXCEPTION 'required nebula_rag_api membership is missing'; END IF;

  IF NOT pg_catalog.has_function_privilege(current_user,
       'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege(current_user,
       'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'login cannot execute both approved RPCs';
  END IF;
  IF pg_catalog.has_schema_privilege(current_user,'rag','USAGE') OR
     pg_catalog.has_schema_privilege(current_user,'student','USAGE') THEN
    RAISE EXCEPTION 'login has direct private schema usage';
  END IF;

  BEGIN EXECUTE 'SELECT 1 FROM rag.documents LIMIT 1';
    RAISE EXCEPTION 'direct rag.documents SELECT unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN EXECUTE 'SELECT 1 FROM student.profiles LIMIT 1';
    RAISE EXCEPTION 'direct student.profiles SELECT unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  -- Ejecuta ambas funciones. P0002/22023 son validaciones internas esperadas
  -- mientras no exista un perfil activo compatible; 42501 no se acepta.
  BEGIN
    PERFORM * FROM public.nebula_search_academic_chunks(
      '[1]'::extensions.vector,'__permission_probe_no_profile__',1,0);
  EXCEPTION WHEN SQLSTATE 'P0002' OR SQLSTATE '22023' THEN NULL; END;
  BEGIN
    PERFORM * FROM public.nebula_search_academic_chunks_hybrid(
      'permission probe','[1]'::extensions.vector,'__permission_probe_no_profile__','old_9s_151c',1,0);
  EXCEPTION WHEN SQLSTATE 'P0002' OR SQLSTATE '22023' THEN NULL; END;
END;
$verify$;

SELECT current_user AS connected_role,
       pg_catalog.has_function_privilege(current_user,
         'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') AS vector_rpc_execute,
       pg_catalog.has_function_privilege(current_user,
         'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') AS hybrid_rpc_execute,
       pg_catalog.has_schema_privilege(current_user,'rag','USAGE') AS rag_schema_usage,
       pg_catalog.has_schema_privilege(current_user,'student','USAGE') AS student_schema_usage;
SELECT 'RAG_LIMITED_LOGIN_VERIFIED' AS result;
ROLLBACK;

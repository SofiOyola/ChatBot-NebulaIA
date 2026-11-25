BEGIN TRANSACTION READ ONLY;
DO $precheck$
DECLARE permission_role pg_catalog.pg_roles%ROWTYPE;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api_login') THEN
    RAISE EXCEPTION 'nebula_rag_api_login already exists; creation aborted';
  END IF;
  SELECT * INTO permission_role FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api';
  IF NOT FOUND OR permission_role.rolcanlogin OR permission_role.rolsuper OR
     permission_role.rolcreatedb OR permission_role.rolcreaterole OR
     permission_role.rolreplication OR permission_role.rolbypassrls THEN
    RAISE EXCEPTION 'nebula_rag_api is missing or unsafe';
  END IF;
END;
$precheck$;
SELECT 'RAG_LOGIN_NAME_AVAILABLE_AND_PERMISSION_ROLE_SAFE' AS result;
ROLLBACK;

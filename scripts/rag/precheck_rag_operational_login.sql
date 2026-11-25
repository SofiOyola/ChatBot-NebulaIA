BEGIN TRANSACTION READ ONLY;
SELECT pg_catalog.set_config('nebula.precheck_login_name',:'login_name',true),
       pg_catalog.set_config('nebula.precheck_permission_role',:'permission_role',true);
DO $precheck$
DECLARE permission_role pg_catalog.pg_roles%ROWTYPE;
        login_name text:=pg_catalog.current_setting('nebula.precheck_login_name');
        permission_role_name text:=pg_catalog.current_setting('nebula.precheck_permission_role');
BEGIN
  IF (login_name,permission_role_name) NOT IN (
       ('nebula_rag_ingest_login','nebula_rag_ingest'),
       ('nebula_rag_reviewer_login','nebula_rag_reviewer')) THEN
    RAISE EXCEPTION 'unsupported operational login mapping';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=login_name) THEN
    RAISE EXCEPTION '% already exists; creation aborted',login_name;
  END IF;
  SELECT * INTO permission_role FROM pg_catalog.pg_roles WHERE rolname=permission_role_name;
  IF NOT FOUND OR permission_role.rolcanlogin OR permission_role.rolsuper OR
     permission_role.rolcreatedb OR permission_role.rolcreaterole OR
     permission_role.rolreplication OR permission_role.rolbypassrls THEN
    RAISE EXCEPTION '% is missing or unsafe',permission_role_name;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member=permission_role.oid) THEN
    RAISE EXCEPTION '% unexpectedly inherits another role',permission_role_name;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname='nebula_rag_api_login'
      AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolcreatedb AND NOT r.rolcreaterole
      AND NOT r.rolreplication AND NOT r.rolbypassrls) OR
     (SELECT pg_catalog.count(*) FROM pg_catalog.pg_auth_members m
      JOIN pg_catalog.pg_roles member_role ON member_role.oid=m.member
      JOIN pg_catalog.pg_roles parent ON parent.oid=m.roleid
      WHERE member_role.rolname='nebula_rag_api_login')<>1 OR
     NOT pg_catalog.pg_has_role('nebula_rag_api_login','nebula_rag_api','MEMBER') THEN
    RAISE EXCEPTION 'existing search login is missing or its security contract changed';
  END IF;
END;
$precheck$;
SELECT :'login_name' AS available_login, :'permission_role' AS safe_permission_role,
       'RAG_OPERATIONAL_LOGIN_PREFLIGHT_READY' AS result;
ROLLBACK;

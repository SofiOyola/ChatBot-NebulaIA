\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT current_database() AS database_name, current_user AS audit_user,
       current_setting('server_version') AS postgres_version;
SELECT e.extname,e.extversion,n.nspname AS extension_schema,r.rolname AS owner
FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
JOIN pg_roles r ON r.oid=e.extowner WHERE e.extname='vector';
SELECT r.rolname,r.rolcanlogin,r.rolsuper,r.rolcreatedb,r.rolcreaterole,
       r.rolreplication,r.rolbypassrls
FROM pg_roles r WHERE r.rolname IN ('nebula_rag_api','nebula_rag_api_login');
SELECT n.nspname,c.relname,c.relkind,r.rolname AS owner,c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_roles r ON r.oid=c.relowner
WHERE n.nspname='rag' ORDER BY c.relkind,c.relname;
SELECT p.oid::regprocedure AS function_signature,r.rolname AS owner,p.prosecdef,p.proconfig,
       has_function_privilege('PUBLIC',p.oid,'EXECUTE') AS public_execute,
       CASE WHEN EXISTS(SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api')
            THEN has_function_privilege('nebula_rag_api',p.oid,'EXECUTE') END AS rag_api_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner
WHERE n.nspname='public' AND (p.proname LIKE 'nebula_search_academic_chunks%' OR p.prosecdef)
ORDER BY p.proname;
SELECT d.refobjid::regprocedure AS referenced_function, d.objid::regprocedure AS dependent_object
FROM pg_depend d JOIN pg_proc p ON p.oid=d.refobjid
WHERE p.proname LIKE 'nebula_search_academic_chunks%';
ROLLBACK;

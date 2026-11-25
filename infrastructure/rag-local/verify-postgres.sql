\set ON_ERROR_STOP on
DO $verify$
DECLARE found integer; owner_name text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
                 WHERE e.extname='vector' AND e.extversion='0.8.2' AND n.nspname='extensions') THEN
    RAISE EXCEPTION 'vector 0.8.2 is not installed in extensions';
  END IF;
  SELECT count(*) INTO found FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='rag' AND c.relkind='r' AND c.relrowsecurity;
  IF found<>4 THEN RAISE EXCEPTION 'expected four RLS tables, found %',found; END IF;
  SELECT r.rolname INTO owner_name FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
  WHERE p.oid='public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::regprocedure;
  IF owner_name IS NULL OR owner_name IN ('anon','authenticated','authenticator','service_role') THEN
    RAISE EXCEPTION 'unsafe function owner';
  END IF;
  IF has_schema_privilege('anon','rag','USAGE') OR has_table_privilege('anon','rag.documents','SELECT')
     OR has_schema_privilege('authenticated','rag','USAGE')
     OR has_table_privilege('authenticated','rag.documents','SELECT')
     OR has_schema_privilege('nebula_rag_api','rag','USAGE')
     OR has_table_privilege('nebula_rag_api','rag.documents','SELECT') THEN
    RAISE EXCEPTION 'client or API role has direct RAG access';
  END IF;
  IF has_function_privilege('anon',
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE')
     OR has_function_privilege('anon',
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'anon unexpectedly has RAG RPC execute privilege';
  END IF;
  IF NOT has_function_privilege('nebula_rag_api',
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE')
     OR NOT has_function_privilege('nebula_rag_api',
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') THEN
    RAISE EXCEPTION 'nebula_rag_api RPC execute privilege missing';
  END IF;
END;
$verify$;

SET ROLE nebula_rag_api;
DO $visibility$
DECLARE old_count integer; hybrid_count integer;
BEGIN
  SELECT count(*) INTO old_count FROM public.nebula_search_academic_chunks(
      '[1,0,0]'::extensions.vector,'local-synthetic-3d',10,0);
  IF old_count<>1 THEN RAISE EXCEPTION 'vector RPC returned % rows, expected 1',old_count; END IF;
  SELECT count(*) INTO hybrid_count FROM public.nebula_search_academic_chunks_hybrid(
      'curriculum credits','[1,0,0]'::extensions.vector,'local-synthetic-3d','old_9s_151c',10,0);
  IF hybrid_count<>1 THEN RAISE EXCEPTION 'hybrid RPC returned % rows, expected 1',hybrid_count; END IF;
END;
$visibility$;
RESET ROLE;
SELECT 'RAG_LOCAL_POSTGRES_PASS' AS result;

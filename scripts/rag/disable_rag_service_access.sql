\set ON_ERROR_STOP on
BEGIN;
REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(
  extensions.vector,text,integer,real) FROM nebula_rag_api;
REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid(
  text,extensions.vector,text,text,integer,real) FROM nebula_rag_api;
COMMIT;
SELECT 'RAG_SERVICE_ACCESS_DISABLED_DATA_PRESERVED' AS result;

-- NEBULA 2.0 | Migracion 009 | Rol minimo para el servicio HTTP RAG
-- Crea un rol de permisos NOLOGIN. La identidad LOGIN y su secreto se crean
-- fuera de la migracion mediante un procedimiento operativo protegido.
BEGIN;

DO $role$
DECLARE existing pg_catalog.pg_roles%ROWTYPE;
BEGIN
    SELECT * INTO existing FROM pg_catalog.pg_roles WHERE rolname = 'nebula_rag_api';
    IF NOT FOUND THEN
        CREATE ROLE nebula_rag_api NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOINHERIT NOREPLICATION NOBYPASSRLS;
    ELSIF existing.rolcanlogin OR existing.rolsuper OR existing.rolcreatedb OR
          existing.rolcreaterole OR existing.rolreplication OR existing.rolbypassrls THEN
        RAISE EXCEPTION 'existing nebula_rag_api role has unsafe attributes';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_auth_members AS membership
        JOIN pg_catalog.pg_roles AS member_role ON member_role.oid = membership.member
        WHERE member_role.rolname = 'nebula_rag_api'
    ) THEN
        RAISE EXCEPTION 'nebula_rag_api must not inherit membership in another role';
    END IF;
END;
$role$;

REVOKE ALL ON SCHEMA rag FROM nebula_rag_api;
REVOKE ALL ON ALL TABLES IN SCHEMA rag FROM nebula_rag_api;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA rag FROM nebula_rag_api;
GRANT USAGE ON SCHEMA public, extensions TO nebula_rag_api;
GRANT USAGE ON TYPE extensions.vector TO nebula_rag_api;

REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(
    extensions.vector, text, integer, real) FROM PUBLIC, anon, authenticated, nebula_rag_api;
REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid(
    text, extensions.vector, text, text, integer, real) FROM PUBLIC, anon, authenticated, nebula_rag_api;
GRANT EXECUTE ON FUNCTION public.nebula_search_academic_chunks(
    extensions.vector, text, integer, real) TO nebula_rag_api;
GRANT EXECUTE ON FUNCTION public.nebula_search_academic_chunks_hybrid(
    text, extensions.vector, text, text, integer, real) TO nebula_rag_api;

COMMIT;

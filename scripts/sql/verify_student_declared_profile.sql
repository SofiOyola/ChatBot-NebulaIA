-- Verificacion de la migracion 20261125120000_student_declared_profile.sql
-- Solo lectura. Lanza excepcion si algo no cumple. Ejecutar tras aplicar la migracion.
BEGIN TRANSACTION READ ONLY;

DO $verify$
DECLARE
    fn oid := pg_catalog.to_regprocedure('public.get_student_profile()');
BEGIN
    -- 1) Columnas nuevas en student.profiles.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'student' AND c.relname = 'profiles'
          AND a.attname = 'declared_cumulative_gpa' AND NOT a.attisdropped
    ) THEN RAISE EXCEPTION 'Falta la columna declared_cumulative_gpa'; END IF;

    -- 2) Funcion de lectura presente, SECURITY DEFINER, STABLE y search_path vacio.
    --    PostgreSQL almacena "search_path=\"\"" (comillas vacias) para SET search_path = ''.
    IF fn IS NULL THEN RAISE EXCEPTION 'Falta public.get_student_profile()'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid = fn AND p.prosecdef AND p.provolatile = 's'
          AND p.proconfig @> ARRAY['search_path=""']
    ) THEN RAISE EXCEPTION 'Atributos de seguridad de get_student_profile incorrectos'; END IF;

    -- 3) PUBLIC (grantee 0) NO puede ejecutar; anon NO; authenticated SI.
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) acl
        WHERE p.oid = fn AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    ) THEN RAISE EXCEPTION 'PUBLIC no debe poder ejecutar get_student_profile'; END IF;
    IF pg_catalog.has_function_privilege('anon', fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'anon no debe poder ejecutar get_student_profile';
    END IF;
    IF NOT pg_catalog.has_function_privilege('authenticated', fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'authenticated debe poder ejecutar get_student_profile';
    END IF;

    -- 4) Las tablas del esquema student siguen sin acceso directo para anon ni authenticated.
    IF pg_catalog.has_table_privilege('authenticated', 'student.profiles', 'SELECT') THEN
        RAISE EXCEPTION 'authenticated no debe tener acceso directo a student.profiles';
    END IF;
    IF pg_catalog.has_table_privilege('anon', 'student.profiles', 'SELECT') THEN
        RAISE EXCEPTION 'anon no debe tener acceso directo a student.profiles';
    END IF;

    -- 5) RLS sigue habilitada en student.profiles.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'student' AND c.relname = 'profiles' AND c.relrowsecurity
    ) THEN RAISE EXCEPTION 'RLS debe seguir habilitada en student.profiles'; END IF;
END;
$verify$;

SELECT 'STUDENT_DECLARED_PROFILE_VERIFIED' AS result;

ROLLBACK;

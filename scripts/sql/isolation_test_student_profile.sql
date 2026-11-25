-- Prueba de AISLAMIENTO de public.get_student_profile() con sesiones autenticadas
-- simuladas (distinto "sub" de JWT). No escribe nada: termina en ROLLBACK.
-- Ejecutar tras la migracion (y, para la parte 2b, tras el seed) en el SQL Editor.
--
-- Comprueba:
--   1) Acceso DIRECTO a student.profiles como rol authenticated: debe fallar.
--   2a) Usuario autenticado con un sub SIN perfil: la funcion devuelve 0 filas
--       (no puede ver el perfil de nadie mas).
--   2b) Usuario autenticado cuyo sub = un perfil existente: devuelve EXACTAMENTE 1
--       fila (la suya). Si hay dos perfiles, cada uno ve solo el suyo.
BEGIN;

DO $iso$
DECLARE
    v_a uuid;
    v_b uuid;
    v_random uuid := gen_random_uuid();
    n integer;
    blocked boolean := false;
BEGIN
    -- Perfiles existentes (como admin; superusuario omite RLS). Puede haber 0, 1 o 2+.
    SELECT user_id INTO v_a FROM student.profiles ORDER BY user_id LIMIT 1;
    SELECT user_id INTO v_b FROM student.profiles ORDER BY user_id OFFSET 1 LIMIT 1;

    ----------------------------------------------------------------------------
    -- 1) Acceso directo a la tabla como authenticated: debe estar prohibido.
    ----------------------------------------------------------------------------
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM 1 FROM student.profiles LIMIT 1;  -- deberia lanzar insufficient_privilege
    EXCEPTION
        WHEN insufficient_privilege THEN blocked := true;
    END;
    RESET ROLE;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FALLO: authenticated pudo leer student.profiles directamente';
    END IF;

    ----------------------------------------------------------------------------
    -- 2a) Sub autenticado SIN perfil -> 0 filas.
    ----------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_random, 'role', 'authenticated')::text, true);
    SELECT count(*) INTO n FROM public.get_student_profile();
    IF n <> 0 THEN
        RAISE EXCEPTION 'FALLO: un usuario sin perfil obtuvo % filas', n;
    END IF;

    ----------------------------------------------------------------------------
    -- 2b) Sub = perfil existente -> exactamente 1 fila (la suya).
    ----------------------------------------------------------------------------
    IF v_a IS NULL THEN
        RAISE NOTICE 'Sin perfiles cargados: se omite 2b (ejecuta el seed primero).';
    ELSE
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
        SELECT count(*) INTO n FROM public.get_student_profile();
        IF n <> 1 THEN
            RAISE EXCEPTION 'FALLO: el usuario A deberia ver 1 fila, vio %', n;
        END IF;

        IF v_b IS NOT NULL THEN
            PERFORM set_config('request.jwt.claims',
                json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
            SELECT count(*) INTO n FROM public.get_student_profile();
            IF n <> 1 THEN
                RAISE EXCEPTION 'FALLO: el usuario B deberia ver 1 fila, vio %', n;
            END IF;
            RAISE NOTICE 'OK: dos usuarios distintos ven solo su propio perfil.';
        ELSE
            RAISE NOTICE 'OK: un usuario ve solo su propio perfil (1 fila).';
        END IF;
    END IF;

    PERFORM set_config('request.jwt.claims', NULL, true);
END;
$iso$;

SELECT 'STUDENT_PROFILE_ISOLATION_VERIFIED' AS result;

ROLLBACK;

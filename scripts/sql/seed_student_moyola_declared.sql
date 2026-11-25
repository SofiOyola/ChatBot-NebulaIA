-- NEBULA 2.0 | Dato DECLARADO por la estudiante: moyola@unab.edu.co
-- Semestre actual: 6   |   Promedio acumulado declarado: 4.61
--
-- REQUIERE aprobacion antes de ejecutarse en Supabase Cloud.
-- Ejecutar UNA vez en el proyecto correcto (SQL Editor o psql con rol adecuado),
-- DESPUES de aplicar la migracion 20261125120000_student_declared_profile.sql.
--
-- Seguridad y honestidad:
--   - La relacion se ALMACENA por user_id (uuid de Supabase Auth). El correo se usa
--     SOLO para localizar la cuenta y resolver su uuid, nunca como clave almacenada.
--   - NO inventa notas individuales ni creditos aprobados. Solo guarda semestre y
--     promedio declarados por la propia estudiante.
--   - Idempotente: re-ejecutar deja el mismo estado.
BEGIN;

DO $seed$
DECLARE
    v_email text := 'moyola@unab.edu.co';
    v_uid   uuid;
    v_count integer;
    v_curr  text := 'NEBULA-UNAB-IS-9S-V1';  -- plan historico 9 semestres / 151 creditos
BEGIN
    -- Exigir EXACTAMENTE una cuenta con ese correo (comparacion sin distinguir mayusculas).
    SELECT count(*) INTO v_count FROM auth.users WHERE lower(email) = lower(v_email);
    IF v_count = 0 THEN
        RAISE EXCEPTION 'No existe la cuenta % en auth.users', v_email;
    ELSIF v_count > 1 THEN
        RAISE EXCEPTION 'Hay % cuentas con el correo %; se aborta por seguridad', v_count, v_email;
    END IF;
    SELECT id INTO v_uid FROM auth.users WHERE lower(email) = lower(v_email);

    IF NOT EXISTS (SELECT 1 FROM academic.curriculum_versions WHERE curriculum_id = v_curr) THEN
        RAISE EXCEPTION 'Falta el plan % en academic.curriculum_versions', v_curr;
    END IF;

    -- Guarda SOLO los datos declarados. En conflicto NO reescribe curriculum_id,
    -- student_code, full_name, enrollment_status ni ningun registro academico.
    INSERT INTO student.profiles AS p
        (user_id, curriculum_id, current_semester,
         declared_cumulative_gpa, declared_gpa_reported_at, enrollment_status)
    VALUES
        (v_uid, v_curr, 6, 4.61, now(), 'active')
    ON CONFLICT (user_id) DO UPDATE SET
        current_semester         = EXCLUDED.current_semester,
        declared_cumulative_gpa  = EXCLUDED.declared_cumulative_gpa,
        declared_gpa_reported_at = EXCLUDED.declared_gpa_reported_at,
        updated_at               = now();

    RAISE NOTICE 'Perfil declarado guardado para uuid % (semestre 6, promedio 4.61).', v_uid;
END;
$seed$;

COMMIT;

-- Verificacion (solo lectura). Debe mostrar current_semester=6 y declared_cumulative_gpa=4.61.
SELECT p.current_semester, p.declared_cumulative_gpa, p.curriculum_id, p.enrollment_status
FROM student.profiles p
JOIN auth.users u ON u.id = p.user_id
WHERE lower(u.email) = lower('moyola@unab.edu.co');

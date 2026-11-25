-- NEBULA 2.0 | Migracion 004
-- API de lectura academica por usuario autenticado (sin SQL libre para Gemini).
-- Requiere migraciones 001, 002 y 003 aplicadas.
-- No crea usuarios, no inserta notas, no altera el catalogo.
BEGIN;

-- Esta funcion no acepta user_id. La identidad se obtiene del JWT validado por Supabase.
CREATE OR REPLACE FUNCTION public.get_academic_history()
RETURNS TABLE (
    position_id text,
    course_name text,
    curriculum_semester integer,
    credits integer,
    attempt_number integer,
    final_grade numeric,
    outcome text,
    source_type text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        ca.position_id,
        cp.original_name AS course_name,
        cp.semester AS curriculum_semester,
        cp.credits,
        ca.attempt_number,
        ca.final_grade,
        ca.outcome,
        ca.source_type
    FROM student.course_attempts AS ca
    INNER JOIN student.profiles AS sp
        ON sp.user_id = ca.user_id AND sp.curriculum_id = ca.curriculum_id
    INNER JOIN academic.curriculum_positions AS cp
        ON cp.curriculum_id = ca.curriculum_id
       AND cp.position_id = ca.position_id
    WHERE ca.user_id = (SELECT auth.uid())
    ORDER BY cp.semester, cp.position_number, ca.attempt_number;
$$;

-- Reporta creditos verificados y declarados por separado.
-- Solo cuenta una vez cada posicion aprobada y nunca infiere aprobado por nota.
CREATE OR REPLACE FUNCTION public.get_credit_progress()
RETURNS TABLE (
    total_curriculum_credits bigint,
    verified_approved_credits bigint,
    reported_only_approved_credits bigint,
    pending_or_unverified_credits bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH my_profiles AS (
        SELECT curriculum_id
        FROM student.profiles
        WHERE user_id = (SELECT auth.uid())
    ), position_state AS (
        SELECT cp.credits,
            EXISTS (
                SELECT 1 FROM student.course_attempts AS ca
                WHERE ca.user_id = (SELECT auth.uid())
                  AND ca.curriculum_id = cp.curriculum_id
                  AND ca.position_id = cp.position_id
                  AND ca.outcome = 'passed'
                  AND ca.source_type IN ('institution_verified', 'admin_recorded')
            ) AS verified_pass,
            EXISTS (
                SELECT 1 FROM student.course_attempts AS ca
                WHERE ca.user_id = (SELECT auth.uid())
                  AND ca.curriculum_id = cp.curriculum_id
                  AND ca.position_id = cp.position_id
                  AND ca.outcome = 'passed'
                  AND ca.source_type = 'student_reported'
            ) AS reported_pass
        FROM academic.curriculum_positions AS cp
        JOIN my_profiles AS mp ON mp.curriculum_id = cp.curriculum_id
    )
    SELECT
        COALESCE(SUM(credits), 0)::bigint,
        COALESCE(SUM(credits) FILTER (WHERE verified_pass), 0)::bigint,
        COALESCE(SUM(credits) FILTER (WHERE NOT verified_pass AND reported_pass), 0)::bigint,
        COALESCE(SUM(credits) FILTER (WHERE NOT verified_pass AND NOT reported_pass), 0)::bigint
    FROM position_state
    HAVING COUNT(*) > 0;
$$;

-- Impedir que PUBLIC o un usuario anonimo ejecute estos endpoints.
REVOKE ALL ON FUNCTION public.get_academic_history() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_credit_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_academic_history() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_credit_progress() TO authenticated;

COMMIT;

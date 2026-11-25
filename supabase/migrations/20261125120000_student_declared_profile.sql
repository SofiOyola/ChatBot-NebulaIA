-- NEBULA 2.0 | Migracion 013: promedio declarado y lectura de perfil estudiantil
-- NUEVA migracion. No modifica migraciones ya aplicadas. Ejecutar con rol postgres
-- DESPUES de 003 (student schema) y 004 (funciones de lectura).
--
-- Que hace:
--   1) Agrega a student.profiles un promedio acumulado DECLARADO por el estudiante
--      (no es una certificacion oficial de la UNAB) y su marca temporal.
--   2) Crea public.get_student_profile(): lectura SECURITY DEFINER del perfil del
--      usuario autenticado (identidad por JWT, auth.uid()). No acepta user_id.
--
-- No inserta datos de estudiantes. No inventa notas ni creditos. No toca el catalogo.
BEGIN;

ALTER TABLE student.profiles
    ADD COLUMN IF NOT EXISTS declared_cumulative_gpa numeric(3,2)
        CHECK (declared_cumulative_gpa IS NULL OR declared_cumulative_gpa BETWEEN 0 AND 5),
    ADD COLUMN IF NOT EXISTS declared_gpa_reported_at timestamptz;

COMMENT ON COLUMN student.profiles.declared_cumulative_gpa IS
    'Promedio acumulado DECLARADO por el estudiante. No es certificacion oficial UNAB.';

-- Lectura del perfil propio. La identidad se obtiene del JWT validado por Supabase.
CREATE OR REPLACE FUNCTION public.get_student_profile()
RETURNS TABLE (
    curriculum_id text,
    current_semester integer,
    enrollment_status text,
    declared_cumulative_gpa numeric,
    declared_gpa_reported_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        sp.curriculum_id,
        sp.current_semester,
        sp.enrollment_status,
        sp.declared_cumulative_gpa,
        sp.declared_gpa_reported_at
    FROM student.profiles AS sp
    WHERE sp.user_id = (SELECT auth.uid());
$$;

-- Impedir ejecucion anonima; permitir solo a usuarios autenticados.
REVOKE ALL ON FUNCTION public.get_student_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_profile() TO authenticated;

COMMIT;

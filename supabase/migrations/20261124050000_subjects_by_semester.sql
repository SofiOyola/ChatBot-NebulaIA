-- NEBULA 2.0 | Migracion 005
-- Catalogo curricular de solo lectura por semestre.
-- Requiere migraciones 001 y 002 aplicadas.
-- No expone el esquema academic ni consulta informacion de estudiantes.
BEGIN;

CREATE OR REPLACE FUNCTION public.nebula_get_subjects_by_semester(p_semester integer)
RETURNS TABLE (
    curriculum_id text,
    position_id text,
    subject_name text,
    institutional_code text,
    semester integer,
    position_number integer,
    credits integer,
    category text,
    elective_group text,
    prerequisite_coverage text,
    prerequisites jsonb,
    corequisite_coverage text,
    corequisites jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_curriculum_id text;
    matching_curricula integer;
BEGIN
    IF p_semester IS NULL OR p_semester NOT BETWEEN 1 AND 9 THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'p_semester must be between 1 and 9';
    END IF;

    -- Resolver el pensum por sus invariantes verificables, no por un nombre inventado.
    SELECT COUNT(*)::integer, MIN(candidate.curriculum_id)
    INTO matching_curricula, target_curriculum_id
    FROM (
        SELECT cv.curriculum_id
        FROM academic.curriculum_versions AS cv
        WHERE cv.term_count = 9
          AND cv.position_count = 51
          AND cv.total_credits = 151
          AND (SELECT COUNT(*)
               FROM academic.curriculum_positions AS counted
               WHERE counted.curriculum_id = cv.curriculum_id) = 51
          AND (SELECT COALESCE(SUM(summed.credits), 0)
               FROM academic.curriculum_positions AS summed
               WHERE summed.curriculum_id = cv.curriculum_id) = 151
    ) AS candidate;

    IF matching_curricula = 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0002',
            MESSAGE = 'expected curriculum was not found';
    ELSIF matching_curricula > 1 THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0003',
            MESSAGE = 'more than one curriculum matches the expected invariants';
    END IF;

    RETURN QUERY
    SELECT
        cp.curriculum_id,
        cp.position_id,
        cp.original_name AS subject_name,
        CASE
            WHEN c.code_evidence_id IS NOT NULL
             AND c.evidence_kind = 'official'
             AND c.evidence_status = 'documented'
            THEN c.institutional_code
            ELSE NULL
        END AS institutional_code,
        cp.semester,
        cp.position_number,
        cp.credits,
        cp.category,
        eg.label AS elective_group,
        prerequisite_state.coverage AS prerequisite_coverage,
        COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'position_id', required.position_id,
                    'subject_name', required.original_name,
                    'semester', required.semester,
                    'coverage', relation.coverage,
                    'applicability', relation.applicability
                )
                ORDER BY required.semester, required.position_number
            )
            FROM academic.course_requirements AS relation
            INNER JOIN academic.curriculum_positions AS required
                ON required.curriculum_id = relation.curriculum_id
               AND required.position_id = relation.required_position_id
            WHERE relation.curriculum_id = cp.curriculum_id
              AND relation.position_id = cp.position_id
              AND relation.kind = 'prerequisite'
        ), '[]'::jsonb) AS prerequisites,
        corequisite_state.coverage AS corequisite_coverage,
        COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'position_id', required.position_id,
                    'subject_name', required.original_name,
                    'semester', required.semester,
                    'coverage', relation.coverage,
                    'applicability', relation.applicability
                )
                ORDER BY required.semester, required.position_number
            )
            FROM academic.course_requirements AS relation
            INNER JOIN academic.curriculum_positions AS required
                ON required.curriculum_id = relation.curriculum_id
               AND required.position_id = relation.required_position_id
            WHERE relation.curriculum_id = cp.curriculum_id
              AND relation.position_id = cp.position_id
              AND relation.kind = 'corequisite'
        ), '[]'::jsonb) AS corequisites
    FROM academic.curriculum_positions AS cp
    LEFT JOIN academic.courses AS c
        ON c.course_id = cp.course_id
       AND c.institution_id = cp.institution_id
    LEFT JOIN academic.elective_slots AS es
        ON es.curriculum_id = cp.curriculum_id
       AND es.position_id = cp.position_id
    LEFT JOIN academic.elective_groups AS eg
        ON eg.curriculum_id = es.curriculum_id
       AND eg.group_id = es.group_id
    LEFT JOIN academic.requirement_coverage AS prerequisite_state
        ON prerequisite_state.curriculum_id = cp.curriculum_id
       AND prerequisite_state.position_id = cp.position_id
       AND prerequisite_state.kind = 'prerequisite'
    LEFT JOIN academic.requirement_coverage AS corequisite_state
        ON corequisite_state.curriculum_id = cp.curriculum_id
       AND corequisite_state.position_id = cp.position_id
       AND corequisite_state.kind = 'corequisite'
    WHERE cp.curriculum_id = target_curriculum_id
      AND cp.semester = p_semester
    ORDER BY cp.position_number;
END;
$$;

REVOKE ALL ON FUNCTION public.nebula_get_subjects_by_semester(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nebula_get_subjects_by_semester(integer) TO anon, authenticated;

COMMIT;

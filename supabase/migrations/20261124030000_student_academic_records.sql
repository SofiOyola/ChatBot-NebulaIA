-- NEBULA 2.0 | Migracion 003: perfiles, historial y planificacion estudiantil
-- Ejecutar UNA vez, con rol postgres, despues de migraciones 001 y 002.
-- Sin datos de estudiantes. No modifica filas del catalogo academico.
BEGIN;

CREATE SCHEMA IF NOT EXISTS student;

-- Cada perfil corresponde a una cuenta de Supabase Auth.
-- El codigo institucional es opcional y distinto del UUID de autenticacion.
CREATE TABLE student.profiles (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    student_code text UNIQUE,
    full_name text,
    curriculum_id text NOT NULL REFERENCES academic.curriculum_versions(curriculum_id),
    current_semester integer CHECK (current_semester BETWEEN 1 AND 9),
    enrollment_status text NOT NULL DEFAULT 'active'
        CHECK (enrollment_status IN ('active','inactive','graduated','suspended','unknown')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, curriculum_id),
    CHECK (student_code IS NULL OR btrim(student_code) <> ''),
    CHECK (full_name IS NULL OR btrim(full_name) <> '')
);

-- Periodos academicos oficiales o provisionales: fechas y codigos no se inventan.
CREATE TABLE student.academic_periods (
    period_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    label text NOT NULL,
    start_date date,
    end_date date,
    is_official boolean NOT NULL DEFAULT false,
    CHECK (btrim(code) <> ''),
    CHECK (btrim(label) <> ''),
    CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date)
);

-- Un intento por asignatura y periodo (repeticiones en otros periodos se conservan).
-- No se deriva aprobado/reprobado solo por nota, hasta verificar las reglas UNAB.
CREATE TABLE student.course_attempts (
    attempt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL,
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    period_id bigint REFERENCES student.academic_periods(period_id),
    attempt_number integer NOT NULL CHECK (attempt_number >= 1),
    final_grade numeric(4,2) CHECK (final_grade BETWEEN 0 AND 5),
    outcome text NOT NULL DEFAULT 'unknown'
        CHECK (outcome IN ('passed','failed','withdrawn','in_progress','unknown')),
    source_type text NOT NULL DEFAULT 'student_reported'
        CHECK (source_type IN ('student_reported','institution_verified','admin_recorded')),
    notes text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, curriculum_id, position_id, attempt_number),
    FOREIGN KEY (user_id, curriculum_id)
        REFERENCES student.profiles(user_id, curriculum_id),
    FOREIGN KEY (curriculum_id, position_id)
        REFERENCES academic.curriculum_positions(curriculum_id, position_id),
    CHECK (outcome <> 'in_progress' OR final_grade IS NULL)
);

-- Matricula real: no confundir con una sugerencia o proyeccion.
CREATE TABLE student.enrollments (
    enrollment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL,
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    period_id bigint NOT NULL REFERENCES student.academic_periods(period_id),
    status text NOT NULL DEFAULT 'enrolled'
        CHECK (status IN ('enrolled','completed','withdrawn','cancelled')),
    source_type text NOT NULL DEFAULT 'student_reported'
        CHECK (source_type IN ('student_reported','institution_verified','admin_recorded')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, period_id, position_id),
    FOREIGN KEY (user_id, curriculum_id)
        REFERENCES student.profiles(user_id, curriculum_id),
    FOREIGN KEY (curriculum_id, position_id)
        REFERENCES academic.curriculum_positions(curriculum_id, position_id)
);

-- Un plan es un escenario, no una matricula confirmada.
CREATE TABLE student.academic_plans (
    plan_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL,
    curriculum_id text NOT NULL,
    target_period_id bigint REFERENCES student.academic_periods(period_id),
    title text NOT NULL DEFAULT 'Plan de matricula',
    status text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','proposed','accepted','archived')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (plan_id, curriculum_id),
    FOREIGN KEY (user_id, curriculum_id)
        REFERENCES student.profiles(user_id, curriculum_id)
);

CREATE TABLE student.planned_courses (
    plan_id bigint NOT NULL,
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    selection_type text NOT NULL DEFAULT 'student_selected'
        CHECK (selection_type IN ('student_selected','system_suggested')),
    recommendation_reason text,
    eligibility_status text NOT NULL DEFAULT 'not_verified'
        CHECK (eligibility_status IN ('eligible','not_eligible','needs_review','not_verified')),
    PRIMARY KEY (plan_id, position_id),
    FOREIGN KEY (plan_id, curriculum_id)
        REFERENCES student.academic_plans(plan_id, curriculum_id) ON DELETE CASCADE,
    FOREIGN KEY (curriculum_id, position_id)
        REFERENCES academic.curriculum_positions(curriculum_id, position_id)
);

CREATE INDEX course_attempts_user_idx ON student.course_attempts (user_id, curriculum_id, position_id);
CREATE INDEX enrollments_user_period_idx ON student.enrollments (user_id, period_id);
CREATE INDEX academic_plans_user_idx ON student.academic_plans (user_id, created_at DESC);

-- Capa privada: sin acceso directo desde las claves anon/authenticated.
REVOKE ALL ON SCHEMA student FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA student FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA student FROM PUBLIC, anon, authenticated;

-- Habilitar RLS en todas las tablas nuevas, aun sin politicas de acceso directo.
ALTER TABLE student.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE student.academic_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE student.course_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE student.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE student.academic_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE student.planned_courses ENABLE ROW LEVEL SECURITY;

COMMIT;

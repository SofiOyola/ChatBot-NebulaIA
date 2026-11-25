-- NEBULA 2.0 | Migracion 001: catalogo academico (estructura, sin datos)
-- Adaptacion del modelo anterior a Supabase PostgreSQL.
-- Ejecutar una sola vez sobre un proyecto limpio, desde SQL Editor como postgres.
-- No contiene credenciales ni datos personales.
-- No ejecuta el guard de nombre de la BD anterior ni comandos exclusivos de psql.
BEGIN;


CREATE SCHEMA IF NOT EXISTS academic;
SET LOCAL search_path = academic, pg_catalog;

CREATE TABLE schema_migrations (
    version integer PRIMARY KEY CHECK (version > 0),
    applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE institutions (
    institution_id text PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE programs (
    program_id text PRIMARY KEY,
    institution_id text NOT NULL REFERENCES institutions,
    name text NOT NULL,
    campus text NOT NULL,
    UNIQUE (program_id, institution_id)
);

CREATE TABLE sources (
    source_id text PRIMARY KEY,
    title text NOT NULL,
    publisher text NOT NULL,
    source_kind text NOT NULL CHECK (source_kind IN ('official', 'third_party')),
    url text NOT NULL CHECK (url LIKE 'https://%'),
    published_on date,
    updated_on date,
    accessed_on date NOT NULL,
    locator text NOT NULL,
    verification_status text NOT NULL CHECK (verification_status IN (
        'student_validated', 'historical', 'documented', 'contextual',
        'excluded', 'pending', 'contradictory'
    )),
    scope text NOT NULL,
    UNIQUE (source_id, source_kind),
    CHECK (verification_status <> 'student_validated' OR source_kind = 'third_party')
);

CREATE TABLE evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_id text NOT NULL,
    source_kind text NOT NULL,
    locator text NOT NULL,
    field_name text NOT NULL,
    observed_value text NOT NULL,
    verification_status text NOT NULL CHECK (verification_status IN (
        'student_validated', 'documented', 'pending', 'contradictory'
    )),
    scope text,
    FOREIGN KEY (source_id, source_kind) REFERENCES sources (source_id, source_kind),
    UNIQUE (source_id, locator, field_name, observed_value, verification_status),
    UNIQUE (evidence_id, source_kind, verification_status),
    CHECK (verification_status <> 'student_validated' OR source_kind = 'third_party')
);

CREATE TABLE curriculum_versions (
    curriculum_id text PRIMARY KEY,
    program_id text NOT NULL,
    institution_id text NOT NULL,
    provisional_version text NOT NULL,
    official_plan_code text,
    official_cohort text,
    term_count integer NOT NULL CHECK (term_count = 9),
    total_credits integer NOT NULL CHECK (total_credits >= 0),
    position_count integer NOT NULL CHECK (position_count > 0),
    evidence_id bigint NOT NULL REFERENCES evidence,
    notes text,
    FOREIGN KEY (program_id, institution_id) REFERENCES programs (program_id, institution_id),
    UNIQUE (curriculum_id, institution_id),
    UNIQUE (curriculum_id, official_cohort),
    UNIQUE (program_id, provisional_version),
    CHECK (official_plan_code IS NULL OR btrim(official_plan_code) <> ''),
    CHECK (official_cohort IS NULL OR btrim(official_cohort) <> '')
);

CREATE TABLE courses (
    course_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    institution_id text NOT NULL REFERENCES institutions,
    name text NOT NULL CHECK (btrim(name) <> ''),
    institutional_code text CHECK (btrim(institutional_code) <> ''),
    code_evidence_id bigint,
    evidence_kind text GENERATED ALWAYS AS ('official'::text) STORED,
    evidence_status text GENERATED ALWAYS AS ('documented'::text) STORED,
    UNIQUE (institution_id, institutional_code),
    UNIQUE (course_id, institution_id),
    CHECK ((institutional_code IS NULL) = (code_evidence_id IS NULL)),
    FOREIGN KEY (code_evidence_id, evidence_kind, evidence_status)
        REFERENCES evidence (evidence_id, source_kind, verification_status)
);

CREATE TABLE curriculum_positions (
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    institution_id text NOT NULL,
    course_id bigint,
    semester integer NOT NULL CHECK (semester BETWEEN 1 AND 9),
    position_number integer NOT NULL CHECK (position_number > 0),
    original_name text NOT NULL CHECK (btrim(original_name) <> ''),
    normalized_name text NOT NULL CHECK (btrim(normalized_name) <> ''),
    credits integer NOT NULL CHECK (credits >= 0),
    category text NOT NULL CHECK (category IN (
        'electiva', 'laboratorio', 'practica', 'actividad_formativa', 'sin_clasificar', 'obligatoria'
    )),
    evidence_id bigint NOT NULL REFERENCES evidence,
    notes text,
    PRIMARY KEY (curriculum_id, position_id),
    UNIQUE (curriculum_id, semester, position_number),
    UNIQUE (curriculum_id, position_id, category),
    FOREIGN KEY (curriculum_id, institution_id)
        REFERENCES curriculum_versions (curriculum_id, institution_id),
    FOREIGN KEY (course_id, institution_id) REFERENCES courses (course_id, institution_id)
);

CREATE TABLE elective_groups (
    curriculum_id text NOT NULL REFERENCES curriculum_versions,
    group_id bigint GENERATED ALWAYS AS IDENTITY,
    label text NOT NULL,
    evidence_id bigint NOT NULL REFERENCES evidence,
    PRIMARY KEY (curriculum_id, group_id)
);

CREATE TABLE elective_slots (
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    category text GENERATED ALWAYS AS ('electiva'::text) STORED,
    group_id bigint,
    PRIMARY KEY (curriculum_id, position_id),
    FOREIGN KEY (curriculum_id, position_id, category)
        REFERENCES curriculum_positions (curriculum_id, position_id, category),
    FOREIGN KEY (curriculum_id, group_id) REFERENCES elective_groups
);

CREATE TABLE requirement_coverage (
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('prerequisite', 'corequisite')),
    coverage text NOT NULL CHECK (coverage IN ('unknown', 'partial', 'complete', 'confirmed_absent')),
    cohort text,
    evidence_id bigint,
    evidence_kind text GENERATED ALWAYS AS ('official'::text) STORED,
    evidence_status text GENERATED ALWAYS AS ('documented'::text) STORED,
    PRIMARY KEY (curriculum_id, position_id, kind),
    UNIQUE (curriculum_id, position_id, kind, coverage),
    FOREIGN KEY (curriculum_id, position_id) REFERENCES curriculum_positions,
    FOREIGN KEY (curriculum_id, cohort) REFERENCES curriculum_versions (curriculum_id, official_cohort),
    FOREIGN KEY (evidence_id, evidence_kind, evidence_status)
        REFERENCES evidence (evidence_id, source_kind, verification_status),
    CHECK (coverage NOT IN ('complete', 'confirmed_absent')
           OR (evidence_id IS NOT NULL AND cohort IS NOT NULL))
);

CREATE TABLE course_requirements (
    curriculum_id text NOT NULL,
    position_id text NOT NULL,
    required_position_id text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('prerequisite', 'corequisite')),
    coverage text NOT NULL CHECK (coverage IN ('partial', 'complete')),
    applicability text NOT NULL CHECK (applicability IN ('cohort_pending', 'applicable')),
    cohort text,
    evidence_id bigint NOT NULL,
    evidence_kind text GENERATED ALWAYS AS ('official'::text) STORED,
    evidence_status text GENERATED ALWAYS AS ('documented'::text) STORED,
    scope text NOT NULL,
    notes text,
    PRIMARY KEY (curriculum_id, position_id, kind, required_position_id),
    CHECK (position_id <> required_position_id),
    CHECK (coverage <> 'complete' OR applicability = 'applicable'),
    CHECK ((applicability = 'applicable') = (cohort IS NOT NULL)),
    FOREIGN KEY (curriculum_id, position_id, kind, coverage)
        REFERENCES requirement_coverage (curriculum_id, position_id, kind, coverage),
    FOREIGN KEY (curriculum_id, required_position_id) REFERENCES curriculum_positions,
    FOREIGN KEY (curriculum_id, cohort) REFERENCES curriculum_versions (curriculum_id, official_cohort),
    FOREIGN KEY (evidence_id, evidence_kind, evidence_status)
        REFERENCES evidence (evidence_id, source_kind, verification_status)
);

CREATE TABLE import_batches (
    batch_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    curriculum_id text NOT NULL UNIQUE REFERENCES curriculum_versions,
    sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    imported_at timestamptz NOT NULL DEFAULT now(),
    summary jsonb NOT NULL CHECK (jsonb_typeof(summary) = 'object')
);

CREATE INDEX positions_search_idx ON curriculum_positions (curriculum_id, normalized_name);
CREATE INDEX positions_course_idx ON curriculum_positions (course_id, institution_id);
CREATE INDEX requirements_reverse_idx ON course_requirements (curriculum_id, required_position_id, kind);

INSERT INTO schema_migrations (version) VALUES (1);

-- Los datos academicos no se exponen directamente al cliente movil.
-- Las funciones autorizadas del backend se definiran en migraciones posteriores.
REVOKE ALL ON SCHEMA academic FROM PUBLIC, anon, authenticated;
DO $rls$
DECLARE t record;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'academic' LOOP
    EXECUTE format('ALTER TABLE academic.%I ENABLE ROW LEVEL SECURITY', t.tablename);
  END LOOP;
END;
$rls$;
COMMIT;

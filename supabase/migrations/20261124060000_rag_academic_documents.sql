-- NEBULA 2.0 | Migracion 006 | RAG-01
-- Documentos academicos comunes y busqueda semantica trazable.
-- No contiene documentos, embeddings, perfiles de estudiantes ni datos personales.
-- Requiere pgvector ya instalado en el esquema extensions.
BEGIN;

DO $extension_check$
DECLARE
    installed_schema text;
BEGIN
    SELECT n.nspname
    INTO installed_schema
    FROM pg_extension AS e
    JOIN pg_namespace AS n ON n.oid = e.extnamespace
    WHERE e.extname = 'vector';

    IF installed_schema IS NULL THEN
        RAISE EXCEPTION 'pgvector extension is required before RAG-01';
    ELSIF installed_schema <> 'extensions' THEN
        RAISE EXCEPTION 'pgvector is installed in schema %, expected extensions; review migration before applying', installed_schema;
    END IF;
END;
$extension_check$;

CREATE SCHEMA IF NOT EXISTS rag;

CREATE TABLE IF NOT EXISTS rag.embedding_profiles (
    profile_id text PRIMARY KEY CHECK (btrim(profile_id) <> ''),
    provider text NOT NULL CHECK (btrim(provider) <> ''),
    model text NOT NULL CHECK (btrim(model) <> ''),
    dimension integer NOT NULL CHECK (dimension BETWEEN 1 AND 16000),
    distance_metric text NOT NULL DEFAULT 'cosine'
        CHECK (distance_metric = 'cosine'),
    normalization text NOT NULL DEFAULT 'model_default'
        CHECK (normalization IN ('model_default', 'unit_length', 'none')),
    status text NOT NULL DEFAULT 'inactive'
        CHECK (status IN ('inactive', 'active', 'retired')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, model, dimension),
    UNIQUE (profile_id, dimension)
);

CREATE UNIQUE INDEX IF NOT EXISTS embedding_profiles_one_active_idx
    ON rag.embedding_profiles ((status))
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS rag.documents (
    document_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text NOT NULL CHECK (btrim(title) <> ''),
    source_url text NOT NULL CHECK (source_url LIKE 'https://%'),
    source_type text NOT NULL CHECK (source_type IN ('official', 'third_party')),
    publisher text CHECK (publisher IS NULL OR btrim(publisher) <> ''),
    published_on date,
    updated_on date,
    accessed_on date NOT NULL,
    validation_status text NOT NULL DEFAULT 'pending'
        CHECK (validation_status IN ('documented', 'pending', 'contradictory', 'excluded')),
    scope text NOT NULL CHECK (btrim(scope) <> ''),
    content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(metadata) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_url, content_sha256),
    CHECK (published_on IS NULL OR updated_on IS NULL OR published_on <= updated_on)
);

CREATE TABLE IF NOT EXISTS rag.document_chunks (
    chunk_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_id bigint NOT NULL REFERENCES rag.documents(document_id) ON DELETE CASCADE,
    chunk_index integer NOT NULL CHECK (chunk_index >= 0),
    locator text NOT NULL CHECK (btrim(locator) <> ''),
    content text NOT NULL CHECK (btrim(content) <> ''),
    token_count integer CHECK (token_count IS NULL OR token_count > 0),
    content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(metadata) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_id, chunk_index),
    UNIQUE (document_id, content_sha256)
);

CREATE TABLE IF NOT EXISTS rag.chunk_embeddings (
    chunk_id bigint NOT NULL REFERENCES rag.document_chunks(chunk_id) ON DELETE CASCADE,
    profile_id text NOT NULL,
    embedding_dimension integer NOT NULL,
    embedding extensions.vector NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (chunk_id, profile_id),
    FOREIGN KEY (profile_id, embedding_dimension)
        REFERENCES rag.embedding_profiles(profile_id, dimension),
    CHECK (extensions.vector_dims(embedding) = embedding_dimension),
    CHECK (extensions.vector_norm(embedding) > 0)
);

CREATE INDEX IF NOT EXISTS document_chunks_document_idx
    ON rag.document_chunks (document_id, chunk_index);
CREATE INDEX IF NOT EXISTS chunk_embeddings_profile_idx
    ON rag.chunk_embeddings (profile_id, chunk_id);

ALTER TABLE rag.embedding_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE rag.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE rag.document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE rag.chunk_embeddings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON SCHEMA rag FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA rag FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA rag FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks(
    p_query_embedding extensions.vector,
    p_profile_id text,
    p_match_count integer DEFAULT 5,
    p_min_similarity real DEFAULT 0
)
RETURNS TABLE (
    chunk_id bigint,
    document_id bigint,
    document_title text,
    source_url text,
    source_type text,
    accessed_on date,
    validation_status text,
    locator text,
    content text,
    metadata jsonb,
    similarity real
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    expected_dimension integer;
BEGIN
    IF p_query_embedding IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'p_query_embedding is required';
    END IF;
    IF extensions.vector_norm(p_query_embedding) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'p_query_embedding must have non-zero norm';
    END IF;
    IF p_match_count IS NULL OR p_match_count NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'p_match_count must be between 1 and 20';
    END IF;
    IF p_min_similarity IS NULL OR p_min_similarity NOT BETWEEN 0 AND 1 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'p_min_similarity must be between 0 and 1';
    END IF;
    IF p_profile_id IS NULL OR btrim(p_profile_id) = '' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'p_profile_id is required';
    END IF;

    SELECT ep.dimension
    INTO expected_dimension
    FROM rag.embedding_profiles AS ep
    WHERE ep.profile_id = p_profile_id
      AND ep.status = 'active'
      AND ep.distance_metric = 'cosine';

    IF expected_dimension IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'active embedding profile was not found';
    END IF;
    IF extensions.vector_dims(p_query_embedding) <> expected_dimension THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'query embedding dimension does not match the active profile';
    END IF;

    RETURN QUERY
    SELECT
        dc.chunk_id,
        d.document_id,
        d.title AS document_title,
        d.source_url,
        d.source_type,
        d.accessed_on,
        d.validation_status,
        dc.locator,
        dc.content,
        dc.metadata,
        (1 - (ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real AS similarity
    FROM rag.chunk_embeddings AS ce
    JOIN rag.document_chunks AS dc ON dc.chunk_id = ce.chunk_id
    JOIN rag.documents AS d ON d.document_id = dc.document_id
    WHERE ce.profile_id = p_profile_id
      AND d.validation_status = 'documented'
      AND (1 - (ce.embedding OPERATOR(extensions.<=>) p_query_embedding)) >= p_min_similarity
    ORDER BY ce.embedding OPERATOR(extensions.<=>) p_query_embedding, dc.chunk_id
    LIMIT p_match_count;
END;
$$;

-- SECURITY DEFINER nunca debe quedar en manos de un rol cliente.
DO $function_owner_check$
DECLARE
    function_owner text;
BEGIN
    SELECT r.rolname
    INTO function_owner
    FROM pg_proc AS p
    JOIN pg_roles AS r ON r.oid = p.proowner
    WHERE p.oid = 'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::regprocedure;

    IF function_owner IS NULL THEN
        RAISE EXCEPTION 'nebula_search_academic_chunks was not created';
    ELSIF function_owner IN ('anon', 'authenticated', 'service_role') THEN
        RAISE EXCEPTION 'unsafe owner % for nebula_search_academic_chunks', function_owner;
    END IF;
END;
$function_owner_check$;

REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(extensions.vector, text, integer, real)
    FROM PUBLIC, anon, authenticated;

COMMIT;

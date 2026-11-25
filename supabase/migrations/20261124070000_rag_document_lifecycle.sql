-- NEBULA 2.0 | Migracion 007 | RAG-01 lifecycle
-- Una revision nueva queda pendiente y retira temporalmente la version anterior.
BEGIN;

ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS is_current boolean NOT NULL DEFAULT false;
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS supersedes_document_id bigint;

DO $constraints$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_supersedes_document_fkey'
                   AND conrelid = 'rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_supersedes_document_fkey
            FOREIGN KEY (supersedes_document_id) REFERENCES rag.documents(document_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'documents_current_requires_documented'
                   AND conrelid = 'rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_current_requires_documented
            CHECK (NOT is_current OR validation_status = 'documented');
    END IF;
END;
$constraints$;

CREATE UNIQUE INDEX IF NOT EXISTS documents_one_current_source_idx
    ON rag.documents (source_url) WHERE is_current;

CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks(
    p_query_embedding extensions.vector,
    p_profile_id text,
    p_match_count integer DEFAULT 5,
    p_min_similarity real DEFAULT 0
)
RETURNS TABLE (
    chunk_id bigint, document_id bigint, document_title text, source_url text,
    source_type text, accessed_on date, validation_status text, locator text,
    content text, metadata jsonb, similarity real
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE expected_dimension integer;
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
    SELECT ep.dimension INTO expected_dimension FROM rag.embedding_profiles ep
    WHERE ep.profile_id = p_profile_id AND ep.status = 'active' AND ep.distance_metric = 'cosine';
    IF expected_dimension IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'active embedding profile was not found';
    END IF;
    IF extensions.vector_dims(p_query_embedding) <> expected_dimension THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'query embedding dimension does not match the active profile';
    END IF;
    RETURN QUERY
    SELECT dc.chunk_id, d.document_id, d.title, d.source_url, d.source_type, d.accessed_on,
           d.validation_status, dc.locator, dc.content, dc.metadata,
           (1 - (ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real
    FROM rag.chunk_embeddings ce
    JOIN rag.document_chunks dc ON dc.chunk_id = ce.chunk_id
    JOIN rag.documents d ON d.document_id = dc.document_id
    WHERE ce.profile_id = p_profile_id AND d.validation_status = 'documented' AND d.is_current
      AND (1 - (ce.embedding OPERATOR(extensions.<=>) p_query_embedding)) >= p_min_similarity
    ORDER BY ce.embedding OPERATOR(extensions.<=>) p_query_embedding, dc.chunk_id
    LIMIT p_match_count;
END;
$$;

DO $owner_check$
DECLARE owner_name text;
BEGIN
    SELECT r.rolname INTO owner_name FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid = 'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::regprocedure;
    IF owner_name IS NULL OR owner_name IN ('anon', 'authenticated', 'service_role') THEN
        RAISE EXCEPTION 'unsafe owner for nebula_search_academic_chunks';
    END IF;
END;
$owner_check$;

REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(extensions.vector,text,integer,real)
    FROM PUBLIC, anon, authenticated;
COMMIT;

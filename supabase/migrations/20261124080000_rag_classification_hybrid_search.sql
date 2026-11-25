-- NEBULA 2.0 | Migracion 008 | Clasificacion documental y busqueda hibrida segura
BEGIN;

ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS information_type text NOT NULL DEFAULT 'general';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS authority_level text NOT NULL DEFAULT 'institutional_informative';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS validity_status text NOT NULL DEFAULT 'pending_review';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS curriculum_scope text NOT NULL DEFAULT 'unknown';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS program_key text;
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS effective_from date;
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS effective_to date;

-- Una instalacion previa con documentos aprobados conserva coherencia al incorporar vigencia.
UPDATE rag.documents SET validity_status = 'current'
WHERE is_current AND validation_status = 'documented' AND validity_status = 'pending_review';

DO $classification_constraints$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_information_type_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_information_type_check CHECK (
            information_type IN ('institutional_policy','academic_curriculum','university_services',
                'libraries','news_events','calls','research','general'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_authority_level_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_authority_level_check CHECK (
            authority_level IN ('institutional_normative','institutional_informative',
                'external_academic','secondary'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_validity_status_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_validity_status_check CHECK (
            validity_status IN ('current','pending_review','superseded','historical','undetermined'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_curriculum_scope_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_curriculum_scope_check CHECK (
            curriculum_scope IN ('old_9s_151c','new_2027_8s_134c','general','unknown'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_current_requires_validity_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_current_requires_validity_check CHECK (
            NOT is_current OR (validation_status='documented' AND validity_status='current'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='documents_effective_dates_check'
                   AND conrelid='rag.documents'::regclass) THEN
        ALTER TABLE rag.documents ADD CONSTRAINT documents_effective_dates_check CHECK (
            effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to);
    END IF;
END;
$classification_constraints$;

ALTER TABLE rag.document_chunks ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (pg_catalog.to_tsvector('pg_catalog.spanish'::regconfig, content)) STORED;
CREATE INDEX IF NOT EXISTS document_chunks_search_vector_idx
    ON rag.document_chunks USING gin (search_vector);
CREATE INDEX IF NOT EXISTS documents_retrieval_filter_idx
    ON rag.documents (curriculum_scope, validity_status, authority_level)
    WHERE is_current AND validation_status='documented';

-- Mantiene la RPC original, pero la hace segura por defecto para el plan antiguo.
CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks(
    p_query_embedding extensions.vector, p_profile_id text,
    p_match_count integer DEFAULT 5, p_min_similarity real DEFAULT 0
)
RETURNS TABLE (chunk_id bigint, document_id bigint, document_title text, source_url text,
    source_type text, accessed_on date, validation_status text, locator text, content text,
    metadata jsonb, similarity real)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE expected_dimension integer;
BEGIN
    IF p_query_embedding IS NULL OR extensions.vector_norm(p_query_embedding) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='valid p_query_embedding is required';
    END IF;
    IF p_match_count IS NULL OR p_match_count NOT BETWEEN 1 AND 20 OR
       p_min_similarity IS NULL OR p_min_similarity NOT BETWEEN 0 AND 1 OR
       p_profile_id IS NULL OR pg_catalog.btrim(p_profile_id)='' THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid search parameters';
    END IF;
    SELECT dimension INTO expected_dimension FROM rag.embedding_profiles
    WHERE profile_id=p_profile_id AND status='active' AND distance_metric='cosine';
    IF expected_dimension IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='active embedding profile was not found';
    END IF;
    IF extensions.vector_dims(p_query_embedding) <> expected_dimension THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='query embedding dimension does not match the active profile';
    END IF;
    RETURN QUERY SELECT dc.chunk_id,d.document_id,d.title,d.source_url,d.source_type,d.accessed_on,
        d.validation_status,dc.locator,dc.content,dc.metadata,
        (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real
    FROM rag.chunk_embeddings ce JOIN rag.document_chunks dc USING(chunk_id)
    JOIN rag.documents d USING(document_id)
    WHERE ce.profile_id=p_profile_id AND d.validation_status='documented' AND d.is_current
      AND d.validity_status='current' AND d.curriculum_scope IN ('general','old_9s_151c')
      AND (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding)) >= p_min_similarity
    ORDER BY ce.embedding OPERATOR(extensions.<=>) p_query_embedding, dc.chunk_id LIMIT p_match_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks_hybrid(
    p_query_text text, p_query_embedding extensions.vector, p_profile_id text,
    p_curriculum_scope text DEFAULT 'old_9s_151c', p_match_count integer DEFAULT 5,
    p_min_similarity real DEFAULT 0
)
RETURNS TABLE (chunk_id bigint, document_id bigint, document_title text, source_url text,
    source_type text, accessed_on date, locator text, content text, metadata jsonb,
    information_type text, authority_level text, curriculum_scope text,
    semantic_similarity real, lexical_score real, rank_score real)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE expected_dimension integer; query_terms tsquery;
BEGIN
    IF p_query_text IS NULL OR pg_catalog.btrim(p_query_text)='' OR pg_catalog.length(p_query_text)>2000 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='valid p_query_text is required';
    END IF;
    IF p_curriculum_scope NOT IN ('old_9s_151c','general') THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='unsupported curriculum scope';
    END IF;
    IF p_query_embedding IS NULL OR extensions.vector_norm(p_query_embedding)<=0 OR
       p_match_count IS NULL OR p_match_count NOT BETWEEN 1 AND 20 OR
       p_min_similarity IS NULL OR p_min_similarity NOT BETWEEN 0 AND 1 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid search parameters';
    END IF;
    SELECT dimension INTO expected_dimension FROM rag.embedding_profiles
    WHERE profile_id=p_profile_id AND status='active' AND distance_metric='cosine';
    IF expected_dimension IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='active embedding profile was not found';
    END IF;
    IF extensions.vector_dims(p_query_embedding)<>expected_dimension THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='query embedding dimension does not match the active profile';
    END IF;
    query_terms := pg_catalog.websearch_to_tsquery('pg_catalog.spanish'::regconfig,p_query_text);
    RETURN QUERY WITH scored AS (
        SELECT dc.chunk_id,d.document_id,d.title,d.source_url,d.source_type,d.accessed_on,
            dc.locator,dc.content,dc.metadata,d.information_type,d.authority_level,d.curriculum_scope,
            (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real AS semantic_similarity,
            LEAST(pg_catalog.ts_rank_cd(dc.search_vector,query_terms),1)::real AS lexical_score
        FROM rag.chunk_embeddings ce JOIN rag.document_chunks dc USING(chunk_id)
        JOIN rag.documents d USING(document_id)
        WHERE ce.profile_id=p_profile_id AND d.validation_status='documented' AND d.is_current
          AND d.validity_status='current'
          AND (d.curriculum_scope='general' OR d.curriculum_scope=p_curriculum_scope)
          AND (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding)) >= p_min_similarity
    ) SELECT s.*,(0.75*s.semantic_similarity + 0.20*s.lexical_score +
        CASE s.authority_level WHEN 'institutional_normative' THEN 0.05
             WHEN 'institutional_informative' THEN 0.03 WHEN 'external_academic' THEN 0.01 ELSE 0 END)::real
      FROM scored s ORDER BY 15 DESC, s.chunk_id LIMIT p_match_count;
END;
$$;

DO $safe_owners$
DECLARE unsafe_count integer;
BEGIN
    SELECT count(*) INTO unsafe_count FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
    WHERE p.oid IN (
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::regprocedure,
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::regprocedure)
      AND r.rolname IN ('anon','authenticated','service_role');
    IF unsafe_count<>0 THEN RAISE EXCEPTION 'unsafe owner for RAG search function'; END IF;
END;
$safe_owners$;

REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(extensions.vector,text,integer,real)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)
    FROM PUBLIC, anon, authenticated;
COMMIT;

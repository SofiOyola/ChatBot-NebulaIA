-- NEBULA 2.0 | Migracion 011 | Metadatos de autorizacion y exclusion de material demo
BEGIN;

ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS content_class text NOT NULL DEFAULT 'institutional';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS authorization_status text NOT NULL DEFAULT 'pending';
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS authorization_reference text;
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS authorization_date date;

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
      WHERE conrelid='rag.documents'::pg_catalog.regclass AND conname='documents_content_class_check') THEN
    ALTER TABLE rag.documents ADD CONSTRAINT documents_content_class_check
      CHECK (content_class IN ('institutional','demo_non_institutional'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
      WHERE conrelid='rag.documents'::pg_catalog.regclass AND conname='documents_authorization_status_check') THEN
    ALTER TABLE rag.documents ADD CONSTRAINT documents_authorization_status_check
      CHECK (authorization_status IN ('pending','approved','rejected','not_required'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
      WHERE conrelid='rag.documents'::pg_catalog.regclass AND conname='documents_demo_safety_check') THEN
    ALTER TABLE rag.documents ADD CONSTRAINT documents_demo_safety_check CHECK (
      content_class<>'demo_non_institutional' OR (
        source_type='third_party' AND authority_level='secondary' AND information_type='general'
        AND curriculum_scope='general' AND authorization_status='approved'
        AND publisher IS NOT NULL AND pg_catalog.btrim(publisher)<>''
        AND authorization_reference IS NOT NULL AND pg_catalog.btrim(authorization_reference)<>''
        AND authorization_date IS NOT NULL
        AND metadata @> '{"demo_non_institutional":true}'::pg_catalog.jsonb
        AND metadata->'authorization'->>'status'='approved'
      ));
  END IF;
END;
$constraints$;

GRANT INSERT (content_class,authorization_status,authorization_reference,authorization_date)
  ON rag.documents TO nebula_rag_ingest;

CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks(
  p_query_embedding extensions.vector,p_profile_id text,
  p_match_count integer DEFAULT 5,p_min_similarity real DEFAULT 0)
RETURNS TABLE (chunk_id bigint,document_id bigint,document_title text,source_url text,
  source_type text,accessed_on date,validation_status text,locator text,content text,
  metadata jsonb,similarity real)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE expected_dimension integer;
BEGIN
  IF p_query_embedding IS NULL OR extensions.vector_norm(p_query_embedding)<=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='valid p_query_embedding is required';
  END IF;
  IF p_match_count IS NULL OR p_match_count NOT BETWEEN 1 AND 20 OR
     p_min_similarity IS NULL OR p_min_similarity NOT BETWEEN 0 AND 1 OR
     p_profile_id IS NULL OR pg_catalog.btrim(p_profile_id)='' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid search parameters';
  END IF;
  SELECT dimension INTO expected_dimension FROM rag.embedding_profiles
  WHERE profile_id=p_profile_id AND status='active' AND distance_metric='cosine';
  IF expected_dimension IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='active embedding profile was not found';
  END IF;
  IF extensions.vector_dims(p_query_embedding)<>expected_dimension THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='query embedding dimension does not match the active profile';
  END IF;
  RETURN QUERY SELECT dc.chunk_id,d.document_id,d.title,d.source_url,d.source_type,d.accessed_on,
    d.validation_status,dc.locator,dc.content,dc.metadata,
    (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real
  FROM rag.chunk_embeddings ce JOIN rag.document_chunks dc USING(chunk_id)
  JOIN rag.documents d USING(document_id)
  WHERE ce.profile_id=p_profile_id AND d.validation_status='documented' AND d.is_current
    AND d.validity_status='current' AND d.content_class='institutional'
    AND d.curriculum_scope IN ('general','old_9s_151c')
    AND (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))>=p_min_similarity
  ORDER BY ce.embedding OPERATOR(extensions.<=>) p_query_embedding,dc.chunk_id LIMIT p_match_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks_hybrid(
  p_query_text text,p_query_embedding extensions.vector,p_profile_id text,
  p_curriculum_scope text DEFAULT 'old_9s_151c',p_match_count integer DEFAULT 5,
  p_min_similarity real DEFAULT 0)
RETURNS TABLE (chunk_id bigint,document_id bigint,document_title text,source_url text,
  source_type text,accessed_on date,locator text,content text,metadata jsonb,
  information_type text,authority_level text,curriculum_scope text,
  semantic_similarity real,lexical_score real,rank_score real)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE expected_dimension integer;query_terms tsquery;
BEGIN
  IF p_query_text IS NULL OR pg_catalog.btrim(p_query_text)='' OR pg_catalog.length(p_query_text)>2000 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='valid p_query_text is required';
  END IF;
  IF p_curriculum_scope NOT IN ('old_9s_151c','general') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unsupported curriculum scope';
  END IF;
  IF p_query_embedding IS NULL OR extensions.vector_norm(p_query_embedding)<=0 OR
     p_match_count IS NULL OR p_match_count NOT BETWEEN 1 AND 20 OR
     p_min_similarity IS NULL OR p_min_similarity NOT BETWEEN 0 AND 1 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid search parameters';
  END IF;
  SELECT dimension INTO expected_dimension FROM rag.embedding_profiles
  WHERE profile_id=p_profile_id AND status='active' AND distance_metric='cosine';
  IF expected_dimension IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='active embedding profile was not found';
  END IF;
  IF extensions.vector_dims(p_query_embedding)<>expected_dimension THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='query embedding dimension does not match the active profile';
  END IF;
  query_terms:=pg_catalog.websearch_to_tsquery('pg_catalog.spanish'::pg_catalog.regconfig,p_query_text);
  RETURN QUERY WITH scored AS (
    SELECT dc.chunk_id,d.document_id,d.title,d.source_url,d.source_type,d.accessed_on,
      dc.locator,dc.content,dc.metadata,d.information_type,d.authority_level,d.curriculum_scope,
      (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))::real AS semantic_similarity,
      LEAST(pg_catalog.ts_rank_cd(dc.search_vector,query_terms),1)::real AS lexical_score
    FROM rag.chunk_embeddings ce JOIN rag.document_chunks dc USING(chunk_id)
    JOIN rag.documents d USING(document_id)
    WHERE ce.profile_id=p_profile_id AND d.validation_status='documented' AND d.is_current
      AND d.validity_status='current' AND d.content_class='institutional'
      AND (d.curriculum_scope='general' OR d.curriculum_scope=p_curriculum_scope)
      AND (1-(ce.embedding OPERATOR(extensions.<=>) p_query_embedding))>=p_min_similarity
  ) SELECT s.*,(0.75*s.semantic_similarity+0.20*s.lexical_score+
      CASE s.authority_level WHEN 'institutional_normative' THEN 0.05
      WHEN 'institutional_informative' THEN 0.03 WHEN 'external_academic' THEN 0.01 ELSE 0 END)::real
    FROM scored s ORDER BY 15 DESC,s.chunk_id LIMIT p_match_count;
END;
$$;

DO $security$
DECLARE unsafe_count integer;
BEGIN
  SELECT pg_catalog.count(*) INTO unsafe_count FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
  WHERE p.oid IN (
    'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::pg_catalog.regprocedure,
    'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)'::pg_catalog.regprocedure)
    AND (NOT p.prosecdef OR NOT p.proconfig @> ARRAY['search_path=""'] OR
         r.rolname IN ('anon','authenticated','service_role','nebula_rag_api'));
  IF unsafe_count<>0 THEN RAISE EXCEPTION 'unsafe RAG search function security attributes'; END IF;
END;
$security$;

REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(extensions.vector,text,integer,real)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)
  FROM PUBLIC,anon,authenticated;
DO $service_role_revoke$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
    REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks(extensions.vector,text,integer,real)
      FROM service_role;
    REVOKE ALL ON FUNCTION public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)
      FROM service_role;
  END IF;
END;
$service_role_revoke$;
GRANT EXECUTE ON FUNCTION public.nebula_search_academic_chunks(extensions.vector,text,integer,real)
  TO nebula_rag_api;
GRANT EXECUTE ON FUNCTION public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)
  TO nebula_rag_api;

COMMIT;

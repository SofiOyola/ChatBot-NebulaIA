-- NEBULA 2.0 | Migracion 010 | Ingesta y revision RAG con privilegios separados
BEGIN;

DO $roles$
DECLARE role_row pg_catalog.pg_roles%ROWTYPE; role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['nebula_rag_ingest','nebula_rag_reviewer'] LOOP
    SELECT * INTO role_row FROM pg_catalog.pg_roles WHERE rolname=role_name;
    IF NOT FOUND THEN
      EXECUTE pg_catalog.format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',role_name);
    ELSIF role_row.rolcanlogin OR role_row.rolsuper OR role_row.rolcreatedb OR role_row.rolcreaterole OR
          role_row.rolreplication OR role_row.rolbypassrls THEN
      RAISE EXCEPTION 'existing role % has unsafe attributes',role_name;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member=role_row.oid) THEN
      RAISE EXCEPTION 'role % must not inherit another role',role_name;
    END IF;
  END LOOP;
END;
$roles$;

-- SESSION_USER conserva la identidad del login incluso si una conexion hace SET ROLE.
-- CURRENT_USER identificaria al rol grupal en ese caso y debilitaria el aislamiento.
ALTER TABLE rag.documents ADD COLUMN IF NOT EXISTS ingested_by name NOT NULL DEFAULT SESSION_USER;

REVOKE ALL ON SCHEMA rag FROM nebula_rag_ingest,nebula_rag_reviewer;
REVOKE ALL ON ALL TABLES IN SCHEMA rag FROM nebula_rag_ingest,nebula_rag_reviewer;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA rag FROM nebula_rag_ingest,nebula_rag_reviewer;
GRANT USAGE ON SCHEMA rag,extensions TO nebula_rag_ingest;
GRANT USAGE ON SCHEMA rag,public TO nebula_rag_reviewer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA rag TO nebula_rag_ingest;

GRANT SELECT ON rag.embedding_profiles TO nebula_rag_ingest,nebula_rag_reviewer;
GRANT SELECT ON rag.documents,rag.document_chunks,rag.chunk_embeddings TO nebula_rag_reviewer;
GRANT SELECT ON rag.documents,rag.document_chunks,rag.chunk_embeddings TO nebula_rag_ingest;
GRANT INSERT (title,source_url,source_type,publisher,published_on,updated_on,accessed_on,
  validation_status,scope,content_sha256,metadata,is_current,information_type,authority_level,
  validity_status,curriculum_scope,program_key,effective_from,effective_to)
  ON rag.documents TO nebula_rag_ingest;
GRANT INSERT (document_id,chunk_index,locator,content,token_count,content_sha256,metadata)
  ON rag.document_chunks TO nebula_rag_ingest;
GRANT INSERT (chunk_id,profile_id,embedding_dimension,embedding)
  ON rag.chunk_embeddings TO nebula_rag_ingest;
GRANT UPDATE (embedding_dimension,embedding,created_at)
  ON rag.chunk_embeddings TO nebula_rag_ingest;

DROP POLICY IF EXISTS rag_profiles_ingest_read ON rag.embedding_profiles;
DROP POLICY IF EXISTS rag_profiles_reviewer_read ON rag.embedding_profiles;
DROP POLICY IF EXISTS rag_documents_ingest_read ON rag.documents;
DROP POLICY IF EXISTS rag_documents_ingest_insert ON rag.documents;
DROP POLICY IF EXISTS rag_documents_reviewer_read ON rag.documents;
DROP POLICY IF EXISTS rag_chunks_ingest_read ON rag.document_chunks;
DROP POLICY IF EXISTS rag_chunks_ingest_insert ON rag.document_chunks;
DROP POLICY IF EXISTS rag_chunks_reviewer_read ON rag.document_chunks;
DROP POLICY IF EXISTS rag_embeddings_ingest_read ON rag.chunk_embeddings;
DROP POLICY IF EXISTS rag_embeddings_ingest_insert ON rag.chunk_embeddings;
DROP POLICY IF EXISTS rag_embeddings_ingest_update ON rag.chunk_embeddings;
DROP POLICY IF EXISTS rag_embeddings_reviewer_read ON rag.chunk_embeddings;

CREATE POLICY rag_profiles_ingest_read ON rag.embedding_profiles FOR SELECT TO nebula_rag_ingest USING (true);
CREATE POLICY rag_profiles_reviewer_read ON rag.embedding_profiles FOR SELECT TO nebula_rag_reviewer USING (true);
CREATE POLICY rag_documents_ingest_read ON rag.documents FOR SELECT TO nebula_rag_ingest
  USING (ingested_by=SESSION_USER);
CREATE POLICY rag_documents_ingest_insert ON rag.documents FOR INSERT TO nebula_rag_ingest
  WITH CHECK (ingested_by=SESSION_USER AND validation_status='pending' AND NOT is_current
              AND reviewed_at IS NULL AND validity_status='pending_review');
CREATE POLICY rag_documents_reviewer_read ON rag.documents FOR SELECT TO nebula_rag_reviewer USING (true);
CREATE POLICY rag_chunks_ingest_read ON rag.document_chunks FOR SELECT TO nebula_rag_ingest
  USING (EXISTS (SELECT 1 FROM rag.documents d WHERE d.document_id=document_chunks.document_id
                 AND d.ingested_by=SESSION_USER));
CREATE POLICY rag_chunks_ingest_insert ON rag.document_chunks FOR INSERT TO nebula_rag_ingest
  WITH CHECK (EXISTS (SELECT 1 FROM rag.documents d WHERE d.document_id=document_chunks.document_id
                      AND d.ingested_by=SESSION_USER AND d.validation_status='pending' AND NOT d.is_current));
CREATE POLICY rag_chunks_reviewer_read ON rag.document_chunks FOR SELECT TO nebula_rag_reviewer USING (true);
CREATE POLICY rag_embeddings_ingest_read ON rag.chunk_embeddings FOR SELECT TO nebula_rag_ingest
  USING (EXISTS (SELECT 1 FROM rag.document_chunks dc JOIN rag.documents d USING(document_id)
                 WHERE dc.chunk_id=chunk_embeddings.chunk_id AND d.ingested_by=SESSION_USER));
CREATE POLICY rag_embeddings_ingest_insert ON rag.chunk_embeddings FOR INSERT TO nebula_rag_ingest
  WITH CHECK (EXISTS (SELECT 1 FROM rag.document_chunks dc JOIN rag.documents d USING(document_id)
                      WHERE dc.chunk_id=chunk_embeddings.chunk_id AND d.ingested_by=SESSION_USER
                        AND d.validation_status='pending' AND NOT d.is_current));
CREATE POLICY rag_embeddings_ingest_update ON rag.chunk_embeddings FOR UPDATE TO nebula_rag_ingest
  USING (EXISTS (SELECT 1 FROM rag.document_chunks dc JOIN rag.documents d USING(document_id)
                 WHERE dc.chunk_id=chunk_embeddings.chunk_id AND d.ingested_by=SESSION_USER
                   AND d.validation_status='pending' AND NOT d.is_current))
  WITH CHECK (EXISTS (SELECT 1 FROM rag.document_chunks dc JOIN rag.documents d USING(document_id)
                      WHERE dc.chunk_id=chunk_embeddings.chunk_id AND d.ingested_by=SESSION_USER
                        AND d.validation_status='pending' AND NOT d.is_current));
CREATE POLICY rag_embeddings_reviewer_read ON rag.chunk_embeddings FOR SELECT TO nebula_rag_reviewer USING (true);

CREATE OR REPLACE FUNCTION public.nebula_review_rag_document(
  p_document_id bigint,p_action text,p_profile_id text DEFAULT NULL)
RETURNS TABLE(out_document_id bigint,out_validation_status text,out_is_current boolean)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$
DECLARE target_url text; previous_id bigint; chunk_count integer; missing_count integer;
BEGIN
  IF p_action NOT IN ('approve','reject') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unsupported review action';
  END IF;
  SELECT d.source_url INTO target_url FROM rag.documents d
  WHERE d.document_id=p_document_id AND d.validation_status='pending' AND NOT d.is_current FOR UPDATE;
  IF target_url IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='pending document was not found'; END IF;
  IF p_action='approve' THEN
    IF p_profile_id IS NULL OR NOT EXISTS (SELECT 1 FROM rag.embedding_profiles ep
      WHERE ep.profile_id=p_profile_id AND ep.status IN ('inactive','active') AND ep.distance_metric='cosine') THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='approved embedding profile is required';
    END IF;
    SELECT count(*) INTO chunk_count FROM rag.document_chunks dc WHERE dc.document_id=p_document_id;
    SELECT count(*) INTO missing_count FROM rag.document_chunks dc
    LEFT JOIN rag.chunk_embeddings ce ON ce.chunk_id=dc.chunk_id AND ce.profile_id=p_profile_id
    WHERE dc.document_id=p_document_id AND ce.chunk_id IS NULL;
    IF chunk_count=0 OR missing_count<>0 THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='all document chunks require the approved embedding profile';
    END IF;
    SELECT d.document_id INTO previous_id FROM rag.documents d
    WHERE d.source_url=target_url AND d.is_current AND d.document_id<>p_document_id FOR UPDATE;
    IF previous_id IS NOT NULL THEN
      UPDATE rag.documents SET is_current=false,validity_status='superseded',updated_at=pg_catalog.now()
      WHERE document_id=previous_id;
    END IF;
    UPDATE rag.documents SET validation_status='documented',validity_status='current',is_current=true,
      reviewed_at=pg_catalog.now(),updated_at=pg_catalog.now(),supersedes_document_id=previous_id
    WHERE document_id=p_document_id;
  ELSE
    UPDATE rag.documents SET validation_status='excluded',validity_status='undetermined',is_current=false,
      reviewed_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE document_id=p_document_id;
  END IF;
  RETURN QUERY SELECT d.document_id,d.validation_status,d.is_current
    FROM rag.documents d WHERE d.document_id=p_document_id;
END;
$$;

DO $owner$
DECLARE owner_name text;
BEGIN
  SELECT r.rolname INTO owner_name FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
  WHERE p.oid='public.nebula_review_rag_document(bigint,text,text)'::pg_catalog.regprocedure;
  IF owner_name IS NULL OR owner_name IN ('anon','authenticated','service_role','nebula_rag_api',
      'nebula_rag_ingest','nebula_rag_reviewer') THEN RAISE EXCEPTION 'unsafe review function owner'; END IF;
END;
$owner$;
REVOKE ALL ON FUNCTION public.nebula_review_rag_document(bigint,text,text)
  FROM PUBLIC,anon,authenticated,nebula_rag_api,nebula_rag_ingest;
DO $service_role_revoke$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
    REVOKE ALL ON FUNCTION public.nebula_review_rag_document(bigint,text,text) FROM service_role;
  END IF;
END;
$service_role_revoke$;
GRANT EXECUTE ON FUNCTION public.nebula_review_rag_document(bigint,text,text) TO nebula_rag_reviewer;

COMMIT;

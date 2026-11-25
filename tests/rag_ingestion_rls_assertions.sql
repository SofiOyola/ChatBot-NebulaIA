\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE rag_ingest_test_a NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest_test_b NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_reviewer_test NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT nebula_rag_ingest TO rag_ingest_test_a,rag_ingest_test_b;
GRANT nebula_rag_reviewer TO rag_reviewer_test;

SET SESSION AUTHORIZATION rag_ingest_test_a;
INSERT INTO rag.documents(title,source_url,source_type,accessed_on,validation_status,scope,
  content_sha256,metadata,is_current,information_type,authority_level,validity_status,curriculum_scope)
VALUES ('Ingest A','https://rls.invalid/a','official',DATE '2026-11-25','pending','test',repeat('1',64),
  '{}',false,'institutional_policy','institutional_normative','pending_review','general');
INSERT INTO rag.document_chunks(document_id,chunk_index,locator,content,content_sha256)
SELECT document_id,0,'fixture:a','content a',repeat('2',64) FROM rag.documents WHERE source_url='https://rls.invalid/a';
INSERT INTO rag.chunk_embeddings(chunk_id,profile_id,embedding_dimension,embedding)
SELECT dc.chunk_id,'synthetic-3d',3,'[1,0,0]'::extensions.vector FROM rag.document_chunks dc
JOIN rag.documents d USING(document_id) WHERE d.source_url='https://rls.invalid/a';

RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION rag_ingest_test_b;
INSERT INTO rag.documents(title,source_url,source_type,accessed_on,validation_status,scope,
  content_sha256,metadata,is_current,information_type,authority_level,validity_status,curriculum_scope)
VALUES ('Ingest B','https://rls.invalid/b','official',DATE '2026-11-25','pending','test',repeat('3',64),
  '{}',false,'institutional_policy','institutional_normative','pending_review','general');
INSERT INTO rag.document_chunks(document_id,chunk_index,locator,content,content_sha256)
SELECT document_id,0,'fixture:b','content b',repeat('4',64) FROM rag.documents WHERE source_url='https://rls.invalid/b';

RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION rag_ingest_test_a;
DO $negative_ingest$
BEGIN
  IF (SELECT count(*) FROM rag.documents WHERE source_url='https://rls.invalid/a')<>1 OR
     (SELECT count(*) FROM rag.documents WHERE source_url='https://rls.invalid/b')<>0 THEN
    RAISE EXCEPTION 'ingestion ownership isolation failed';
  END IF;
  BEGIN
    UPDATE rag.documents SET validation_status='documented' WHERE source_url='https://rls.invalid/a';
    RAISE EXCEPTION 'ingestor changed document review state';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO rag.document_chunks(document_id,chunk_index,locator,content,content_sha256)
    SELECT document_id,1,'fixture:foreign','forbidden',repeat('5',64)
    FROM rag.documents WHERE source_url='https://rls.invalid/b';
    IF FOUND THEN RAISE EXCEPTION 'ingestor inserted a chunk for another owner'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE rag.embedding_profiles SET status='retired' WHERE profile_id='synthetic-3d';
    RAISE EXCEPTION 'ingestor activated or retired a profile';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM * FROM public.nebula_review_rag_document(
      (SELECT document_id FROM rag.documents WHERE source_url='https://rls.invalid/a'),'approve','synthetic-3d');
    RAISE EXCEPTION 'ingestor executed review RPC';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM 1 FROM student.profiles LIMIT 1;
    RAISE EXCEPTION 'ingestor read student data';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$negative_ingest$;

RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION rag_reviewer_test;
DO $review$
DECLARE approved_id bigint; rejected_id bigint;
BEGIN
  SELECT document_id INTO approved_id FROM rag.documents WHERE source_url='https://rls.invalid/a';
  SELECT document_id INTO rejected_id FROM rag.documents WHERE source_url='https://rls.invalid/b';
  PERFORM * FROM public.nebula_review_rag_document(approved_id,'approve','synthetic-3d');
  PERFORM * FROM public.nebula_review_rag_document(rejected_id,'reject',NULL);
  IF NOT EXISTS (SELECT 1 FROM rag.documents WHERE document_id=approved_id
      AND validation_status='documented' AND validity_status='current' AND is_current) THEN
    RAISE EXCEPTION 'reviewer approval did not produce the expected state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM rag.documents WHERE document_id=rejected_id
      AND validation_status='excluded' AND validity_status='undetermined' AND NOT is_current) THEN
    RAISE EXCEPTION 'reviewer rejection did not produce the expected state';
  END IF;
  BEGIN
    UPDATE rag.embedding_profiles SET status='retired' WHERE profile_id='synthetic-3d';
    RAISE EXCEPTION 'reviewer activated or retired a profile';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO rag.documents(title,source_url,source_type,accessed_on,validation_status,scope,
      content_sha256,metadata,is_current,information_type,authority_level,validity_status,curriculum_scope)
    VALUES ('Forbidden','https://rls.invalid/reviewer','official',DATE '2026-11-25','pending','test',
      repeat('6',64),'{}',false,'general','secondary','pending_review','general');
    RAISE EXCEPTION 'reviewer inserted a document';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$review$;

RESET SESSION AUTHORIZATION;
DO $existing_search_role$
BEGIN
  IF NOT pg_catalog.has_function_privilege('nebula_rag_api',
      'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)','EXECUTE') OR
     NOT pg_catalog.has_function_privilege('nebula_rag_api',
      'public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)','EXECUTE') OR
     pg_catalog.has_function_privilege('nebula_rag_api',
      'public.nebula_review_rag_document(bigint,text,text)','EXECUTE') OR
     pg_catalog.has_schema_privilege('nebula_rag_api','rag','USAGE') THEN
    RAISE EXCEPTION 'existing search role contract changed';
  END IF;
END;
$existing_search_role$;

SELECT 'RAG_INGESTION_RLS_ASSERTIONS_PASS' AS result;
ROLLBACK;

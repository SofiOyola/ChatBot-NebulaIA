\set ON_ERROR_STOP on

DO $assertions$
DECLARE
    actual integer;
    owner_name text;
BEGIN
    SELECT count(*) INTO actual
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'rag'
      AND c.relkind = 'r'
      AND c.relname IN ('embedding_profiles', 'documents', 'document_chunks', 'chunk_embeddings');
    IF actual <> 4 THEN
        RAISE EXCEPTION 'expected four RAG tables, found %', actual;
    END IF;

    SELECT count(*) INTO actual
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'rag'
      AND c.relname IN ('embedding_profiles', 'documents', 'document_chunks', 'chunk_embeddings')
      AND c.relrowsecurity;
    IF actual <> 4 THEN
        RAISE EXCEPTION 'RLS is not enabled on all RAG tables';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'rag' AND indexname = 'embedding_profiles_one_active_idx'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'rag' AND indexname = 'document_chunks_document_idx'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'rag' AND indexname = 'chunk_embeddings_profile_idx'
    ) THEN
        RAISE EXCEPTION 'one or more expected RAG indexes are missing';
    END IF;

    SELECT r.rolname INTO owner_name
    FROM pg_proc AS p
    JOIN pg_roles AS r ON r.oid = p.proowner
    WHERE p.oid = 'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::regprocedure;
    IF owner_name IS NULL OR owner_name IN ('anon', 'authenticated', 'service_role') THEN
        RAISE EXCEPTION 'unsafe or missing function owner';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc AS p
        WHERE p.oid = 'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)'::regprocedure
          AND p.prosecdef
          AND p.provolatile = 's'
          AND p.proconfig @> ARRAY['search_path=""']
    ) THEN
        RAISE EXCEPTION 'function security attributes do not match contract';
    END IF;

    IF has_schema_privilege('anon', 'rag', 'USAGE')
       OR has_schema_privilege('authenticated', 'rag', 'USAGE') THEN
        RAISE EXCEPTION 'client role unexpectedly has RAG schema usage';
    END IF;
    IF has_table_privilege('anon', 'rag.documents', 'SELECT')
       OR has_table_privilege('authenticated', 'rag.documents', 'SELECT') THEN
        RAISE EXCEPTION 'client role unexpectedly has direct table SELECT';
    END IF;
    IF has_function_privilege(
        'anon',
        'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)',
        'EXECUTE'
    ) OR has_function_privilege(
        'authenticated',
        'public.nebula_search_academic_chunks(extensions.vector,text,integer,real)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'client role unexpectedly has RPC EXECUTE privilege';
    END IF;
END;
$assertions$;

INSERT INTO rag.embedding_profiles (
    profile_id, provider, model, dimension, status
) VALUES (
    'synthetic-3d', 'offline-test', 'deterministic-fixture', 3, 'active'
);

INSERT INTO rag.documents (
    title, source_url, source_type, accessed_on, validation_status, scope, content_sha256
) VALUES
    ('Synthetic documented', 'https://example.invalid/documented', 'official', DATE '2026-11-25',
     'documented', 'integration-test', repeat('a', 64)),
    ('Synthetic pending', 'https://example.invalid/pending', 'official', DATE '2026-11-25',
     'pending', 'integration-test', repeat('b', 64));

INSERT INTO rag.document_chunks (
    document_id, chunk_index, locator, content, content_sha256
)
SELECT document_id, 0, 'fixture:documented', 'documented synthetic content', repeat('c', 64)
FROM rag.documents WHERE validation_status = 'documented'
UNION ALL
SELECT document_id, 0, 'fixture:pending', 'pending synthetic content', repeat('d', 64)
FROM rag.documents WHERE validation_status = 'pending';

INSERT INTO rag.chunk_embeddings (chunk_id, profile_id, embedding_dimension, embedding)
SELECT dc.chunk_id, 'synthetic-3d', 3,
       CASE d.validation_status
           WHEN 'documented' THEN '[1,0,0]'::extensions.vector
           ELSE '[0.99,0.01,0]'::extensions.vector
       END
FROM rag.document_chunks AS dc
JOIN rag.documents AS d ON d.document_id = dc.document_id;

DO $invalid_inputs$
BEGIN
    BEGIN
        PERFORM * FROM public.nebula_search_academic_chunks(NULL, 'synthetic-3d', 5, 0);
        RAISE EXCEPTION 'NULL vector was accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        PERFORM * FROM public.nebula_search_academic_chunks('[0,0,0]'::extensions.vector, 'synthetic-3d', 5, 0);
        RAISE EXCEPTION 'zero-norm vector was accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        PERFORM * FROM public.nebula_search_academic_chunks('[1,0]'::extensions.vector, 'synthetic-3d', 5, 0);
        RAISE EXCEPTION 'wrong vector dimension was accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        INSERT INTO rag.chunk_embeddings (chunk_id, profile_id, embedding_dimension, embedding)
        SELECT min(chunk_id), 'synthetic-3d', 3, '[0,0,0]'::extensions.vector
        FROM rag.document_chunks;
        RAISE EXCEPTION 'zero-norm stored embedding was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$invalid_inputs$;

DO $rpc_result$
DECLARE
    result_count integer;
    result_title text;
    result_url text;
    result_locator text;
    result_similarity real;
BEGIN
    SELECT count(*), min(document_title), min(source_url), min(locator), min(similarity)
    INTO result_count, result_title, result_url, result_locator, result_similarity
    FROM public.nebula_search_academic_chunks('[1,0,0]'::extensions.vector, 'synthetic-3d', 5, 0);

    IF result_count <> 1
       OR result_title <> 'Synthetic documented'
       OR result_url <> 'https://example.invalid/documented'
       OR result_locator <> 'fixture:documented'
       OR abs(result_similarity - 1.0) > 0.000001 THEN
        RAISE EXCEPTION 'unexpected semantic search result';
    END IF;
END;
$rpc_result$;

SELECT 'RAG01_POSTGRES_ASSERTIONS_PASS' AS result;

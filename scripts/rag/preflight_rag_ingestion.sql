-- Nébula 2.0 | Preflight remoto de solo lectura para la migración 010.
-- Compatible con Supabase SQL Editor: no usa metacomandos de psql.
BEGIN TRANSACTION READ ONLY;

SELECT current_database() AS database_name,
       current_user AS audit_user,
       pg_catalog.current_setting('server_version') AS postgres_version,
       pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

SELECT e.extname, e.extversion, n.nspname AS extension_schema, r.rolname AS extension_owner
FROM pg_catalog.pg_extension e
JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
JOIN pg_catalog.pg_roles r ON r.oid=e.extowner
WHERE e.extname='vector';

-- Una fila aquí representa una colisión que debe revisarse antes del despliegue.
SELECT r.rolname, r.rolcanlogin, r.rolsuper, r.rolcreatedb, r.rolcreaterole,
       r.rolreplication, r.rolbypassrls
FROM pg_catalog.pg_roles r
WHERE r.rolname IN ('nebula_rag_ingest','nebula_rag_reviewer');

SELECT n.nspname AS schema_name, c.relname, a.attname, pg_catalog.format_type(a.atttypid,a.atttypmod) AS data_type,
       a.attnotnull, pg_catalog.pg_get_expr(ad.adbin,ad.adrelid) AS column_default
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
WHERE n.nspname='rag' AND c.relname='documents' AND a.attname='ingested_by' AND NOT a.attisdropped;

SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_catalog.pg_policies
WHERE schemaname='rag' AND policyname IN (
  'rag_profiles_ingest_read','rag_profiles_reviewer_read','rag_documents_ingest_read',
  'rag_documents_ingest_insert','rag_documents_reviewer_read','rag_chunks_ingest_read',
  'rag_chunks_ingest_insert','rag_chunks_reviewer_read','rag_embeddings_ingest_read',
  'rag_embeddings_ingest_insert','rag_embeddings_ingest_update','rag_embeddings_reviewer_read')
ORDER BY tablename,policyname;

SELECT p.oid::pg_catalog.regprocedure AS colliding_function, r.rolname AS owner,
       p.prosecdef, p.proconfig
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
WHERE n.nspname='public' AND p.proname='nebula_review_rag_document';

-- Solo agregados operativos; no devuelve títulos, URLs, fragmentos ni metadatos.
SELECT pg_catalog.count(*) AS document_count,
       pg_catalog.count(*) FILTER (WHERE validation_status='pending') AS pending_count,
       pg_catalog.count(*) FILTER (WHERE is_current) AS current_count,
       pg_catalog.count(*) FILTER (WHERE validation_status='documented') AS documented_count
FROM rag.documents;

SELECT n.nspname AS schema_name, c.relname, c.relkind, r.rolname AS owner,
       c.relrowsecurity, c.relforcerowsecurity
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
WHERE n.nspname='rag' AND c.relname IN
  ('embedding_profiles','documents','document_chunks','chunk_embeddings')
ORDER BY c.relname;

SELECT n.nspname AS schema_name, c.relname AS sequence_name, r.rolname AS owner,
       dep.refobjid::pg_catalog.regclass AS owning_table, a.attname AS owning_column
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
LEFT JOIN pg_catalog.pg_depend dep ON dep.objid=c.oid AND dep.deptype IN ('a','i')
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=dep.refobjid AND a.attnum=dep.refobjsubid
WHERE n.nspname='rag' AND c.relkind='S'
ORDER BY c.relname;

SELECT con.conname, con.contype, con.conrelid::pg_catalog.regclass AS relation
FROM pg_catalog.pg_constraint con
WHERE con.conrelid IN ('rag.embedding_profiles'::pg_catalog.regclass,
                       'rag.documents'::pg_catalog.regclass,
                       'rag.document_chunks'::pg_catalog.regclass,
                       'rag.chunk_embeddings'::pg_catalog.regclass)
ORDER BY con.conrelid::text,con.conname;

SELECT r.rolname, r.rolsuper, r.rolcreaterole,
       pg_catalog.has_schema_privilege(current_user,'public','CREATE') AS can_create_public_function,
       pg_catalog.has_schema_privilege(current_user,'rag','USAGE') AS rag_usage
FROM pg_catalog.pg_roles r WHERE r.rolname=current_user;

SELECT c.oid::pg_catalog.regclass AS object_name, owner.rolname AS owner,
       (owner.rolname=current_user OR auditor.rolsuper OR
        pg_catalog.pg_has_role(current_user,c.relowner,'USAGE')) AS effective_owner_authority
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_roles owner ON owner.oid=c.relowner
JOIN pg_catalog.pg_roles auditor ON auditor.rolname=current_user
WHERE n.nspname='rag' AND c.relname IN
  ('embedding_profiles','documents','document_chunks','chunk_embeddings')
ORDER BY c.oid::text;

DO $preflight$
DECLARE
  missing_columns integer;
  collision_count integer;
  document_count bigint;
BEGIN
  IF pg_catalog.current_setting('transaction_read_only')<>'on' THEN
    RAISE EXCEPTION 'preflight must run in a read-only transaction';
  END IF;
  IF pg_catalog.current_setting('server_version_num')::integer < 150000 THEN
    RAISE EXCEPTION 'PostgreSQL 15 or newer is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
    WHERE e.extname='vector' AND e.extversion='0.8.2' AND n.nspname='extensions'
  ) THEN RAISE EXCEPTION 'pgvector 0.8.2 in extensions is required'; END IF;

  IF pg_catalog.to_regnamespace('rag') IS NULL OR pg_catalog.to_regnamespace('public') IS NULL THEN
    RAISE EXCEPTION 'required rag or public schema is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles
             WHERE rolname IN ('nebula_rag_ingest','nebula_rag_reviewer')) THEN
    RAISE EXCEPTION 'ingestion role name collision detected';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='nebula_review_rag_document') THEN
    RAISE EXCEPTION 'review function name collision detected';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
             WHERE attrelid=pg_catalog.to_regclass('rag.documents') AND attname='ingested_by' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'rag.documents.ingested_by already exists; review partial deployment';
  END IF;
  SELECT pg_catalog.count(*) INTO collision_count FROM pg_catalog.pg_policies
  WHERE schemaname='rag' AND policyname IN (
    'rag_profiles_ingest_read','rag_profiles_reviewer_read','rag_documents_ingest_read',
    'rag_documents_ingest_insert','rag_documents_reviewer_read','rag_chunks_ingest_read',
    'rag_chunks_ingest_insert','rag_chunks_reviewer_read','rag_embeddings_ingest_read',
    'rag_embeddings_ingest_insert','rag_embeddings_ingest_update','rag_embeddings_reviewer_read');
  IF collision_count<>0 THEN RAISE EXCEPTION 'ingestion RLS policy collision detected: %',collision_count; END IF;

  WITH required(table_name,column_name,expected_type) AS (VALUES
    ('embedding_profiles','profile_id',pg_catalog.to_regtype('pg_catalog.text')),
    ('embedding_profiles','dimension',pg_catalog.to_regtype('pg_catalog.int4')),
    ('embedding_profiles','distance_metric',pg_catalog.to_regtype('pg_catalog.text')),
    ('embedding_profiles','status',pg_catalog.to_regtype('pg_catalog.text')),
    ('documents','document_id',pg_catalog.to_regtype('pg_catalog.int8')),
    ('documents','source_url',pg_catalog.to_regtype('pg_catalog.text')),
    ('documents','validation_status',pg_catalog.to_regtype('pg_catalog.text')),
    ('documents','updated_at',pg_catalog.to_regtype('pg_catalog.timestamptz')),
    ('documents','is_current',pg_catalog.to_regtype('pg_catalog.bool')),
    ('documents','reviewed_at',pg_catalog.to_regtype('pg_catalog.timestamptz')),
    ('documents','supersedes_document_id',pg_catalog.to_regtype('pg_catalog.int8')),
    ('documents','validity_status',pg_catalog.to_regtype('pg_catalog.text')),
    ('document_chunks','chunk_id',pg_catalog.to_regtype('pg_catalog.int8')),
    ('document_chunks','document_id',pg_catalog.to_regtype('pg_catalog.int8')),
    ('chunk_embeddings','chunk_id',pg_catalog.to_regtype('pg_catalog.int8')),
    ('chunk_embeddings','profile_id',pg_catalog.to_regtype('pg_catalog.text')),
    ('chunk_embeddings','embedding_dimension',pg_catalog.to_regtype('pg_catalog.int4')),
    ('chunk_embeddings','embedding',pg_catalog.to_regtype('extensions.vector'))
  )
  SELECT pg_catalog.count(*) INTO missing_columns FROM required req
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='rag' AND c.relname=req.table_name AND a.attname=req.column_name
      AND NOT a.attisdropped AND a.atttypid=req.expected_type);
  IF missing_columns<>0 THEN RAISE EXCEPTION 'required RAG columns missing or incompatible: %',missing_columns; END IF;

  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='rag' AND c.relkind='r' AND c.relname IN
        ('embedding_profiles','documents','document_chunks','chunk_embeddings') AND c.relrowsecurity)<>4 THEN
    RAISE EXCEPTION 'four RAG tables with RLS enabled are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
                 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
                 WHERE n.nspname='rag' AND c.relname='documents_one_current_source_idx' AND i.indisunique) THEN
    RAISE EXCEPTION 'unique current-document index is missing';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute
      WHERE attrelid IN ('rag.documents'::pg_catalog.regclass,'rag.document_chunks'::pg_catalog.regclass)
        AND attname IN ('document_id','chunk_id') AND attidentity<>'')<>2 THEN
    RAISE EXCEPTION 'required identity columns or their sequences are missing';
  END IF;
  IF pg_catalog.to_regprocedure('public.nebula_search_academic_chunks(extensions.vector,text,integer,real)') IS NULL OR
     pg_catalog.to_regprocedure('public.nebula_search_academic_chunks_hybrid(text,extensions.vector,text,text,integer,real)') IS NULL OR
     NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api') THEN
    RAISE EXCEPTION 'migration 006-009 dependencies are incomplete';
  END IF;

  SELECT pg_catalog.count(*) INTO document_count FROM rag.documents;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND (rolsuper OR rolcreaterole)) THEN
    RAISE EXCEPTION 'audit user lacks CREATEROLE or superuser authority';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(current_user,'public','CREATE') THEN
    RAISE EXCEPTION 'audit user cannot create the review function in public';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_roles auditor ON auditor.rolname=current_user
    WHERE n.nspname='rag' AND c.relname IN
      ('embedding_profiles','documents','document_chunks','chunk_embeddings')
      AND NOT (c.relowner=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname=current_user)
               OR auditor.rolsuper OR pg_catalog.pg_has_role(current_user,c.relowner,'USAGE'))
  ) THEN RAISE EXCEPTION 'audit user lacks effective ownership authority over a required RAG table'; END IF;
END;
$preflight$;

SELECT CASE WHEN pg_catalog.count(*)=0
            THEN 'RAG_INGESTION_PREFLIGHT_READY'
            ELSE 'RAG_INGESTION_PREFLIGHT_PENDING_EXISTING_DOCUMENTS'
       END AS result
FROM rag.documents;
ROLLBACK;

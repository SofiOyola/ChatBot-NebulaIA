BEGIN TRANSACTION READ ONLY;
DO $precheck$
DECLARE missing_or_incompatible integer; constraint_count integer;
BEGIN
  IF current_user IN ('nebula_rag_api','nebula_rag_api_login','nebula_rag_ingest',
      'nebula_rag_ingest_login','nebula_rag_reviewer','nebula_rag_reviewer_login',
      'anon','authenticated','service_role') THEN
    RAISE EXCEPTION 'embedding profile provisioning requires a reviewed administrative session';
  END IF;
  IF pg_catalog.to_regclass('rag.embedding_profiles') IS NULL THEN
    RAISE EXCEPTION 'rag.embedding_profiles is missing';
  END IF;
  WITH required(column_name,expected_type,is_not_null) AS (VALUES
    ('profile_id',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('provider',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('model',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('dimension',pg_catalog.to_regtype('pg_catalog.int4'),true),
    ('distance_metric',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('normalization',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('status',pg_catalog.to_regtype('pg_catalog.text'),true),
    ('created_at',pg_catalog.to_regtype('pg_catalog.timestamptz'),true)
  )
  SELECT pg_catalog.count(*) INTO missing_or_incompatible FROM required req
  WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='rag.embedding_profiles'::pg_catalog.regclass
      AND a.attname=req.column_name AND NOT a.attisdropped
      AND a.atttypid=req.expected_type AND a.attnotnull=req.is_not_null);
  IF missing_or_incompatible<>0 THEN
    RAISE EXCEPTION 'embedding profile columns missing or incompatible: %',missing_or_incompatible;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class
      WHERE oid='rag.embedding_profiles'::pg_catalog.regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS is not enabled on rag.embedding_profiles';
  END IF;
  SELECT pg_catalog.count(*) INTO constraint_count FROM pg_catalog.pg_constraint
  WHERE conrelid='rag.embedding_profiles'::pg_catalog.regclass
    AND (contype='p' OR (contype='u' AND conkey IN (
      ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=conrelid AND attname='provider'),
            (SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=conrelid AND attname='model'),
            (SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=conrelid AND attname='dimension')]::smallint[],
      ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=conrelid AND attname='profile_id'),
            (SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=conrelid AND attname='dimension')]::smallint[])));
  IF constraint_count<>3 THEN
    RAISE EXCEPTION 'required embedding profile primary/unique constraints are missing';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint
      WHERE conrelid='rag.embedding_profiles'::pg_catalog.regclass AND contype='c'
        AND conname IN ('embedding_profiles_profile_id_check','embedding_profiles_provider_check',
          'embedding_profiles_model_check','embedding_profiles_dimension_check',
          'embedding_profiles_distance_metric_check','embedding_profiles_normalization_check',
          'embedding_profiles_status_check'))<>7 THEN
    RAISE EXCEPTION 'required embedding profile validation constraints are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid='rag.embedding_profiles'::pg_catalog.regclass AND a.attname='created_at'
        AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT NULL) THEN
    RAISE EXCEPTION 'embedding profile created_at default is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      WHERE i.indexrelid=pg_catalog.to_regclass('rag.embedding_profiles_one_active_idx')
        AND i.indisunique AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) IS NOT NULL) THEN
    RAISE EXCEPTION 'single-active-profile index is missing or incompatible';
  END IF;
  IF EXISTS (SELECT 1 FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768'
         OR (provider='google' AND model='gemini-embedding-001' AND dimension=768)) THEN
    RAISE EXCEPTION 'target embedding profile or provider/model/dimension tuple already exists';
  END IF;
  IF NOT pg_catalog.has_table_privilege(current_user,'rag.embedding_profiles','INSERT') THEN
    RAISE EXCEPTION 'current administrative session cannot insert the embedding profile';
  END IF;
END;
$precheck$;
SELECT pg_catalog.count(*) AS existing_profile_count,
       pg_catalog.count(*) FILTER (WHERE status='active') AS active_profile_count,
       'RAG_EMBEDDING_PROFILE_PREFLIGHT_READY' AS result
FROM rag.embedding_profiles;
ROLLBACK;

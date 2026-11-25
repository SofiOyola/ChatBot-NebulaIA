BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$
BEGIN
  IF current_user IN ('nebula_rag_api','nebula_rag_api_login','nebula_rag_ingest',
      'nebula_rag_ingest_login','nebula_rag_reviewer','nebula_rag_reviewer_login',
      'anon','authenticated','service_role') THEN
    RAISE EXCEPTION 'embedding profile provisioning requires a reviewed administrative session';
  END IF;
  IF EXISTS (SELECT 1 FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768'
         OR (provider='google' AND model='gemini-embedding-001' AND dimension=768)) THEN
    RAISE EXCEPTION 'target embedding profile or provider/model/dimension tuple already exists';
  END IF;
END;
$guard$;
INSERT INTO rag.embedding_profiles
  (profile_id,provider,model,dimension,distance_metric,normalization,status)
VALUES
  ('gemini-embedding-001-768','google','gemini-embedding-001',768,'cosine','unit_length','inactive');
DO $verify_insert$
BEGIN
  IF (SELECT pg_catalog.count(*) FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768' AND provider='google'
        AND model='gemini-embedding-001' AND dimension=768 AND distance_metric='cosine'
        AND normalization='unit_length' AND status='inactive' AND created_at IS NOT NULL)<>1 THEN
    RAISE EXCEPTION 'inserted embedding profile does not match the approved contract';
  END IF;
END;
$verify_insert$;
COMMIT;

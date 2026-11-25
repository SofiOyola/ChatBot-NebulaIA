BEGIN TRANSACTION READ ONLY;
DO $verify$
BEGIN
  IF (SELECT pg_catalog.count(*) FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768')<>1 THEN
    RAISE EXCEPTION 'expected exactly one gemini-embedding-001-768 profile';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM rag.embedding_profiles
      WHERE profile_id='gemini-embedding-001-768' AND provider='google'
        AND model='gemini-embedding-001' AND dimension=768 AND distance_metric='cosine'
        AND normalization='unit_length' AND status='inactive' AND created_at IS NOT NULL) THEN
    RAISE EXCEPTION 'embedding profile attributes do not match the approved inactive contract';
  END IF;
END;
$verify$;
SELECT profile_id,provider,model,dimension,distance_metric,normalization,status,
       created_at IS NOT NULL AS created_at_present,
       'RAG_EMBEDDING_PROFILE_VERIFIED' AS result
FROM rag.embedding_profiles WHERE profile_id='gemini-embedding-001-768';
ROLLBACK;

\set ON_ERROR_STOP on
INSERT INTO rag.embedding_profiles
    (profile_id,provider,model,dimension,distance_metric,normalization,status)
VALUES ('local-synthetic-3d','offline-test','deterministic-fixture',3,'cosine','unit_length','active');

INSERT INTO rag.documents
    (title,source_url,source_type,accessed_on,validation_status,scope,content_sha256,metadata,
     is_current,reviewed_at,information_type,authority_level,validity_status,curriculum_scope,program_key)
VALUES
 ('Old plan fixture','https://example.invalid/old','official',DATE '2026-11-25','documented','test',repeat('a',64),'{}',
  true,now(),'academic_curriculum','institutional_normative','current','old_9s_151c','systems-unab'),
 ('New 2027 fixture','https://example.invalid/new','official',DATE '2026-11-25','documented','test',repeat('b',64),'{}',
  true,now(),'academic_curriculum','institutional_informative','current','new_2027_8s_134c','systems-unab'),
 ('Pending fixture','https://example.invalid/pending','official',DATE '2026-11-25','pending','test',repeat('c',64),'{}',
  false,NULL,'institutional_policy','institutional_normative','pending_review','general',NULL),
 ('Historical fixture','https://example.invalid/historical','official',DATE '2026-11-25','documented','test',repeat('d',64),'{}',
  false,now(),'institutional_policy','institutional_normative','historical','general',NULL),
 ('Unknown scope fixture','https://example.invalid/unknown','official',DATE '2026-11-25','documented','test',repeat('e',64),'{}',
  true,now(),'general','institutional_informative','current','unknown',NULL);

INSERT INTO rag.document_chunks (document_id,chunk_index,locator,content,content_sha256)
SELECT document_id,0,'fixture:'||curriculum_scope,
       CASE curriculum_scope
         WHEN 'old_9s_151c' THEN 'old curriculum nine semesters 151 credits'
         WHEN 'new_2027_8s_134c' THEN 'new curriculum eight semesters 134 credits'
         WHEN 'unknown' THEN 'unclassified restricted content'
         ELSE title
       END,
       pg_catalog.md5(document_id::text)||pg_catalog.md5(document_id::text)
FROM rag.documents;

INSERT INTO rag.chunk_embeddings (chunk_id,profile_id,embedding_dimension,embedding)
SELECT chunk_id,'local-synthetic-3d',3,
       CASE WHEN locator IN ('fixture:old_9s_151c','fixture:new_2027_8s_134c')
                 THEN '[0.7427813527082074,0.3713906763541037,0.5570860145311556]'::extensions.vector
            WHEN locator='fixture:unknown'
                 THEN '[0.5345224838248488,0.2672612419124244,0.8017837257372732]'::extensions.vector
            ELSE '[0,0,1]'::extensions.vector END
FROM rag.document_chunks;

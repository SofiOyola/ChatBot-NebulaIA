from __future__ import annotations

import json
from dataclasses import dataclass

from .models import ExtractedDocument, SearchResult, TextChunk


def _vector_literal(values: list[float]) -> str:
    return "[" + ",".join(format(value, ".12g") for value in values) + "]"


@dataclass
class PostgresRagRepository:
    connection: object

    def stage_document(self, document: ExtractedDocument, chunks: list[TextChunk]) -> tuple[int, bool]:
        with self.connection.transaction(), self.connection.cursor() as cursor:
            cursor.execute("SELECT document_id FROM rag.documents WHERE source_url=%s AND content_sha256=%s",
                           (document.source_url, document.content_sha256))
            existing = cursor.fetchone()
            if existing:
                return int(existing[0]), False
            cursor.execute("""
                INSERT INTO rag.documents
                    (title,source_url,source_type,publisher,accessed_on,validation_status,scope,content_sha256,metadata,
                     is_current,information_type,authority_level,validity_status,
                     curriculum_scope,program_key,published_on,effective_from,effective_to,
                     content_class,authorization_status,authorization_reference,authorization_date)
                VALUES (%s,%s,%s,%s,%s,'pending','academic-rag',%s,%s::jsonb,false,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING document_id
            """, (document.title, document.source_url, document.source_type, document.publisher,
                  document.accessed_on,
                  document.content_sha256, json.dumps(document.metadata),
                  document.information_type, document.authority_level, document.validity_status,
                  document.curriculum_scope, document.program_key, document.published_on,
                  document.effective_from, document.effective_to, document.content_class,
                  document.authorization_status, document.authorization_reference,
                  document.authorization_date))
            document_id = int(cursor.fetchone()[0])
            cursor.executemany("""
                INSERT INTO rag.document_chunks
                    (document_id,chunk_index,locator,content,content_sha256,metadata)
                VALUES (%s,%s,%s,%s,%s,%s::jsonb)
            """, [(document_id, c.index, c.locator, c.content, c.content_sha256, json.dumps(c.metadata)) for c in chunks])
            return document_id, True

    def approve_document(self, document_id: int, required_profile_id: str) -> None:
        with self.connection.transaction(), self.connection.cursor() as cursor:
            cursor.execute("SELECT * FROM public.nebula_review_rag_document(%s,'approve',%s)",
                           (document_id, required_profile_id))
            if not cursor.fetchone():
                raise ValueError("document review returned no result")

    def reject_document(self, document_id: int) -> None:
        with self.connection.transaction(), self.connection.cursor() as cursor:
            cursor.execute("SELECT * FROM public.nebula_review_rag_document(%s,'reject',NULL)", (document_id,))
            if not cursor.fetchone():
                raise ValueError("document review returned no result")

    def store_embedding(self, chunk_id: int, profile_id: str, vector: list[float]) -> None:
        with self.connection.transaction(), self.connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO rag.chunk_embeddings(chunk_id,profile_id,embedding_dimension,embedding)
                VALUES (%s,%s,%s,%s::extensions.vector)
                ON CONFLICT (chunk_id,profile_id) DO UPDATE SET
                    embedding_dimension=EXCLUDED.embedding_dimension, embedding=EXCLUDED.embedding,
                    created_at=now()
                WHERE rag.chunk_embeddings.embedding::text IS DISTINCT FROM EXCLUDED.embedding::text
                   OR rag.chunk_embeddings.embedding_dimension IS DISTINCT FROM EXCLUDED.embedding_dimension
            """, (chunk_id, profile_id, len(vector), _vector_literal(vector)))

    def document_chunks(self, document_id: int) -> list[tuple[int, str]]:
        with self.connection.cursor() as cursor:
            cursor.execute("SELECT chunk_id,content FROM rag.document_chunks WHERE document_id=%s ORDER BY chunk_index",
                           (document_id,))
            return [(int(row[0]), str(row[1])) for row in cursor.fetchall()]

    def document_title(self, document_id: int) -> str:
        with self.connection.cursor() as cursor:
            cursor.execute("SELECT title FROM rag.documents WHERE document_id=%s", (document_id,))
            row = cursor.fetchone()
            if not row:
                raise ValueError("document does not exist")
            return str(row[0])

    def search(self, vector: list[float], profile_id: str, limit: int, threshold: float,
               *, query_text: str | None = None, curriculum_scope: str = "old_9s_151c") -> list[SearchResult]:
        with self.connection.cursor() as cursor:
            if query_text is not None:
                cursor.execute("SELECT document_title,source_url,locator,content,rank_score,"
                               "metadata || jsonb_build_object('information_type',information_type,"
                               "'authority_level',authority_level,'curriculum_scope',curriculum_scope) "
                               "FROM public.nebula_search_academic_chunks_hybrid("
                               "%s,%s::extensions.vector,%s,%s,%s::integer,%s::real)",
                               (query_text, _vector_literal(vector), profile_id, curriculum_scope, limit, threshold))
            else:
                cursor.execute("SELECT document_title,source_url,locator,content,similarity,metadata "
                               "FROM public.nebula_search_academic_chunks("
                               "%s::extensions.vector,%s,%s::integer,%s::real)",
                               (_vector_literal(vector), profile_id, limit, threshold))
            return [SearchResult(*row) for row in cursor.fetchall()]

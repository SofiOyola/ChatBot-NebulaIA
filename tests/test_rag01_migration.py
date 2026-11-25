from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20261124060000_rag_academic_documents.sql"


def _sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_pgvector_is_required_but_no_dimension_or_model_is_invented():
    sql = _sql()
    assert "WHERE e.extname = 'vector'" in sql
    assert "installed_schema <> 'extensions'" in sql
    assert "embedding extensions.vector NOT NULL" in sql
    assert not re.search(r"extensions\.vector\s*\(\s*\d+\s*\)", sql)
    assert "CHECK (extensions.vector_dims(embedding) = embedding_dimension)" in sql
    assert "CHECK (extensions.vector_norm(embedding) > 0)" in sql
    assert not re.search(r"INSERT\s+INTO\s+rag\.embedding_profiles", sql, re.IGNORECASE)
    assert "p_query_embedding IS NULL" in sql


def test_document_and_chunk_provenance_is_complete_and_has_no_seeded_content():
    sql = _sql()
    for fragment in (
        "CREATE TABLE IF NOT EXISTS rag.documents",
        "title text NOT NULL",
        "source_url text NOT NULL CHECK (source_url LIKE 'https://%')",
        "source_type text NOT NULL CHECK (source_type IN ('official', 'third_party'))",
        "accessed_on date NOT NULL",
        "validation_status text NOT NULL DEFAULT 'pending'",
        "content_sha256 text NOT NULL",
        "CREATE TABLE IF NOT EXISTS rag.document_chunks",
        "locator text NOT NULL",
        "content text NOT NULL",
        "metadata jsonb NOT NULL",
    ):
        assert fragment in sql
    assert not re.search(r"INSERT\s+INTO\s+rag\.(documents|document_chunks|chunk_embeddings)", sql, re.IGNORECASE)


def test_embeddings_are_bound_to_a_declared_profile_and_dimension():
    sql = _sql()
    assert "UNIQUE (profile_id, dimension)" in sql
    assert "FOREIGN KEY (profile_id, embedding_dimension)" in sql
    assert "REFERENCES rag.embedding_profiles(profile_id, dimension)" in sql
    assert "PRIMARY KEY (chunk_id, profile_id)" in sql
    assert "embedding_profiles_one_active_idx" in sql


def test_search_returns_content_with_traceable_references_only_when_documented():
    sql = _sql()
    for returned in (
        "document_title text",
        "source_url text",
        "source_type text",
        "accessed_on date",
        "validation_status text",
        "locator text",
        "content text",
        "metadata jsonb",
        "similarity real",
    ):
        assert returned in sql
    assert "d.validation_status = 'documented'" in sql
    assert "OPERATOR(extensions.<=>)" in sql
    assert "p_match_count NOT BETWEEN 1 AND 20" in sql
    assert "p_min_similarity NOT BETWEEN 0 AND 1" in sql
    assert "vector_dims(p_query_embedding) <> expected_dimension" in sql
    assert "extensions.vector_norm(p_query_embedding) <= 0" in sql


def test_all_pgvector_references_are_schema_qualified_for_empty_search_path():
    sql = _sql()
    assert "p_query_embedding extensions.vector" in sql
    assert "embedding extensions.vector NOT NULL" in sql
    assert "extensions.vector_dims(embedding)" in sql
    assert "extensions.vector_dims(p_query_embedding)" in sql
    assert "extensions.vector_norm(embedding)" in sql
    assert "extensions.vector_norm(p_query_embedding)" in sql
    assert "OPERATOR(extensions.<=>)" in sql
    assert not re.search(r"(?<!extensions\.)\bvector_(?:dims|norm)\s*\(", sql)


def test_rag_schema_is_private_and_rpc_is_the_only_client_surface():
    sql = _sql().lower()
    assert "revoke all on schema rag from public, anon, authenticated" in sql
    assert "revoke all on all tables in schema rag from public, anon, authenticated" in sql
    assert "revoke all on all sequences in schema rag from public, anon, authenticated" in sql
    assert "security definer" in sql
    assert "set search_path = ''" in sql
    assert "from public, anon, authenticated" in sql
    assert "grant execute on function public.nebula_search_academic_chunks" not in sql
    assert "grant select" not in sql
    assert "student." not in sql
    assert "auth.uid" not in sql
    assert "function_owner in ('anon', 'authenticated', 'service_role')" in sql


def test_schema_tables_and_indexes_are_safe_to_recreate():
    sql = _sql()
    for table in ("embedding_profiles", "documents", "document_chunks", "chunk_embeddings"):
        assert f"CREATE TABLE IF NOT EXISTS rag.{table}" in sql
    for index in (
        "embedding_profiles_one_active_idx",
        "document_chunks_document_idx",
        "chunk_embeddings_profile_idx",
    ):
        assert f"CREATE " in sql
        assert re.search(rf"CREATE (?:UNIQUE )?INDEX IF NOT EXISTS {index}\b", sql)
    assert "CREATE SCHEMA IF NOT EXISTS rag" in sql
    assert "CREATE OR REPLACE FUNCTION public.nebula_search_academic_chunks" in sql


def test_migration_does_not_modify_existing_academic_or_student_objects():
    sql = _sql().lower()
    assert "alter table academic." not in sql
    assert "alter table student." not in sql
    assert "create or replace function public.get_academic_history" not in sql
    assert "create or replace function public.get_credit_progress" not in sql
    assert "create or replace function public.nebula_get_subjects_by_semester" not in sql

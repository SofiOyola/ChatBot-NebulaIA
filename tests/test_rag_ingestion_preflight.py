from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "scripts/rag/preflight_rag_ingestion.sql").read_text(encoding="utf-8")


def test_preflight_is_sql_editor_compatible_and_strictly_read_only():
    normalized = " ".join(SQL.lower().split())
    assert "\\set" not in SQL
    assert "begin transaction read only" in normalized
    assert normalized.endswith("rollback;")
    uncommented = re.sub(r"--.*?$", "", SQL, flags=re.MULTILINE)
    for statement in ("insert", "update", "delete", "alter", "create", "grant", "revoke"):
        assert not re.search(rf"(?im)^\s*{statement}\b", uncommented)


def test_preflight_checks_all_migration_010_name_collisions():
    for name in (
        "nebula_rag_ingest", "nebula_rag_reviewer", "ingested_by",
        "nebula_review_rag_document", "rag_profiles_ingest_read",
        "rag_profiles_reviewer_read", "rag_documents_ingest_read",
        "rag_documents_ingest_insert", "rag_documents_reviewer_read",
        "rag_chunks_ingest_read", "rag_chunks_ingest_insert",
        "rag_chunks_reviewer_read", "rag_embeddings_ingest_read",
        "rag_embeddings_ingest_insert", "rag_embeddings_ingest_update",
        "rag_embeddings_reviewer_read",
    ):
        assert name in SQL


def test_preflight_checks_dependencies_owners_rls_sequences_and_existing_documents():
    lowered = SQL.lower()
    for marker in (
        "extensions.vector", "0.8.2", "relrowsecurity", "attidentity",
        "documents_one_current_source_idx", "effective_owner_authority",
        "rolcreaterole", "document_count", "pending_existing_documents",
        "nebula_search_academic_chunks_hybrid", "rag_ingestion_preflight_ready",
    ):
        assert marker in lowered


def test_column_contract_compares_type_oids_not_formatted_type_names():
    lowered = SQL.lower()
    assert lowered.count("pg_catalog.to_regtype(") == 18
    assert "a.atttypid=req.expected_type" in lowered
    assert "format_type(a.atttypid,a.atttypmod)=req" not in lowered
    assert "pg_catalog.to_regtype('extensions.vector')" in lowered


def test_preflight_does_not_read_document_content_or_private_schemas():
    lowered = SQL.lower()
    for forbidden in (
        "rag.document_chunks.content", "select content", "select title",
        "student.", "auth.", "memory", "get_academic_history", "get_credit_progress",
    ):
        assert forbidden not in lowered

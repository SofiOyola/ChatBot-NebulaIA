from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261124100000_rag_ingestion_roles.sql").read_text(encoding="utf-8")
REPOSITORY = (ROOT / "src/nebula_rag/repository.py").read_text(encoding="utf-8")
VERIFIER = (ROOT / "scripts/rag/verify_rag_ingestion_security.sql").read_text(encoding="utf-8")


def test_ingestion_and_review_roles_are_non_login_non_admin_and_separate():
    normalized = " ".join(SQL.lower().split())
    for role in ("nebula_rag_ingest", "nebula_rag_reviewer"):
        assert role in normalized
    assert "nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls" in normalized
    assert "grant nebula_rag_reviewer to nebula_rag_ingest" not in normalized
    assert "grant nebula_rag_ingest to nebula_rag_reviewer" not in normalized


def test_ingestor_has_no_delete_ddl_review_or_profile_activation_permission():
    grants = [line.lower() for line in SQL.splitlines() if line.strip().lower().startswith("grant ")]
    assert not any(" delete " in f" {line} " for line in grants)
    assert "grant execute on function public.nebula_review_rag_document" in SQL.lower()
    assert "to nebula_rag_reviewer" in SQL.lower()
    assert "from public,anon,authenticated,nebula_rag_api,nebula_rag_ingest" in SQL.lower()
    assert "update (status)" not in SQL.lower()


def test_rls_owns_staged_rows_and_review_rpc_requires_complete_embeddings():
    assert "ingested_by name not null default session_user" in SQL.lower()
    assert "ingested_by=session_user" in SQL.lower()
    assert "ingested_by=current_user" not in SQL.lower()
    assert "all document chunks require the approved embedding profile" in SQL
    assert "security definer set search_path=''" in SQL.lower()


def test_migration_never_references_student_auth_memory_or_existing_personal_rpcs():
    lowered = SQL.lower()
    for forbidden in ("student.", "auth.", "memory", "get_academic_history", "get_credit_progress"):
        assert forbidden not in lowered


def test_stage_preserves_current_revision_and_review_is_routed_through_rpc():
    assert "set is_current=false" not in REPOSITORY.lower()
    assert "nebula_review_rag_document" in REPOSITORY
    assert "required_profile_id: str" in REPOSITORY


def test_post_deployment_verifier_rejects_all_public_client_execute_paths():
    lowered = VERIFIER.lower()
    assert "pg_catalog.aclexplode" in lowered
    assert "acl.grantee=0" in lowered
    for role in ("anon", "authenticated", "service_role", "nebula_rag_api", "nebula_rag_ingest"):
        assert role in lowered

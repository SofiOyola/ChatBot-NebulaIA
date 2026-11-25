from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "scripts/rag/preflight_rag_demo_guard.sql").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/rag/verify_rag_demo_guard.sql").read_text(encoding="utf-8")


def test_preflight_is_sql_editor_compatible_and_read_only():
    normalized = " ".join(SQL.lower().split())
    assert normalized.startswith("begin transaction read only;")
    assert normalized.endswith("rollback;")
    assert "\\set" not in SQL
    uncommented = re.sub(r"--.*?$", "", SQL, flags=re.MULTILINE)
    for statement in ("insert", "update", "delete", "alter", "create", "grant", "revoke", "drop"):
        assert not re.search(rf"(?im)^\s*{statement}\b", uncommented)


def test_preflight_checks_dependencies_collisions_security_and_existing_documents():
    lowered = SQL.lower()
    for marker in (
        "0.8.2", "extensions", "content_class", "authorization_status",
        "documents_demo_safety_check", "nebula_search_academic_chunks_hybrid",
        "search_path=\"\"", "nebula_rag_api", "expected 12 ingestion/reviewer policies",
        "pending_existing_documents", "rag_demo_guard_preflight_ready",
    ):
        assert marker in lowered


def test_preflight_uses_oid_column_comparisons_and_never_reads_content():
    lowered = SQL.lower()
    assert lowered.count("pg_catalog.to_regtype(") == 9
    assert "a.atttypid=req.expected_type" in lowered
    for forbidden in ("select content", "select title", "student.", "auth.", "memory"):
        assert forbidden not in lowered


def test_post_deployment_verifier_is_read_only_and_checks_filters_acl_rls_and_columns():
    normalized = " ".join(VERIFY.lower().split())
    assert normalized.startswith("begin transaction read only;") and normalized.endswith("rollback;")
    for marker in ("rag_demo_guard_verified", "d.content_class=''institutional''",
                   "aclexplode", "acl.grantee=0", "policy_count<>12",
                   "has_column_privilege('nebula_rag_ingest'"):
        assert marker in normalized

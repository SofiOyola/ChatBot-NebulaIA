from pathlib import Path


SQL = (Path(__file__).resolve().parents[1] / "scripts/rag/verify_rag_deployment.sql").read_text(encoding="utf-8")


def test_verifier_is_sql_editor_compatible_and_read_only():
    normalized = " ".join(SQL.lower().split())
    assert "\\set" not in SQL
    assert "begin transaction read only" in normalized
    assert normalized.endswith("rollback;")
    for statement in (" insert ", " update ", " delete ", " alter ", " create ", " grant ", " revoke "):
        assert statement not in f" {normalized} "


def test_public_execute_is_read_from_acl_grantee_zero():
    assert "aclexplode" in SQL
    assert "acl.grantee=0" in SQL
    assert "has_function_privilege('PUBLIC'" not in SQL


def test_verifier_checks_exact_signatures_and_effective_vector_usage():
    assert SQL.count("to_regprocedure(") >= 4
    assert "has_type_privilege('nebula_rag_api','extensions.vector','USAGE')" in SQL
    assert "acldefault('T',t.typowner)" in SQL
    assert "vector_usage_effective" in SQL
    assert "RAG_DEPLOYMENT_SQL_VERIFIED" in SQL

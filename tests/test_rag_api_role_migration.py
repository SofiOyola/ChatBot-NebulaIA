from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261124090000_rag_api_role.sql").read_text(encoding="utf-8")


def test_role_is_non_login_and_has_no_administrative_attributes():
    normalized = " ".join(SQL.lower().split())
    assert "create role nebula_rag_api nologin nosuperuser nocreatedb nocreaterole" in normalized
    assert "noreplication nobypassrls" in normalized
    assert "password" not in normalized
    assert "pg_catalog.pg_auth_members" in SQL


def test_role_has_no_direct_rag_table_or_schema_access():
    assert "REVOKE ALL ON SCHEMA rag FROM nebula_rag_api" in SQL
    assert "REVOKE ALL ON ALL TABLES IN SCHEMA rag FROM nebula_rag_api" in SQL
    assert "GRANT SELECT" not in SQL.upper()


def test_only_search_rpc_execution_is_granted():
    grants = [line.strip() for line in SQL.splitlines() if line.strip().upper().startswith("GRANT EXECUTE")]
    assert len(grants) == 2
    assert "nebula_search_academic_chunks(" in grants[0]
    assert "nebula_search_academic_chunks_hybrid(" in grants[1]

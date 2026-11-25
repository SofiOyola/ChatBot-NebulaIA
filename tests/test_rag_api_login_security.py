from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "scripts/rag/Create-RagApiLogin.ps1").read_text(encoding="utf-8")
PRECHECK = (ROOT / "scripts/rag/precheck_rag_api_login.sql").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/rag/verify_rag_api_login.sql").read_text(encoding="utf-8")


def test_password_is_never_interpolated_into_sql_or_command_arguments():
    assert "RAG_TARGET_DATABASE_URL" not in SCRIPT
    assert "PASSWORD '$" not in SCRIPT
    assert "\\password nebula_rag_api_login" in SCRIPT
    assert "PSQL_HISTORY='nul'" in SCRIPT


def test_role_stays_nologin_until_password_command_succeeds():
    assert SCRIPT.index("CREATE ROLE nebula_rag_api_login NOLOGIN") < SCRIPT.index("\\password nebula_rag_api_login")
    assert SCRIPT.index("\\password nebula_rag_api_login") < SCRIPT.index("ALTER ROLE nebula_rag_api_login LOGIN")
    assert "GRANT nebula_rag_api TO nebula_rag_api_login" in SCRIPT


def test_precheck_and_verifier_are_read_only_and_cover_private_data():
    for sql in (PRECHECK, VERIFY):
        normalized = " ".join(sql.lower().split())
        assert "begin transaction read only" in normalized
        assert normalized.endswith("rollback;")
    assert "rag.documents" in VERIFY and "student.profiles" in VERIFY
    assert "RAG_LIMITED_LOGIN_VERIFIED" in VERIFY

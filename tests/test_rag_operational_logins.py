from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CREATE = (ROOT / "scripts/rag/Create-RagOperationalLogin.ps1").read_text(encoding="utf-8")
TEST = (ROOT / "scripts/rag/Test-RagOperationalLogin.ps1").read_text(encoding="utf-8")
PRECHECK = (ROOT / "scripts/rag/precheck_rag_operational_login.sql").read_text(encoding="utf-8")
INGEST = (ROOT / "scripts/rag/verify_rag_ingest_login.sql").read_text(encoding="utf-8")
REVIEWER = (ROOT / "scripts/rag/verify_rag_reviewer_login.sql").read_text(encoding="utf-8")


def test_creation_reuses_one_fixed_identity_map_and_safe_password_sequence():
    assert "[ValidateSet('Ingest','Reviewer')]" in CREATE
    for value in ("nebula_rag_ingest_login", "nebula_rag_reviewer_login",
                  "nebula_rag_ingest", "nebula_rag_reviewer"):
        assert value in CREATE
    assert "NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS" in CREATE
    assert CREATE.index("CREATE ROLE $loginName NOLOGIN") < CREATE.index('\\password $loginName')
    assert CREATE.index('\\password $loginName') < CREATE.index("ALTER ROLE $loginName LOGIN")
    assert "32+" in CREATE and "EXCLUSIVA ALEATORIA" in CREATE
    assert CREATE.index("Read-only operational login precheck failed") < CREATE.index("APLICAR CREACION DE $loginName")
    assert CREATE.index("APLICAR CREACION DE $loginName") < CREATE.index("CREATE ROLE $loginName NOLOGIN")


def test_passwords_are_not_parameters_files_history_or_command_arguments():
    assert "[SecureString]" not in CREATE
    assert "Password=" not in CREATE and "password=" not in CREATE
    assert "PSQL_HISTORY='nul'" in CREATE and "PSQL_HISTORY='nul'" in TEST
    assert "Read-Host 'Administrative database password' -AsSecureString" in CREATE
    assert "-AsSecureString" in TEST
    assert "-c \"\\password $loginName\"" in CREATE


def test_precheck_and_verifiers_are_read_only_and_cover_exclusive_membership():
    assert PRECHECK.lstrip().lower().startswith("begin transaction read only;")
    for sql in (PRECHECK, INGEST, REVIEWER):
        assert sql.strip().lower().endswith("rollback;")
    assert "membership_count<>1" in INGEST and "membership_count<>1" in REVIEWER
    assert "session_user<>'nebula_rag_ingest_login'" in INGEST
    assert "session_user<>'nebula_rag_reviewer_login'" in REVIEWER
    assert "nebula_rag_api_login" in PRECHECK
    assert "existing search login is missing or its security contract changed" in PRECHECK
    assert "new operational login membership is not exclusive" in CREATE


def test_verifiers_reject_admin_ddl_private_schema_and_cross_role_capabilities():
    combined = (INGEST + REVIEWER).lower()
    for marker in ("rolsuper", "rolcreatedb", "rolcreaterole", "rolreplication", "rolbypassrls",
                   "'student','auth','memory'", "'public','create'", "'rag','create'"):
        assert marker in combined
    assert "nebula_review_rag_document" in INGEST and "nebula_review_rag_document" in REVIEWER
    assert "embedding_profiles','status','update'" in INGEST.lower()
    assert "chunk_embeddings','insert,update,delete'" in REVIEWER.lower()


def test_powershell_does_not_contain_literal_secret_assignments():
    for script in (CREATE, TEST):
        assert not re.search(r"(?i)(password|secret|token)\s*=\s*['\"][^$'\"]+['\"]", script)

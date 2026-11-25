from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PRECHECK = (ROOT / "scripts/rag/precheck_rag_embedding_profile.sql").read_text(encoding="utf-8")
CREATE = (ROOT / "scripts/rag/create_rag_embedding_profile.sql").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/rag/verify_rag_embedding_profile.sql").read_text(encoding="utf-8")


def test_precheck_and_verifier_are_read_only_sql_editor_scripts():
    for sql in (PRECHECK, VERIFY):
        normalized = " ".join(sql.lower().split())
        assert normalized.startswith("begin transaction read only;")
        assert normalized.endswith("rollback;")
        uncommented = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
        for statement in ("insert", "update", "delete", "alter", "create", "grant", "revoke", "drop"):
            assert not re.search(rf"(?im)^\s*{statement}\b", uncommented)


def test_precheck_uses_oid_types_and_checks_the_complete_table_contract():
    assert PRECHECK.lower().count("pg_catalog.to_regtype(") == 8
    for column in ("profile_id", "provider", "model", "dimension", "distance_metric",
                   "normalization", "status", "created_at"):
        assert f"'{column}'" in PRECHECK
    assert "relrowsecurity" in PRECHECK
    assert "embedding_profiles_one_active_idx" in PRECHECK
    assert "embedding_profiles_status_check" in PRECHECK
    assert "embedding profile created_at default is missing" in PRECHECK
    assert "RAG_EMBEDDING_PROFILE_PREFLIGHT_READY" in PRECHECK


def test_creation_is_one_atomic_inactive_insert_without_upsert_or_mutation():
    normalized = " ".join(CREATE.lower().split())
    assert normalized.startswith("begin;") and normalized.endswith("commit;")
    assert CREATE.lower().count("insert into rag.embedding_profiles") == 1
    assert "on conflict" not in normalized
    assert not re.search(r"(?im)^\s*(update|delete|alter|grant|revoke|drop)\b", CREATE)
    assert "'gemini-embedding-001-768','google','gemini-embedding-001',768,'cosine','unit_length','inactive'" in normalized


def test_operational_roles_are_blocked_and_verifier_checks_exact_attributes():
    for role in ("nebula_rag_api_login", "nebula_rag_ingest_login", "nebula_rag_reviewer_login"):
        assert role in PRECHECK and role in CREATE
    for value in ("gemini-embedding-001-768", "google", "gemini-embedding-001",
                  "768", "cosine", "unit_length", "inactive"):
        assert value in VERIFY
    assert "RAG_EMBEDDING_PROFILE_VERIFIED" in VERIFY

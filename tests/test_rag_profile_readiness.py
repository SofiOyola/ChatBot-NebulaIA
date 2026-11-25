from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261124120000_rag_profile_readiness.sql").read_text(encoding="utf-8")
PREFLIGHT = (ROOT / "scripts/rag/preflight_rag_profile_readiness.sql").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/rag/verify_rag_profile_readiness.sql").read_text(encoding="utf-8")


def test_migration_has_exact_contract_and_atomic_boundaries():
    normalized = " ".join(MIGRATION.lower().split())
    assert normalized.startswith("-- nebula 2.0 | migracion 012")
    assert "begin;" in normalized and normalized.endswith("commit;")
    assert "nebula_get_rag_profile_readiness(p_profile_id text)" in normalized
    assert "returns table (ready boolean, profile_id text, dimension integer)" in normalized
    assert "sqlstate='22023'" not in normalized  # ERRCODE is used, not an invalid SQLSTATE clause.
    assert "errcode='22023'" in normalized


def test_readiness_requires_the_complete_approved_profile_contract_and_never_null():
    normalized = " ".join(MIGRATION.lower().split())
    for marker in ("gemini-embedding-001-768", "ep.status='active'", "ep.distance_metric='cosine'",
                   "ep.dimension=768", "ep.provider='google'", "ep.model='gemini-embedding-001'",
                   "ep.normalization='unit_length'", "coalesce(v_ready,false)"):
        assert marker in normalized
    assert "from rag.embedding_profiles as ep" in normalized
    assert "execute format" not in normalized and "execute '" not in normalized


def test_migration_uses_security_definer_empty_search_path_and_minimal_acl():
    normalized = " ".join(MIGRATION.lower().split())
    assert "security definer" in normalized and "set search_path = ''" in normalized
    assert "grant execute on function public.nebula_get_rag_profile_readiness(text) to nebula_rag_api" in normalized
    for role in ("public", "anon", "authenticated", "service_role", "nebula_rag_api_login",
                 "nebula_rag_ingest", "nebula_rag_reviewer"):
        assert role in normalized
    assert "grant select" not in normalized and "grant usage on schema rag" not in normalized


def test_preflight_is_read_only_and_checks_dependencies_collision_and_profile_values():
    normalized = " ".join(PREFLIGHT.lower().split())
    assert normalized.startswith("begin transaction read only;") and normalized.endswith("rollback;")
    uncommented = re.sub(r"--.*?$", "", PREFLIGHT, flags=re.MULTILINE)
    for statement in ("insert", "update", "delete", "alter", "create", "grant", "revoke", "drop"):
        assert not re.search(rf"(?im)^\s*{statement}\b", uncommented)
    for marker in ("rag.embedding_profiles", "to_regprocedure", "name/signature collision",
                   "provider='google'", "model='gemini-embedding-001'", "dimension=768",
                   "normalization='unit_length'", "nebula_rag_api_login", "pg_has_role",
                   "rag_profile_readiness_preflight_ready"):
        assert marker in normalized


def test_verifier_is_read_only_and_detects_signature_owner_acl_and_result_corruption():
    normalized = " ".join(VERIFY.lower().split())
    assert normalized.startswith("begin transaction read only;") and normalized.endswith("rollback;")
    for marker in ("prosecdef", "provolatile='s'", "search_path=\"\"", "proallargtypes",
                   "aclexplode", "acl.grantee", "unexpected_execute", "has_table_privilege",
                   "nebula_rag_api_login", "pg_has_role", "existing search rpc permissions changed", "actual_ready is null",
                   "rag_profile_readiness_verified"):
        assert marker in normalized
    assert "has_function_privilege('public'" not in normalized

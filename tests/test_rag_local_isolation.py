from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / "infrastructure/rag-local"


def test_local_stack_has_unique_loopback_only_surfaces_and_resources():
    compose = (LOCAL / "compose.yaml").read_text(encoding="utf-8")
    assert "name: nebula-rag-local-it" in compose
    assert "container_name: nebula-rag-local-postgres" in compose
    assert "container_name: nebula-rag-local-postgrest" in compose
    assert '"127.0.0.1:55432:5432"' in compose
    assert '"127.0.0.1:53000:3000"' in compose
    assert "nebula-rag-local-pgdata" in compose
    assert "infrastructure/n8n" not in compose


def test_local_stack_mounts_only_the_six_rag_migrations():
    compose = (LOCAL / "compose.yaml").read_text(encoding="utf-8")
    migrations = [line for line in compose.splitlines() if "supabase/migrations/" in line]
    assert len(migrations) == 6
    assert "20261124060000_rag_academic_documents.sql" in compose
    assert "20261124070000_rag_document_lifecycle.sql" in compose
    assert "20261124080000_rag_classification_hybrid_search.sql" in compose
    assert "20261124090000_rag_api_role.sql" in compose
    assert "20261124100000_rag_ingestion_roles.sql" in compose
    assert "20261124110000_rag_demo_content_guard.sql" in compose
    assert "20261124015000" not in compose and "20261124040000" not in compose


def test_local_scripts_never_call_remote_supabase_commands():
    executable_suffixes = {".ps1", ".sh", ".sql", ".yaml"}
    text = "\n".join(path.read_text(encoding="utf-8") for path in LOCAL.rglob("*.*")
                     if path.is_file() and path.suffix in executable_suffixes).lower()
    for forbidden in ("supabase link", "supabase db push", "supabase db reset"):
        assert forbidden not in text
    assert "icsekpkuheckfkgkqosg" not in text
